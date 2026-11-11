package main

// Minimal RFC6455 WebSocket server built on the standard library only
// (no external modules — the sandbox cannot be trusted to fetch them).
//
// Scope: what a game relay needs — HTTP upgrade handshake, text frames
// (with fragmentation reassembly), ping/pong, close. Client frames are
// masked per RFC and unmasked here; server frames are sent unmasked.

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
)

const wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
const maxMessageBytes = 1 << 20 // 1 MiB

type wsConn struct {
	conn    net.Conn
	reader  *bufio.Reader
	wmu     sync.Mutex // serialises writes (ticker + handlers race)
	onText  func([]byte)
	onGone  func()
	closed  bool
	cmu     sync.Mutex
	lastFin bool // FIN bit of the most recent frame (readLoop only)
}

func computeAccept(key string) string {
	h := sha1.New()
	io.WriteString(h, key+wsGUID)
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

// upgradeWS hijacks an HTTP request into a WebSocket connection.
func upgradeWS(w http.ResponseWriter, r *http.Request) (*wsConn, error) {
	if !strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
		return nil, errors.New("not a websocket upgrade")
	}
	key := r.Header.Get("Sec-WebSocket-Key")
	if key == "" {
		return nil, errors.New("missing Sec-WebSocket-Key")
	}
	hj, ok := w.(http.Hijacker)
	if !ok {
		return nil, errors.New("hijacking unsupported")
	}
	nc, brw, err := hj.Hijack()
	if err != nil {
		return nil, err
	}
	resp := "HTTP/1.1 101 Switching Protocols\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Accept: " + computeAccept(key) + "\r\n\r\n"
	if _, err := brw.WriteString(resp); err != nil {
		nc.Close()
		return nil, err
	}
	if err := brw.Flush(); err != nil {
		nc.Close()
		return nil, err
	}
	return &wsConn{conn: nc, reader: brw.Reader}, nil
}

// readLoop consumes frames until the connection dies; text messages are
// delivered to onText, disconnects to onGone (exactly once).
func (c *wsConn) readLoop() {
	defer func() {
		c.markClosed()
		if c.onGone != nil {
			c.onGone()
		}
	}()
	var frag []byte
	fragmented := false
	for {
		payload, opcode, err := c.readFrame()
		if err != nil {
			return
		}
		switch opcode {
		case 0x0: // continuation
			if !fragmented {
				return
			}
			frag = append(frag, payload...)
			// FIN detection happens in readFrame; simplified: we treat
			// each frame as complete unless opcode==1 with fin=false,
			// which readFrame reports via opcode 0x81 handling below.
			if c.lastFin {
				if c.onText != nil {
					c.onText(frag)
				}
				frag = nil
				fragmented = false
			}
		case 0x1, 0x2: // text / binary (treated as text payloads)
			if c.lastFin {
				if c.onText != nil {
					c.onText(payload)
				}
			} else {
				frag = append([]byte{}, payload...)
				fragmented = true
			}
		case 0x8: // close
			c.sendFrame(0x8, payload)
			return
		case 0x9: // ping -> pong
			c.sendFrame(0xA, payload)
		case 0xA: // pong: ignore
		}
	}
}

func (c *wsConn) readFrame() (payload []byte, opcode byte, err error) {
	var hdr [2]byte
	if _, err := io.ReadFull(c.reader, hdr[:]); err != nil {
		return nil, 0, err
	}
	c.lastFin = hdr[0]&0x80 != 0
	opcode = hdr[0] & 0x0F
	masked := hdr[1]&0x80 != 0
	length := uint64(hdr[1] & 0x7F)
	switch length {
	case 126:
		var b [2]byte
		if _, err := io.ReadFull(c.reader, b[:]); err != nil {
			return nil, 0, err
		}
		length = uint64(binary.BigEndian.Uint16(b[:]))
	case 127:
		var b [8]byte
		if _, err := io.ReadFull(c.reader, b[:]); err != nil {
			return nil, 0, err
		}
		length = binary.BigEndian.Uint64(b[:])
	}
	if length > maxMessageBytes {
		return nil, 0, errors.New("message too large")
	}
	var maskKey [4]byte
	if masked {
		if _, err := io.ReadFull(c.reader, maskKey[:]); err != nil {
			return nil, 0, err
		}
	}
	payload = make([]byte, length)
	if _, err := io.ReadFull(c.reader, payload); err != nil {
		return nil, 0, err
	}
	if masked {
		for i := range payload {
			payload[i] ^= maskKey[i%4]
		}
	}
	return payload, opcode, nil
}

func (c *wsConn) sendFrame(opcode byte, payload []byte) error {
	c.wmu.Lock()
	defer c.wmu.Unlock()
	if c.isClosed() {
		return errors.New("connection closed")
	}
	var hdr []byte
	hdr = append(hdr, 0x80|opcode)
	switch {
	case len(payload) < 126:
		hdr = append(hdr, byte(len(payload)))
	case len(payload) < 65536:
		hdr = append(hdr, 126, byte(len(payload)>>8), byte(len(payload)))
	default:
		hdr = append(hdr, 127)
		var b [8]byte
		binary.BigEndian.PutUint64(b[:], uint64(len(payload)))
		hdr = append(hdr, b[:]...)
	}
	if _, err := c.conn.Write(hdr); err != nil {
		return err
	}
	_, err := c.conn.Write(payload)
	return err
}

// SendText delivers one JSON text message.
func (c *wsConn) SendText(data []byte) error {
	return c.sendFrame(0x1, data)
}

func (c *wsConn) markClosed() {
	c.cmu.Lock()
	already := c.closed
	c.closed = true
	c.cmu.Unlock()
	if !already {
		c.conn.Close()
	}
}

func (c *wsConn) isClosed() bool {
	c.cmu.Lock()
	defer c.cmu.Unlock()
	return c.closed
}

// Close terminates the connection (idempotent).
func (c *wsConn) Close() { c.markClosed() }
