#!/usr/bin/env bash
# Empire Age 14c hero MP smoke test.
#
# Same hero-duel shape as mp_skill_smoke.sh (13j/13v), but both
# clients pass --mp-hero-chars=loi_chan,thach_son: Net applies
# the SAME forced assignment on every client, so slot 0 duels as
# Lôi Chấn and slot 1 as Thạch Sơn deterministically. The duel
# then exercises, over real lockstep: Lôi Độn's targeted dash
# (Chiêu 1 via the targeted command form), Song Lôi Liên Kích's
# chain, Thiên Lôi Phạt Trận's storm zone, Sơn Băng Đạp's leap,
# Nham Tường's stone wall (segments + timers in the checksum)
# and Địa Long Lật Đất's quake.
#
# Asserts from the MPLOG evidence lines:
#   - the forced chars are logged on both clients
#   - heroes spawn on both clients; both slots order + cast
#   - the skill commands apply on BOTH clients
#   - checksums agree at ticks 60 / 90 / 120 / 150 / 180 / 210
#   - no DESYNC notice anywhere
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-mp-heroes14c.XXXXXX)
echo "smoke workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR"

timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=SkillA --mp-nokill --mp-hero-test --mp-hero-chars=loi_chan,thach_son --mp-hold=230 > "$WORK/a.log" 2>&1 &
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
	--mp-auto=join --mp-code="$CODE" --mp-name=SkillB --mp-nokill --mp-hero-test --mp-hero-chars=loi_chan,thach_son --mp-hold=230 > "$WORK/b.log" 2>&1 &
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

grep -q "MPLOG heroes spawned" "$WORK/a.log"; chk "heroes spawned on A" $?
grep -q "MPLOG heroes spawned" "$WORK/b.log"; chk "heroes spawned on B" $?
grep -q "MPLOG in-match chars" "$WORK/a.log"; chk "char assignment logged on A" $?
grep -q "MPLOG hero chars forced \[\"loi_chan\", \"thach_son\"\]" "$WORK/a.log"; chk "forced 14c chars on A" $?
grep -q "MPLOG hero chars forced \[\"loi_chan\", \"thach_son\"\]" "$WORK/b.log"; chk "forced 14c chars on B" $?
grep -q "MPLOG hero order slot=0 char=loi_chan" "$WORK/a.log"; chk "slot 0 duels as Lôi Chấn" $?
grep -q "MPLOG hero order slot=1 char=thach_son" "$WORK/b.log"; chk "slot 1 duels as Thạch Sơn" $?
grep -q "MPLOG hero order slot=0" "$WORK/a.log"; chk "slot 0 hero ordered (A log)" $?
grep -q "MPLOG hero order slot=1" "$WORK/b.log"; chk "slot 1 hero ordered (B log)" $?
grep -q "MPLOG hero cast slot=0 sent=true" "$WORK/a.log"; chk "slot 0 cast sent" $?
grep -q "MPLOG hero cast slot=1 sent=true" "$WORK/b.log"; chk "slot 1 cast sent" $?
grep -q "MPLOG hero cast2 slot=0" "$WORK/a.log"; chk "slot 0 cast2 sent (13v)" $?
grep -q "MPLOG hero cast2 slot=1" "$WORK/b.log"; chk "slot 1 cast2 sent (13v)" $?
grep -q "MPLOG hero cast3 slot=0" "$WORK/a.log"; chk "slot 0 cast3 sent (13v)" $?
grep -q "MPLOG hero cast3 slot=1" "$WORK/b.log"; chk "slot 1 cast3 sent (13v)" $?
grep -q "kind=skill from=0" "$WORK/a.log"; chk "skill cmd from 0 applied on A" $?
grep -q "kind=skill from=0" "$WORK/b.log"; chk "skill cmd from 0 applied on B" $?
grep -q "kind=skill from=1" "$WORK/a.log"; chk "skill cmd from 1 applied on A" $?
grep -q "kind=skill from=1" "$WORK/b.log"; chk "skill cmd from 1 applied on B" $?

for T in 60 90 120 150 180 210; do
	CA=$(grep -o "MPLOG checksum slot=0 tick=$T hash=[0-9]*" "$WORK/a.log" | grep -o "[0-9]*$" | head -1)
	CB=$(grep -o "MPLOG checksum slot=1 tick=$T hash=[0-9]*" "$WORK/b.log" | grep -o "[0-9]*$" | head -1)
	[ -n "$CA" ] && [ "$CA" = "$CB" ]; chk "checksum tick $T agree (A=$CA B=$CB)" $?
done

if grep -q "MPLOG desync" "$WORK/a.log" "$WORK/b.log"; then
	chk "no DESYNC notices" 1
else
	chk "no DESYNC notices" 0
fi

echo "logs: $WORK/{server,a,b}.log"
if [ $fail -eq 0 ]; then
	echo "MP HEROES 14C SMOKE: ALL PASS"
else
	echo "MP HEROES 14C SMOKE: FAILURES"
fi
exit $fail
