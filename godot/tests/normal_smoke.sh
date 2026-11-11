#!/usr/bin/env bash
# Empire Age 13t/13z — NORMAL (unranked) queue end-to-end smoke.
#
# Real Go server (no referee — normal rooms have none) + EIGHT
# headless Godot clients on the --mp-normal driver (13z: queue
# matches are 8-player free-for-all). NormA (account) queues
# first and becomes slot 0 / host; NormB (account) and six
# GUESTS fill the group (guests are allowed here, unlike ranked):
#
#   8 queue (queue=normal, queue_status pushes count up) ->
#   server forms the FIFO group of 8 -> room ranked=false ->
#   countdown -> match starts -> slot 0 issues the scripted move
#   -> the sim hook fells slots 1..7 on ticks 120..210 (same on
#   every client — checksums must agree throughout) -> slot 0
#   wins -> the HOST reports the full placement list -> server
#   banks W/L only (RecordMatch: 1st = win, 2nd-8th = loss).
#
# A leaderboard probe then proves the banking touched W/L ONLY:
# NormA wins=1 / NormB losses=1 with MMR still 1000 and the
# ladder still at Tân Binh III · 0 sao, and no client ever saw a
# rank_result.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-normal-smoke.XXXXXX)
echo "normal smoke workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" -store "$WORK/accounts.json" \
	> "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR"

PIDS=""
launch() { # launch <logname> <godot args...> — MUST stay a direct child
	# of this shell: capturing the pid via $(launch ...) would run the
	# background job inside a subshell and `wait` could not reap it.
	local log=$1; shift
	timeout 600 "$GODOT" --headless --fixed-fps 30 --path . -- "$@" \
		> "$WORK/$log.log" 2>&1 &
	PIDS="$PIDS $!"
}
wait_queued() { # wait_queued <logname>
	for _ in $(seq 1 90); do
		grep -q "MPLOG queue joined" "$WORK/$1.log" 2>/dev/null && return 0
		sleep 1
	done
	echo "FAIL: client $1 never entered the normal queue (see $WORK/$1.log)"
	kill $SRV 2>/dev/null; exit 1
}

launch a --mp-normal --mp-account=NormA:secret1 --mp-name=NormA --mp-hold=400
wait_queued a
echo "client A queued (account, becomes host)"
launch b --mp-normal --mp-account=NormB:secret1 --mp-name=NormB --mp-hold=400
wait_queued b
i=1
for gname in KhachC KhachD KhachE KhachF KhachG KhachH; do
	i=$((i+1))
	launch g$i --mp-normal --mp-name=$gname --mp-hold=400
done
for p in $PIDS; do wait $p; done

# Leaderboard probe: log in as NormA and dump the ranked board.
timeout 90 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-lbcheck --mp-account=NormA:secret1 > "$WORK/lb.log" 2>&1
kill $SRV 2>/dev/null

fail=0
chk() { # chk <label> <ok:0/1>
	if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

CODE=$(grep -o "MPLOG match found code=[A-Z0-9]*" "$WORK/a.log" | head -1 | cut -d= -f2)
echo "normal room code: ${CODE:-<none>}"
[ -n "$CODE" ]; chk "match_found delivered (room code present)" $?

grep -q "normal: group of 8" "$WORK/server.log"; chk "server formed a group of 8" $?
for f in a b g2 g3 g4 g5 g6 g7; do
	grep -q "MPLOG queue joined .* queue=normal" "$WORK/$f.log" || { chk "client $f joined the NORMAL queue" 1; continue; }
	grep -q "MPLOG match found code=$CODE " "$WORK/$f.log" || { chk "client $f in room $CODE" 1; continue; }
	chk "client $f queued + matched into $CODE" 0
done
grep -q "MPLOG queue status found=" "$WORK/a.log"; chk "queue_status progress pushed to A" $?
grep -q "MPLOG match found code=$CODE slot=0 .* ranked=false" "$WORK/a.log"; chk "A is slot 0, room unranked" $?
SLOTS=$(for f in a b g2 g3 g4 g5 g6 g7; do grep -o "MPLOG match found code=$CODE slot=[0-9]" "$WORK/$f.log" | grep -o "[0-9]$"; done | sort -n | tr '\n' ' ')
[ "$SLOTS" = "0 1 2 3 4 5 6 7 " ]; chk "slots 0..7 all seated ($SLOTS)" $?

grep -q "MPLOG applied .* kind=order from=0" "$WORK/a.log"; chk "move order applied on A" $?
grep -q "MPLOG applied .* kind=order from=0" "$WORK/b.log"; chk "move order applied on B" $?

HASHES=$(for f in a b g2 g3 g4 g5 g6 g7; do grep -o "MPLOG checksum slot=[0-9] tick=90 hash=[0-9]*" "$WORK/$f.log" | grep -o "[0-9]*$" | head -1; done | sort -u | wc -l)
[ "$HASHES" -eq 1 ]; chk "tick 90 checksums identical across all 8 clients" $?

grep -q "MPLOG eliminated slot=7" "$WORK/a.log"; chk "slot 7 eliminated in A's sim" $?
grep -q "MPLOG result victory" "$WORK/a.log"; chk "A (slot 0, last standing) logs victory" $?
grep -q "MPLOG result defeat" "$WORK/b.log"; chk "B logs defeat at its elimination" $?
grep -q "DESYNC" "$WORK"/*.log && chk "no DESYNC anywhere" 1 || chk "no DESYNC anywhere" 0

grep -q "rank_result" "$WORK/a.log" "$WORK/b.log" && chk "no rank_result in a normal match" 1 || chk "no rank_result in a normal match" 0
grep -q "MPLOG lb row user=NormA mmr=1000 wins=1 losses=0" "$WORK/lb.log"; chk "probe: NormA banked the win (placement 1), MMR still 1000" $?
grep -q "MPLOG lb row user=NormB mmr=1000 wins=0 losses=1" "$WORK/lb.log"; chk "probe: NormB banked a loss (placement 2-8)" $?
grep -q "MPLOG lb row user=NormA .* rank=Tân Binh III · 0 sao" "$WORK/lb.log"; chk "probe: NormA ladder untouched (Tân Binh III · 0 sao)" $?
grep -q "MPLOG replay id received id=rp_" "$WORK/a.log"; chk "14a: replay id pushed to normal-match clients" $?

echo "logs: $WORK/"
if [ $fail -eq 0 ]; then
	echo "NORMAL SMOKE: ALL PASS"
else
	echo "NORMAL SMOKE: FAILURES"
fi
exit $fail
