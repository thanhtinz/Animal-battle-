#!/usr/bin/env bash
# Empire Age P4 stage 3 / 13z — RANKED end-to-end smoke test.
#
# Real Go server (with referee orchestration) + a real referee
# process (the same Godot project headless in --referee mode) +
# EIGHT logged-in headless Godot clients (--mp-ranked driver) —
# 13z: ranked matches are 8-player free-for-all.
#
#   8 accounts queue (all MMR 1000) -> the matcher anchors on
#   RankA (first in) and fills by closeness -> slots = join order
#   -> server spawns the referee -> countdown -> match starts ->
#   slot 0 issues the scripted move -> the REFEREE's sim (only)
#   fells slots 1..7 on ticks 120..210 via --referee-test-kills
#   -> clients diverge, the server resyncs them from referee
#   snapshots until the field has fallen -> the referee reports
#   placements [0,7,6,5,4,3,2,1] -> the server banks the FFA
#   table: RankA 1st (+2 sao, +1 daily = delta 3, MMR 1016),
#   RankH 2nd (+1 sao, 1011), RankG 3rd (+1, 1007), RankF 4th
#   (0, 1002), RankE 5th (0, 998), RankD 6th (-1 floored, 993),
#   RankC 7th (-1 floored, 989), RankB 8th (-1 floored, 984).
#
# A leaderboard probe verifies the board afterwards. Exact MMR /
# star figures are asserted HARD in the Go tests; here the smoke
# asserts the end-to-end wiring (group formed, referee reported
# placements, per-player rank_result pushes, the winner/loser
# board rows).
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-ranked-smoke.XXXXXX)
echo "ranked smoke workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" -store "$WORK/accounts.json" \
	-referee-godot "$GODOT" -referee-project "$PWD" \
	-referee-extra-args "--referee-test-kills=120:1,135:2,150:3,165:4,180:5,195:6,210:7" \
	> "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR (referee orchestration on)"

PIDS=""
launch() { # launch <logname> <user> — MUST stay a direct child of this
	# shell: capturing the pid via $(launch ...) would run the job inside
	# a subshell and `wait` could not reap it.
	timeout 700 "$GODOT" --headless --fixed-fps 30 --path . -- \
		--mp-ranked --mp-account=$2:secret1 --mp-nokill --mp-hold=600 \
		> "$WORK/$1.log" 2>&1 &
	PIDS="$PIDS $!"
}
wait_queued() { # wait_queued <logname>
	for _ in $(seq 1 90); do
		grep -q "MPLOG queue joined" "$WORK/$1.log" 2>/dev/null && return 0
		sleep 1
	done
	echo "FAIL: client $1 never entered the queue (see $WORK/$1.log)"
	kill $SRV 2>/dev/null; exit 1
}

for u in RankA RankB RankC RankD RankE RankF RankG RankH; do
	log=$(echo "$u" | tr 'A-Z' 'a-z')
	launch $log $u
	wait_queued $log
	echo "client $u queued"
done
for p in $PIDS; do wait $p; done

# Leaderboard probe: log in as RankA and dump the ranked board.
timeout 90 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-lbcheck --mp-account=RankA:secret1 > "$WORK/lb.log" 2>&1
kill $SRV 2>/dev/null

fail=0
chk() { # chk <label> <ok:0/1>
	if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

CODE=$(grep -o "MPLOG match found code=[A-Z0-9]*" "$WORK/ranka.log" | head -1 | cut -d= -f2)
echo "ranked room code: ${CODE:-<none>}"
[ -n "$CODE" ]; chk "match_found delivered (room code present)" $?

grep -q "ranked: group of 8" "$WORK/server.log"; chk "server formed a ranked group of 8" $?
grep -q "referee\[$CODE\]: spawned pid" "$WORK/server.log"; chk "server spawned the referee process" $?
grep -q "referee joined room $CODE" "$WORK/server.log"; chk "referee authenticated + joined" $?
SLOTS=$(for f in ranka rankb rankc rankd ranke rankf rankg rankh; do grep -o "MPLOG match found code=$CODE slot=[0-9]" "$WORK/$f.log" | grep -o "[0-9]$"; done | sort -n | tr '\n' ' ')
[ "$SLOTS" = "0 1 2 3 4 5 6 7 " ]; chk "slots 0..7 all seated ($SLOTS)" $?
grep -q "MPLOG match found code=$CODE slot=0" "$WORK/ranka.log"; chk "RankA is the anchor (slot 0)" $?

grep -q "MPLOG applied .* kind=order from=0" "$WORK/ranka.log"; chk "move order applied on RankA" $?
grep -q "referee\[$CODE\]: MPLOG applied .* kind=order from=0" "$WORK/server.log"; chk "move order applied in referee sim" $?
grep -q "referee\[$CODE\]: MPLOG eliminated slot=1" "$WORK/server.log"; chk "referee sim eliminated slot 1 (test kill)" $?
grep -q "MPLOG desync" "$WORK/ranka.log"; chk "RankA diverged from the referee (resync mechanism engaged)" $?
grep -q "MPLOG resync applied" "$WORK/ranka.log"; chk "RankA rebuilt from a referee snapshot" $?

grep -q "referee\[$CODE\]: MPLOG referee result winner_team=0 .* placements=\[0, 7, 6, 5, 4, 3, 2, 1\]" "$WORK/server.log"
chk "referee reported placements [0,7,6,5,4,3,2,1]" $?
grep -q "ranked $CODE: #1 RankA — MMR 1000 -> 1016, sao +3" "$WORK/server.log"; chk "server banked RankA: 1st, MMR 1016, +3 sao (2 + daily)" $?
grep -q "ranked $CODE: #8 RankB — MMR 1000 -> 984, sao +0" "$WORK/server.log"; chk "server banked RankB: 8th, MMR 984, floored stars" $?

grep -q "MPLOG result victory" "$WORK/ranka.log"; chk "RankA logs victory" $?
grep -q "MPLOG result defeat" "$WORK/rankb.log"; chk "RankB logs defeat" $?
grep -q "MPLOG rank_result won=true placement=1 delta=3 .* daily=true .* after=Tân Binh III · 3 sao" "$WORK/ranka.log"; chk "RankA rank_result: placement 1, +3 sao, daily" $?
grep -q "MPLOG rank_result won=false placement=8 delta=0" "$WORK/rankb.log"; chk "RankB rank_result: placement 8, floored" $?
grep -q "MPLOG lb row user=RankA mmr=1016 wins=1 losses=0 rank=Tân Binh III · 3 sao" "$WORK/lb.log"; chk "board: RankA 1016 · 1W · 3 sao" $?
grep -q "MPLOG lb row user=RankB mmr=984 wins=0 losses=1" "$WORK/lb.log"; chk "board: RankB 984 · 1L" $?
grep -q "MPLOG replay id received id=rp_" "$WORK/ranka.log"; chk "14a: replay id pushed to ranked-match clients (referee recording)" $?

echo "logs: $WORK/"
if [ $fail -eq 0 ]; then
	echo "RANKED SMOKE: ALL PASS"
else
	echo "RANKED SMOKE: FAILURES"
fi
exit $fail
