#!/usr/bin/env bash
# Empire Age 15g transport smoke test.
#
# Two headless clients in a plain custom room (A host = slot 0,
# B = slot 1), both staged by Main's --mp-transport hook with a
# home + far Market, a Cart, a Wagon and five Militia per slot:
#   * A sets the cart's route through the order pipeline; the
#     cart runs the round trip and A's gold rises by exactly the
#     route payout, IDENTICALLY on both clients (same wallet,
#     same checksums — the payout flows through the sim).
#   * A loads 5 militia into the wagon and sends it to the far
#     Market; both clients see cargo=5, then cargo empty with
#     the five troops standing at the far Market.
#   * B sends its scout to ambush A's cart: the ambush alert
#     line (Main's owner-gated presentation) appears in A's log
#     ONLY — B's log must never contain it.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-transport-smoke.XXXXXX)
echo "smoke workdir: $WORK"
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

room_code_of() { # room_code_of <logfile>
	grep -o "MPLOG room code=[A-Z0-9]*" "$1" 2>/dev/null | head -1 | cut -d= -f2
}

fail=0
chk() { # chk <label> <ok:0/1>
	if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

timeout 700 "$GODOT" $GODOT_FLAGS \
	--mp-auto=create --mp-name=VanTaiA \
	--mp-transport --mp-nokill --mp-min-players=2 --mp-hold=720 > "$WORK/a.log" 2>&1 &
A=$!
CODE=""
for _ in $(seq 1 60); do
	CODE=$(room_code_of "$WORK/a.log")
	[ -n "$CODE" ] && break
	sleep 1
done
echo "room code: ${CODE:-<none>}"
if [ -z "$CODE" ]; then
	echo "FAIL: host never created a room (see $WORK/a.log)"
	kill $A $SRV 2>/dev/null
	exit 1
fi

timeout 700 "$GODOT" $GODOT_FLAGS \
	--mp-auto=join --mp-code="$CODE" --mp-name=VanTaiB \
	--mp-transport --mp-nokill --mp-hold=720 > "$WORK/b.log" 2>&1 &
B=$!
if ! wait_line "$WORK/b.log" "MPLOG room code=$CODE slot=1" 60; then
	echo "FAIL: B never landed as slot 1 (see $WORK/b.log)"
	kill $A $B $SRV 2>/dev/null
	exit 1
fi
echo "both clients in the room"

wait $A; wait $B
kill $SRV 2>/dev/null

grep -q "MPLOG transport staged" "$WORK/a.log"; chk "transport kit staged (host)" $?
grep -q "MPLOG transport staged" "$WORK/b.log"; chk "transport kit staged (guest)" $?
grep -q "MPLOG transport route ordered" "$WORK/a.log"; chk "A ordered the trade route" $?
grep -q "MPLOG transport route set owner=0" "$WORK/a.log"; chk "route set inside the sim (host view)" $?
grep -q "MPLOG transport route set owner=0" "$WORK/b.log"; chk "route set inside the sim (guest view)" $?
grep -q "MPLOG transport load ordered" "$WORK/a.log"; chk "A ordered the wagon loading" $?
grep -q "MPLOG transport cargo=5" "$WORK/a.log"; chk "wagon carries 5 (host view)" $?
grep -q "MPLOG transport cargo=5" "$WORK/b.log"; chk "wagon carries 5 (guest view)" $?
grep -q "MPLOG transport unload ordered" "$WORK/a.log"; chk "A ordered the cross-map unload" $?
grep -q "MPLOG transport unloaded=5" "$WORK/a.log"; chk "5 troops unloaded at the far Market (host view)" $?
grep -q "MPLOG transport unloaded=5" "$WORK/b.log"; chk "5 troops unloaded at the far Market (guest view)" $?
grep -q "MPLOG transport trip done owner=0" "$WORK/a.log"; chk "round trip completed (host view)" $?
grep -q "MPLOG transport trip done owner=0" "$WORK/b.log"; chk "round trip completed (guest view)" $?

GB_A=$(grep -o "MPLOG transport gold before=[0-9]*" "$WORK/a.log" | grep -o "[0-9]*$" | head -1)
GA_A=$(grep -o "MPLOG transport gold after=[0-9]*" "$WORK/a.log" | grep -o "[0-9]*$" | head -1)
GB_B=$(grep -o "MPLOG transport gold before=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | head -1)
GA_B=$(grep -o "MPLOG transport gold after=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | head -1)
if [ -n "$GB_A" ] && [ -n "$GA_A" ] && [ $((GA_A - GB_A)) -gt 0 ]; then
	chk "A's gold rose by the trade payout ($GB_A -> $GA_A)" 0
else
	chk "A's gold rose by the trade payout (before=$GB_A after=$GA_A)" 1
fi
if [ -n "$GB_A" ] && [ "$GB_A" = "$GB_B" ] && [ "$GA_A" = "$GA_B" ]; then
	chk "both clients agree on A's wallet exactly" 0
else
	chk "both clients agree on A's wallet exactly (A: $GB_A->$GA_A, B: $GB_B->$GA_B)" 1
fi
GO_A=$(grep -o "MPLOG transport route set owner=0 gold=[0-9]*" "$WORK/a.log" | grep -o "[0-9]*$" | head -1)
if [ -n "$GO_A" ] && [ -n "$GB_A" ] && [ -n "$GA_A" ] && [ $((GA_A - GB_A)) -ge "$GO_A" ]; then
	chk "gold gain covers the locked route payout ($GO_A)" 0
else
	chk "gold gain covers the locked route payout (route=$GO_A gain=$((GA_A - GB_A)))" 1
fi

grep -q "MPLOG transport ambush ordered" "$WORK/b.log"; chk "B ordered the ambush" $?
grep -q "MPLOG transport alert owner=0" "$WORK/a.log"; chk "ambush alert fired on the owner's client" $?
if grep -q "MPLOG transport alert" "$WORK/b.log"; then
	chk "no ambush alert on the attacker's client" 1
else
	chk "no ambush alert on the attacker's client" 0
fi

# Sim agreement: some tick where A and B printed the same hash.
agree=1
for T in $(grep -o "MPLOG checksum slot=1 tick=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | sort -u | head -40); do
	CA=$(grep -o "MPLOG checksum slot=0 tick=$T hash=[0-9]*" "$WORK/a.log" | grep -o "[0-9]*$" | head -1)
	CB=$(grep -o "MPLOG checksum slot=1 tick=$T hash=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | head -1)
	if [ -n "$CA" ] && [ "$CA" = "$CB" ]; then
		agree=0
		echo "A and B checksums agree at tick $T"
		break
	fi
done
chk "A and B sims agree (checksum)" $agree
if grep -q "MPLOG desync" "$WORK/a.log" "$WORK/b.log"; then
	chk "no DESYNC notices" 1
else
	chk "no DESYNC notices" 0
fi

echo "logs: $WORK/{server,a,b}.log"
if [ $fail -eq 0 ]; then
	echo "TRANSPORT SMOKE: ALL PASS"
else
	echo "TRANSPORT SMOKE: FAILURES"
fi
exit $fail
