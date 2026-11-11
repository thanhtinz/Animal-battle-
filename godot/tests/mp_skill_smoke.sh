#!/usr/bin/env bash
# Empire Age hero-skill MP smoke test (13j).
#
# Same relay + two-client shape as mp_smoke.sh, but the scripted
# match is a HERO DUEL: Main's mp_test_hero hook spawns both
# slots' heroes mid-map at tick 5; Net's --mp-hero-test driver
# orders each hero onto the other at tick 35 (a position order —
# resolved as an attack) and casts each hero's ACTIVE SKILL
# through the normal lockstep command pipeline at tick 55.
#
# Asserts from the MPLOG evidence lines:
#   - heroes spawn on both clients; both slots order + cast
#     (each with whatever character the server drew for them —
#     the draw is payload metadata, so the sims must still agree)
#   - the skill commands apply on BOTH clients
#   - checksums agree at ticks 60 / 90 / 120 / 150 / 180 / 210 — aura
#     math, Chiêu 1/2/3 effects, zones, shots, shields and the
#     per-skill cooldown state are bit-identical sims (13v)
#   - no DESYNC notice anywhere
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-mp-skill.XXXXXX)
echo "smoke workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR"

timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=SkillA --mp-nokill --mp-hero-test --mp-hold=230 > "$WORK/a.log" 2>&1 &
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
	--mp-auto=join --mp-code="$CODE" --mp-name=SkillB --mp-nokill --mp-hero-test --mp-hold=230 > "$WORK/b.log" 2>&1 &
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
	echo "MP SKILL SMOKE: ALL PASS"
else
	echo "MP SKILL SMOKE: FAILURES"
fi
exit $fail
