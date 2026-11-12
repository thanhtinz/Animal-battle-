#!/usr/bin/env bash
# Empire Age 17b — ALLIANCE EXPANSION end-to-end smoke test.
#
# Real Go server + headless Godot clients, three phases:
#
#   Phase 1 (--mp-alliance2): Ally2Lead founds "Hội Sông Lam
#     17b" with tag SL17 and sends an alliance chat line while
#     ALONE; Ally2Mem finds it (browser row carries the tag),
#     joins, and must see that pre-join line in the server's
#     persisted chat history; the leader promotes Mem to
#     deputy; the DEPUTY sets the notice board and the leader
#     sees it live; chat lines carry the SL17 tag. Ally2Out
#     (17a outside driver) must stay clean throughout.
#   Phase 2 (--mp-auto): the same two accounts play a real
#     custom match (scripted slot-1 kill) — the host's result
#     report banks it server-side, firing the alliance hooks.
#   Phase 3 (--mp-alliance2=verify, a FRESH client process —
#     the relog): quest progress moved (matches 2, wins 1,
#     ranked 0), member detail counters are exact (Lead 1
#     game/1 win/30 pts, Mem 1 game/0 wins/10 pts), the chat
#     history survived the relog, and the notice persisted.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-alliance2-smoke.XXXXXX)
echo "alliance2 smoke workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" -store "$WORK/accounts.json" \
	> "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR"

fail=0
chk() { # chk <logfile> <pattern> <label>
	if grep -q "$2" "$WORK/$1.log" 2>/dev/null; then
		echo "ok: $3"
	else
		echo "FAIL: $3 (missing '$2' in $1.log)"; fail=1
	fi
}
chk_absent() { # chk_absent <logfile> <pattern> <label>
	if grep -q "$2" "$WORK/$1.log" 2>/dev/null; then
		echo "FAIL: $3 (unexpected '$2' in $1.log)"; fail=1
	else
		echo "ok: $3"
	fi
}

# ---------------- phase 1: alliance 17b flow ----------------
timeout 200 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-account=Ally2Out:secret1 --mp-nokill --mp-hold=100000 \
	--mp-alliance=outside > "$WORK/out.log" 2>&1 &
OUT=$!
timeout 200 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-account=Ally2Lead:secret1 --mp-nokill --mp-hold=100000 \
	--mp-alliance2=lead --mp-alliance-name="Hội Sông Lam 17b" \
	--mp-alliance-tag=SL17 > "$WORK/lead.log" 2>&1 &
LEAD=$!
for _ in $(seq 1 90); do
	grep -q "MPLOG ally2 created id=" "$WORK/lead.log" 2>/dev/null && break
	sleep 1
done
grep -q "MPLOG ally2 created id=" "$WORK/lead.log" || {
	echo "FAIL: leader never created the alliance (see $WORK/lead.log)"
	kill $SRV 2>/dev/null; exit 1; }
timeout 200 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-account=Ally2Mem:secret1 --mp-nokill --mp-hold=100000 \
	--mp-alliance2=mem --mp-alliance-name="Hội Sông Lam 17b" \
	--mp-alliance-tag=SL17 > "$WORK/mem.log" 2>&1 &
MEM=$!
wait $LEAD $MEM $OUT

chk lead "MPLOG ally2 created id=A" "leader created the alliance"
chk lead "MPLOG ally2 created id=A.* tag=SL17" "alliance carries tag SL17"
chk mem "MPLOG ally2 found id=A.* tag=SL17" "browser row carries the tag"
chk mem "MPLOG ally2 history ok=true" "pre-join chat line delivered via server history"
chk lead "MPLOG ally2 promoting user=Ally2Mem" "leader promoted member to deputy"
chk mem "MPLOG ally2 notice set" "deputy set the notice board"
chk lead "MPLOG ally2 notice seen text=Tối nay 20h tập trung đánh xếp hạng nhé" "leader sees the deputy's notice live"
chk lead "MPLOG chat ally_tag=SL17" "chat line carries the [SL17] tag (leader side)"
chk mem "MPLOG chat ally_tag=SL17" "chat line carries the [SL17] tag (member side)"
chk out "MPLOG alliance outsider clean mine=0 chats=0" "outsider stayed unaffiliated, no chat"
chk_absent mem "MPLOG ally2 TIMEOUT" "member driver finished"
chk_absent lead "MPLOG ally2 TIMEOUT" "leader driver finished"

# ---------------- phase 2: one real recorded match ----------------
timeout 240 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=Ally2Lead \
	--mp-account=Ally2Lead:secret1 > "$WORK/mlead.log" 2>&1 &
MLEAD=$!
CODE=""
for _ in $(seq 1 60); do
	CODE=$(grep -o "MPLOG room code=[A-Z0-9]*" "$WORK/mlead.log" 2>/dev/null | head -1 | cut -d= -f2)
	[ -n "$CODE" ] && break
	sleep 1
done
echo "match room code: ${CODE:-<none>}"
if [ -z "$CODE" ]; then
	echo "FAIL: match host never created a room (see $WORK/mlead.log)"
	kill $SRV 2>/dev/null; exit 1
fi
timeout 240 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code="$CODE" --mp-name=Ally2Mem \
	--mp-account=Ally2Mem:secret1 > "$WORK/mmem.log" 2>&1 &
MMEM=$!
wait $MLEAD $MMEM
chk mlead "MPLOG result victory" "match played: leader (host) won"
chk mmem "MPLOG result defeat" "match played: member lost"
sleep 2 # let the host's result report land + bank

# ---------------- phase 3: verify after relog ----------------
timeout 120 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-account=Ally2Mem:secret1 --mp-nokill --mp-hold=100000 \
	--mp-alliance2=verify --mp-alliance-name="Hội Sông Lam 17b" \
	> "$WORK/verify.log" 2>&1
chk verify "MPLOG ally2 verify quest key=matches prog=2" "quest: 2 collective matches after 1 banked match"
chk verify "MPLOG ally2 verify quest key=wins prog=1" "quest: 1 collective win"
chk verify "MPLOG ally2 verify quest key=ranked_wins prog=0" "quest: custom win does NOT count as ranked"
chk verify "MPLOG ally2 verify member user=Ally2Lead games=1 wins=1 week=30" "member detail: leader 1 game / 1 win / 30 pts"
chk verify "MPLOG ally2 verify member user=Ally2Mem games=1 wins=0 week=10" "member detail: member 1 game / 0 wins / 10 pts"
chk verify "MPLOG ally2 verify history has=true" "chat history visible after relog"
chk verify "MPLOG ally2 verify notice=Tối nay 20h tập trung đánh xếp hạng nhé" "notice persisted across relog"
chk verify "MPLOG ally2 verify done" "verify driver completed"

kill $SRV 2>/dev/null
for f in lead mem out mlead mmem verify; do
	if grep -q "SCRIPT ERROR" "$WORK/$f.log" 2>/dev/null; then
		echo "FAIL: script error in $f.log"; grep "SCRIPT ERROR" "$WORK/$f.log" | head -3; fail=1
	fi
done
if [ $fail -eq 0 ]; then
	echo "ALLIANCE2 SMOKE: ALL PASS"
else
	echo "ALLIANCE2 SMOKE: FAILURES (logs in $WORK)"
	exit 1
fi
