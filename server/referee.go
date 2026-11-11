package main

// Referee orchestration (P4 stage 3). One dedicated Godot referee
// PROCESS per ranked match: the server spawns the same game project
// headless with --referee flags, handing it the room code and a
// one-time token (the room stores only the token's hash). The
// referee's stdout/stderr are folded into the server log with a
// referee[CODE] prefix. Processes are reaped when their room closes,
// when they exit on their own after reporting a result, or at a
// hard match timeout. Deliberately simple: no pooling (see README
// honest limits).

import (
	"fmt"
	"io"
	"log"
	"os/exec"
	"strings"
	"sync"
	"time"
)

const DefaultRefereeTimeout = 45 * time.Minute

type Orchestrator struct {
	GodotPath   string        // headless Godot binary ("" = orchestration off)
	ProjectPath string        // Godot project directory for the referee
	RelayURL    string        // ws:// URL the referee connects back to
	ExtraArgs   []string      // appended verbatim (tests use the test-kill hook)
	Timeout     time.Duration // hard cap per match; 0 = DefaultRefereeTimeout

	mu    sync.Mutex
	procs map[string]*exec.Cmd
	hub   *Hub
}

// buildArgs is the exact referee command line (unit-tested).
func (o *Orchestrator) buildArgs(code, token string) []string {
	args := []string{
		"--headless", "--fixed-fps", "30",
		"--path", o.ProjectPath,
		"--",
		"--referee",
		"--referee-room=" + code,
		"--referee-token=" + token,
		"--referee-url=" + o.RelayURL,
	}
	return append(args, o.ExtraArgs...)
}

// linePrefixWriter forwards a child's output into the server log,
// one line at a time, each tagged with the room.
type linePrefixWriter struct {
	prefix string
	buf    []byte
}

func (w *linePrefixWriter) Write(p []byte) (int, error) {
	w.buf = append(w.buf, p...)
	for {
		i := indexByte(w.buf, '\n')
		if i < 0 {
			break
		}
		line := strings.TrimRight(string(w.buf[:i]), "\r")
		if line != "" {
			log.Printf("%s %s", w.prefix, line)
		}
		w.buf = w.buf[i+1:]
	}
	return len(p), nil
}

func (w *linePrefixWriter) Flush() {
	if len(w.buf) > 0 {
		log.Printf("%s %s", w.prefix, strings.TrimRight(string(w.buf), "\r"))
		w.buf = nil
	}
}

func indexByte(b []byte, c byte) int {
	for i, x := range b {
		if x == c {
			return i
		}
	}
	return -1
}

var _ io.Writer = (*linePrefixWriter)(nil)

// SpawnReferee starts the referee process for a ranked room.
func (o *Orchestrator) SpawnReferee(code, token string) error {
	if o.GodotPath == "" {
		return fmt.Errorf("referee orchestration disabled (no -referee-godot)")
	}
	cmd := exec.Command(o.GodotPath, o.buildArgs(code, token)...)
	out := &linePrefixWriter{prefix: "referee[" + code + "]:"}
	cmd.Stdout = out
	cmd.Stderr = out
	if err := cmd.Start(); err != nil {
		return err
	}
	o.mu.Lock()
	if o.procs == nil {
		o.procs = make(map[string]*exec.Cmd)
	}
	o.procs[code] = cmd
	o.mu.Unlock()
	log.Printf("referee[%s]: spawned pid %d", code, cmd.Process.Pid)
	timeout := o.Timeout
	if timeout <= 0 {
		timeout = DefaultRefereeTimeout
	}
	time.AfterFunc(timeout, func() {
		log.Printf("referee[%s]: match timeout (%s) — killing", code, timeout)
		o.ReapReferee(code)
	})
	go func() {
		err := cmd.Wait()
		out.Flush()
		o.mu.Lock()
		if cur, ok := o.procs[code]; ok && cur == cmd {
			delete(o.procs, code)
		}
		o.mu.Unlock()
		if err != nil {
			log.Printf("referee[%s]: exited: %v", code, err)
		} else {
			log.Printf("referee[%s]: exited cleanly", code)
		}
		if o.hub != nil {
			o.hub.RefereeDisconnect(code)
		}
	}()
	return nil
}

// ReapReferee kills the room's referee process if it is still
// running (room closed / match timeout). The Wait goroutine does
// the bookkeeping.
func (o *Orchestrator) ReapReferee(code string) {
	o.mu.Lock()
	cmd := o.procs[code]
	o.mu.Unlock()
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
	}
}

// Running reports whether a referee process is alive for the room
// (status/tests).
func (o *Orchestrator) Running(code string) bool {
	o.mu.Lock()
	defer o.mu.Unlock()
	_, ok := o.procs[code]
	return ok
}
