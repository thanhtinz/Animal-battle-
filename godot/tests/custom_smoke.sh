#!/usr/bin/env bash
# Empire Age 15a custom-match expansion smoke test.
#
# Four headless clients against one relay:
#   A (host)    creates a PUBLIC, passworded, observer-friendly
#               room; once C is in, A kicks C, then transfers
#               host to B and readies up.
#   B (browser) lists rooms (sees A's room, pass=1 obs=1), joins
#               with the WRONG password (server error is the
#               evidence), then with the right one; becomes host
#               via the transfer and starts the match.
#   C (victim)  joins as slot 2 and gets kicked (and banned) in
#               the lobby; its client exits on the kicked notice.
#   D (watcher) observes MID-MATCH: freezes for the host-served
#               snapshot, fires one raw command the server must
#               reject, then runs in checksum agreement with A.
#
# The scripted TC kill at tick 120 eliminates slot 1 (B), so the
# new host B reports defeat and A victory — host transfer did not
# corrupt the running match's result path.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-custom-smoke.XXXXXX)
echo "smoke workdir: $WORK"
PASS="mk123"
GODOT_FLAGS="--headless --fixed-fps 30 --path . --"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR"

wait_line() { # wait_line <file> <pattern> <seconds>
	local f=$1 pat=$2 secs=$3 n=0
	while [ $n -lt "$secs" ]; do
		grep -q "$pat" "$f" 2>/dev/null && return 0
		sleep 1; n=$((n+1))
	done
	return 1
}

# --- A: host creates the public passworded room ----------------
timeout 300 "$GODOT" $GODOT_FLAGS \
	--mp-auto=create --mp-name=ChuPhong \
	--mp-room-name="Phong Cua Chu" --mp-room-pass="$PASS" \
	--mp-room-public --mp-room-obs --mp-hold=260 \
	--mp-kick-slot=2 --mp-transfer-slot=1 > "$WORK/a.log" 2>&1 &
A=$!
CODE=""
for _ in $(seq 1 60); do
	CODE=$(grep -o "MPLOG room code=[A-Z0-9]*" "$WORK/a.log" 2>/dev/null | head -1 | cut -d= -f2)
	[ -n "$CODE" ] && break
	sleep 1
done
echo "room code: ${CODE:-<none>}"
if [ -z "$CODE" ]; then
	echo "FAIL: host never created a room (see $WORK/a.log)"
	kill $A $SRV 2>/dev/null
	exit 1
fi

# --- B: browse -> wrong password -> right password -------------
timeout 300 "$GODOT" $GODOT_FLAGS \
	--mp-auto=browse --mp-name=KhachB --mp-code="$CODE" \
	--mp-wrong-pass=sai --mp-room-pass="$PASS" \
	--mp-hold=260 > "$WORK/b.log" 2>&1 &
B=$!
if ! wait_line "$WORK/b.log" "MPLOG room code=$CODE slot=1" 60; then
	echo "FAIL: browser client never landed in the room as slot 1 (see $WORK/b.log)"
	kill $A $B $SRV 2>/dev/null
	exit 1
fi
echo "B joined as slot 1"

# --- C: joins as slot 2, gets kicked by A ----------------------
timeout 120 "$GODOT" $GODOT_FLAGS \
	--mp-auto=join --mp-code="$CODE" --mp-name=NanNhan \
	--mp-room-pass="$PASS" > "$WORK/c.log" 2>&1 &
C=$!
if ! wait_line "$WORK/c.log" "MPLOG kicked" 90; then
	echo "FAIL: victim was never kicked (see $WORK/c.log and $WORK/a.log)"
	kill $A $B $C $SRV 2>/dev/null
	exit 1
fi
echo "C kicked"

# --- match starts (B hosts after the transfer) -----------------
# D joins as soon as the match is live: a mid-match join all the
# same (D was not in the room at the start), and the observer's
# scene boot gets the whole match to complete in.
if ! wait_line "$WORK/a.log" "MPLOG auto in match" 120; then
	echo "FAIL: match never started (see $WORK/a.log $WORK/b.log)"
	kill $A $B $C $SRV 2>/dev/null
	exit 1
fi

# --- D: mid-match observer -------------------------------------
timeout 300 "$GODOT" $GODOT_FLAGS \
	--mp-auto=observe --mp-code="$CODE" --mp-name=NguoiXem \
	--mp-room-pass="$PASS" --mp-hold=400 > "$WORK/d.log" 2>&1 &
D=$!

wait $A; wait $B; wait $C; wait $D
kill $SRV 2>/dev/null

fail=0
chk() { # chk <label> <ok:0/1>
	if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

# Browser evidence: the room was listed with its flags, the wrong
# password produced the server's error line, the right one joined.
grep -q "MPLOG roomlist code=$CODE .* pass=1 obs=1" "$WORK/b.log"; chk "browser lists the room (pass=1 obs=1)" $?
grep -q "MPLOG lobby error=wrong room password" "$WORK/b.log"; chk "wrong password rejected with a clear error" $?
grep -q "MPLOG room code=$CODE slot=1" "$WORK/b.log"; chk "right password joins as slot 1" $?

# Host powers: kick happened, C saw the notice, host moved to B.
grep -q "MPLOG auto kicked slot=2" "$WORK/a.log"; chk "host kicked slot 2" $?
grep -q "MPLOG kicked" "$WORK/c.log"; chk "kicked client got the notice" $?
grep -q "MPLOG auto transferred host to slot=1" "$WORK/a.log"; chk "host transferred to slot 1" $?
grep -q "MPLOG room host=1" "$WORK/b.log"; chk "room broadcast names slot 1 as host" $?

# The match still ran clean to its scripted end.
grep -q "MPLOG result victory" "$WORK/a.log"; chk "A logs victory" $?
grep -q "MPLOG result defeat" "$WORK/b.log"; chk "B (new host) logs defeat" $?

# Observer evidence: attached, froze for the snapshot, the host
# served it, our raw command was rejected by the server, and our
# sim agreed with A's checksums afterwards.
grep -q "MPLOG observing code=$CODE" "$WORK/d.log"; chk "observer attached" $?
grep -q "MPLOG observer sync pending" "$WORK/d.log"; chk "observer froze for its snapshot" $?
grep -q "MPLOG obs snapshot served" "$WORK/b.log"; chk "host (B, after transfer) served the observer snapshot" $?
grep -q "MPLOG resync applied" "$WORK/d.log"; chk "observer applied the snapshot" $?
grep -q "MPLOG observer cmd sent" "$WORK/d.log"; chk "observer fired its probe command" $?
grep -q "MPLOG lobby error=observers cannot send commands" "$WORK/d.log"; chk "server rejected the observer command" $?
# Any tick both sides printed works: the observer's boot latency
# under load decides which due ticks it reaches (its snapshot
# lands when it lands), but the hashes at a shared tick must be
# identical — the rebuild was exact.
agree=1
for T in $(grep -o "MPLOG observer checksum tick=[0-9]*" "$WORK/d.log" | grep -o "[0-9]*$" | sort -u); do
	CA=$(grep -o "MPLOG checksum slot=0 tick=$T hash=[0-9]*" "$WORK/a.log" | grep -o "[0-9]*$" | head -1)
	CD=$(grep -o "MPLOG observer checksum tick=$T hash=[0-9]*" "$WORK/d.log" | grep -o "[0-9]*$" | head -1)
	if [ -n "$CA" ] && [ "$CA" = "$CD" ]; then
		agree=0
		echo "observer checksum agrees with A at tick $T"
		break
	fi
done
chk "observer checksum agrees with the host's sim" $agree
grep -q "MPLOG observer match over" "$WORK/d.log"; chk "observer saw the match end neutrally" $?

if grep -q "MPLOG desync" "$WORK/a.log" "$WORK/b.log" "$WORK/d.log"; then
	chk "no DESYNC notices" 1
else
	chk "no DESYNC notices" 0
fi

echo "logs: $WORK/{server,a,b,c,d}.log"
if [ $fail -eq 0 ]; then
	echo "CUSTOM SMOKE: ALL PASS"
else
	echo "CUSTOM SMOKE: FAILURES"
fi
exit $fail
