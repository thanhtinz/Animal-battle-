#!/usr/bin/env bash
# Empire Age 15b diplomacy smoke test.
#
# Scenario 1 — three headless clients in a diplomacy FFA custom
# room (A host, B, C passive):
#   A proposes ALLY to B (tick 40), B accepts on sight of the
#   invite -> B's fog must UNION with A's (B sees A's base,
#   state 0 -> 2). A gifts B exactly 100 wood (tick 120; B parks
#   its villagers first so the delta is exact). A declares a
#   break (tick 260): inside the 30 s declaration window A's
#   attack order on B's scout must NOT land (B's scout HP is
#   identical at ticks 399 and 549); after the window matures
#   the same order (tick 620) must draw blood.
# Scenario 2 — two clients, same flags: the accept leaves the
# last two players mutually allied, so the match must end at
# once as a SHARED victory on both clients.
#
# C's presence in scenario 1 matters: with a third enemy alive,
# the A-B alliance must NOT end the match early.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-dip-smoke.XXXXXX)
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

# ================= scenario 1: 3-client diplomacy FFA ==========
timeout 400 "$GODOT" $GODOT_FLAGS \
	--mp-auto=create --mp-name=NgoaiGiaoA --mp-diplomacy \
	--mp-dip --mp-nokill --mp-min-players=3 --mp-hold=820 > "$WORK/a.log" 2>&1 &
A=$!
CODE=""
for _ in $(seq 1 60); do
	CODE=$(room_code_of "$WORK/a.log")
	[ -n "$CODE" ] && break
	sleep 1
done
echo "scenario 1 room code: ${CODE:-<none>}"
if [ -z "$CODE" ]; then
	echo "FAIL: host never created a room (see $WORK/a.log)"
	kill $A $SRV 2>/dev/null
	exit 1
fi

timeout 400 "$GODOT" $GODOT_FLAGS \
	--mp-auto=join --mp-code="$CODE" --mp-name=NgoaiGiaoB \
	--mp-dip --mp-nokill --mp-hold=820 > "$WORK/b.log" 2>&1 &
B=$!
if ! wait_line "$WORK/b.log" "MPLOG room code=$CODE slot=1" 60; then
	echo "FAIL: B never landed as slot 1 (see $WORK/b.log)"
	kill $A $B $SRV 2>/dev/null
	exit 1
fi
timeout 400 "$GODOT" $GODOT_FLAGS \
	--mp-auto=join --mp-code="$CODE" --mp-name=NgoaiGiaoC \
	--mp-dip --mp-nokill --mp-hold=820 > "$WORK/c.log" 2>&1 &
C=$!
if ! wait_line "$WORK/c.log" "MPLOG room code=$CODE slot=2" 60; then
	echo "FAIL: C never landed as slot 2 (see $WORK/c.log)"
	kill $A $B $C $SRV 2>/dev/null
	exit 1
fi
echo "scenario 1: all three clients in the room"

wait $A; wait $B; wait $C

grep -q "MPLOG dip proposed from=0 to=1" "$WORK/a.log"; chk "A proposed the alliance" $?
grep -q "MPLOG dip accepted by=1" "$WORK/b.log"; chk "B accepted the alliance" $?
grep -q "MPLOG dip vision before b_sees_a=0" "$WORK/b.log"; chk "B could not see A's base before the alliance" $?
grep -q "MPLOG dip vision after b_sees_a=2" "$WORK/b.log"; chk "shared vision: B sees A's base after accepting" $?
grep -q "MPLOG dip gift sent" "$WORK/a.log"; chk "A sent the tribute" $?
WB=$(grep -o "MPLOG dip b wood before=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | head -1)
WA=$(grep -o "MPLOG dip b wood after=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | head -1)
if [ -n "$WB" ] && [ -n "$WA" ] && [ $((WA - WB)) -eq 100 ]; then
	chk "tribute landed exactly (+100 wood: $WB -> $WA)" 0
else
	chk "tribute landed exactly (+100 wood: before=$WB after=$WA)" 1
fi
grep -q "MPLOG dip break declared" "$WORK/a.log"; chk "A declared the break" $?
grep -q "MPLOG dip attack order in window" "$WORK/a.log"; chk "A attacked inside the window" $?
H1=$(grep -o "MPLOG dip b scout hp at399=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | head -1)
H2=$(grep -o "MPLOG dip b scout hp at549=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | head -1)
if [ -n "$H1" ] && [ "$H1" = "$H2" ]; then
	chk "no damage inside the declaration window (scout hp $H1 at 399 and 549)" 0
else
	chk "no damage inside the declaration window (hp at399=$H1 at549=$H2)" 1
fi
grep -q "MPLOG dip attack order after window" "$WORK/a.log"; chk "A attacked again after the window" $?
grep -q "MPLOG dip b scout hp dropped=1" "$WORK/b.log"; chk "attacks land after the declaration matures" $?
if grep -q "MPLOG result" "$WORK/c.log"; then
	chk "the match did NOT end early for the third player" 1
else
	chk "the match did NOT end early for the third player" 0
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
if grep -q "MPLOG desync" "$WORK/a.log" "$WORK/b.log" "$WORK/c.log"; then
	chk "no DESYNC notices (scenario 1)" 1
else
	chk "no DESYNC notices (scenario 1)" 0
fi

# ================= scenario 2: 2-client allied victory =========
timeout 300 "$GODOT" $GODOT_FLAGS \
	--mp-auto=create --mp-name=LienMinhA --mp-diplomacy \
	--mp-dip --mp-nokill --mp-hold=200 > "$WORK/a2.log" 2>&1 &
A2=$!
CODE2=""
for _ in $(seq 1 60); do
	CODE2=$(room_code_of "$WORK/a2.log")
	[ -n "$CODE2" ] && break
	sleep 1
done
echo "scenario 2 room code: ${CODE2:-<none>}"
if [ -z "$CODE2" ]; then
	echo "FAIL: scenario 2 host never created a room (see $WORK/a2.log)"
	kill $A2 $SRV 2>/dev/null
	exit 1
fi
timeout 300 "$GODOT" $GODOT_FLAGS \
	--mp-auto=join --mp-code="$CODE2" --mp-name=LienMinhB \
	--mp-dip --mp-nokill --mp-hold=200 > "$WORK/b2.log" 2>&1 &
B2=$!
wait $A2; wait $B2
kill $SRV 2>/dev/null

grep -q "MPLOG dip allied victory" "$WORK/a2.log"; chk "host records the shared allied victory" $?
grep -q "MPLOG dip allied victory" "$WORK/b2.log"; chk "guest records the shared allied victory" $?
grep -q "MPLOG result victory" "$WORK/a2.log"; chk "host wins the shared victory" $?
grep -q "MPLOG result victory" "$WORK/b2.log"; chk "guest wins the shared victory" $?
if grep -q "MPLOG desync" "$WORK/a2.log" "$WORK/b2.log"; then
	chk "no DESYNC notices (scenario 2)" 1
else
	chk "no DESYNC notices (scenario 2)" 0
fi

echo "logs: $WORK/{server,a,b,c,a2,b2}.log"
if [ $fail -eq 0 ]; then
	echo "DIPLOMACY SMOKE: ALL PASS"
else
	echo "DIPLOMACY SMOKE: FAILURES"
fi
exit $fail
