#!/usr/bin/env bash
# Empire Age P4 multiplayer smoke test.
#
# Builds the Go relay, starts it on localhost, then runs TWO
# headless Godot clients (Net's --mp-auto driver): A creates a room,
# B joins by code, both ready up, the host starts, and the scripted
# match plays out — slot 0 issues a move order (~tick 30), both
# clients report state checksums every 30 ticks, and a scripted TC
# kill at tick 120 eliminates slot 1.
#
# Asserts from the MPLOG evidence lines:
#   - identical world-generation hash on both clients
#   - the move order applied on BOTH clients at the SAME tick
#   - checksums agree at ticks 30 / 60 / 90
#   - slot 1 eliminated on both; A logs victory, B logs defeat
#   - no DESYNC notice anywhere
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-mp-smoke.XXXXXX)
echo "smoke workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR"

timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=SmokeA > "$WORK/a.log" 2>&1 &
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

timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code="$CODE" --mp-name=SmokeB > "$WORK/b.log" 2>&1 &
B=$!
wait $A
wait $B
kill $SRV 2>/dev/null

fail=0
chk() { # chk <label> <ok:0/1>
	if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

HA=$(grep -o "MPLOG worldhash slot=0 hash=[0-9]*" "$WORK/a.log" | grep -o "[0-9]*$" | head -1)
HB=$(grep -o "MPLOG worldhash slot=1 hash=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | head -1)
[ -n "$HA" ] && [ "$HA" = "$HB" ]; chk "same world hash (A=$HA B=$HB)" $?

grep -q "MPLOG applied .* kind=order from=0" "$WORK/a.log"; chk "order applied on A" $?
grep -q "MPLOG applied .* kind=order from=0" "$WORK/b.log"; chk "order applied on B" $?
TA=$(grep -o "MPLOG applied tick=[0-9]* kind=order from=0" "$WORK/a.log" | head -1)
TB=$(grep -o "MPLOG applied tick=[0-9]* kind=order from=0" "$WORK/b.log" | head -1)
[ -n "$TA" ] && [ "$TA" = "$TB" ]; chk "order applied at same tick ($TA)" $?

for T in 30 60 90; do
	CA=$(grep -o "MPLOG checksum slot=0 tick=$T hash=[0-9]*" "$WORK/a.log" | grep -o "[0-9]*$" | head -1)
	CB=$(grep -o "MPLOG checksum slot=1 tick=$T hash=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | head -1)
	[ -n "$CA" ] && [ "$CA" = "$CB" ]; chk "checksum tick $T agree (A=$CA B=$CB)" $?
done

grep -q "MPLOG eliminated slot=1" "$WORK/a.log"; chk "slot 1 eliminated seen on A" $?
grep -q "MPLOG eliminated slot=1" "$WORK/b.log"; chk "slot 1 eliminated seen on B" $?
grep -q "MPLOG result victory" "$WORK/a.log"; chk "A logs victory" $?
grep -q "MPLOG result defeat" "$WORK/b.log"; chk "B logs defeat" $?

if grep -q "MPLOG desync" "$WORK/a.log" "$WORK/b.log"; then
	chk "no DESYNC notices" 1
else
	chk "no DESYNC notices" 0
fi

# ---------------- Phase 2: forced divergence + resync ----------------
# Same scripted match, but client B runs with --mp-corrupt: at tick
# 60 it nudges one of its own villagers +1px locally. Expected flow:
# checksums diverge at tick 60 -> server broadcasts DESYNC -> the
# host's hash wins (1v1 tie) -> host serves a full-state snapshot at
# a tick boundary -> B rebuilds from it -> checksums agree again ->
# the scripted elimination still completes with no further desync.
echo "--- phase 2: resync ---"
"$WORK/relay" -addr "$ADDR" > "$WORK/server2.log" 2>&1 &
SRV2=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: phase2 server not up"; kill $SRV2 2>/dev/null; exit 1; }

timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=SmokeA2 --mp-corrupt > "$WORK/a2.log" 2>&1 &
A2=$!
CODE2=""
for _ in $(seq 1 60); do
	CODE2=$(grep -o "MPLOG room code=[A-Z0-9]*" "$WORK/a2.log" 2>/dev/null | head -1 | cut -d= -f2)
	[ -n "$CODE2" ] && break
	sleep 1
done
echo "phase2 room code: ${CODE2:-<none>}"
if [ -z "$CODE2" ]; then
	echo "FAIL: phase2 host never created a room (see $WORK/a2.log)"
	kill $A2 $SRV2 2>/dev/null
	exit 1
fi
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code="$CODE2" --mp-name=SmokeB2 --mp-corrupt > "$WORK/b2.log" 2>&1 &
B2=$!
wait $A2
wait $B2
kill $SRV2 2>/dev/null

grep -q "MPLOG corrupted slot=1" "$WORK/b2.log"; chk "B corrupted its sim" $?
grep -q "MPLOG desync tick=60" "$WORK/b2.log"; chk "DESYNC raised at tick 60 (B)" $?
grep -q "MPLOG desync tick=60" "$WORK/a2.log"; chk "DESYNC raised at tick 60 (A)" $?
grep -q "MPLOG snapshot sent tick=" "$WORK/a2.log"; chk "host served a snapshot" $?
grep -q "MPLOG resync applied tick=" "$WORK/b2.log"; chk "B rebuilt from snapshot" $?

TS=$(grep -o "MPLOG resync applied tick=[0-9]*" "$WORK/b2.log" | grep -o "[0-9]*$" | head -1)
agree=1
if [ -n "$TS" ]; then
	for T in 90 120 150; do
		[ "$T" -le "$TS" ] && continue
		CA=$(grep -o "MPLOG checksum slot=0 tick=$T hash=[0-9]*" "$WORK/a2.log" | grep -o "[0-9]*$" | head -1)
		CB=$(grep -o "MPLOG checksum slot=1 tick=$T hash=[0-9]*" "$WORK/b2.log" | grep -o "[0-9]*$" | head -1)
		if [ -n "$CA" ] && [ "$CA" = "$CB" ]; then
			agree=0
			echo "post-resync checksums agree at tick $T"
			break
		fi
	done
fi
chk "post-resync checksums agree (snapshot tick ${TS:-?})" $agree

ND=$(grep -c "MPLOG desync" "$WORK/b2.log")
[ "$ND" -eq 1 ]; chk "exactly one DESYNC on B (got $ND)" $?

grep -q "MPLOG eliminated slot=1" "$WORK/a2.log"; chk "phase2 slot 1 eliminated seen on A" $?
grep -q "MPLOG eliminated slot=1" "$WORK/b2.log"; chk "phase2 slot 1 eliminated seen on B" $?
grep -q "MPLOG result victory" "$WORK/a2.log"; chk "phase2 A logs victory" $?
grep -q "MPLOG result defeat" "$WORK/b2.log"; chk "phase2 B logs defeat" $?

echo "logs: $WORK/{server,a,b,server2,a2,b2}.log"
if [ $fail -eq 0 ]; then
	echo "MP SMOKE: ALL PASS"
else
	echo "MP SMOKE: FAILURES"
fi
exit $fail
