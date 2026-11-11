#!/usr/bin/env bash
# Empire Age 13p follow-up 2 — painted matchmaking screen captures:
#  (1) the screen itself at the ~28 s wait state (clock seeded
#      by the Net auto driver): empire_age_matchmaking_v3_painted.png
#  (2) the cancel path: queue, cancel via the screen button's
#      handler, land back on the lobby menu — the client log
#      must show the server's queue_left answer.
# A single client never pairs, so the queue view holds.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="$ROOT/../tools/godot/Godot_v4.4.1-stable_linux.x86_64"
ADDR="127.0.0.1:8765"
WORK="$(mktemp -d /tmp/ea-mm-XXXXXX)"
SRV_PID=""
cleanup() {
	[ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
	rm -rf "$WORK"
}
trap cleanup EXIT

cd "$ROOT/server" || exit 1
"$ROOT/../tools/goroot/bin/go" build -o "$WORK/server" . || exit 1
"$WORK/server" -addr "$ADDR" -store "$WORK/store.json" \
	>"$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1.5

cd "$ROOT/godot" || exit 1
echo "=== matchmaking screen (~28s state) ==="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" \
	--path . --resolution 1152x768 \
	-- --mp-auto=off "--mp-shot-ranked=$ROOT/godot/shots/empire_age_matchmaking_v3_painted.png" \
	"--mp-account=MMCap:secret1" "--mp-addr=$ADDR" \
	>"$WORK/client-mm.log" 2>&1
grep -E "MPLOG (queue joined|ranked queue shot saved)" "$WORK/client-mm.log"
echo "=== cancel path ==="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" \
	--path . --resolution 1152x768 \
	-- --mp-auto=off "--mp-shot-mm-cancel=$ROOT/godot/shots/empire_age_matchmaking_cancel_v3.png" \
	"--mp-account=MMCan:secret1" "--mp-addr=$ADDR" \
	>"$WORK/client-cancel.log" 2>&1
grep -E "MPLOG (queue joined|queue left|mm cancel shot saved)" "$WORK/client-cancel.log"
if grep -q "MPLOG queue left" "$WORK/client-cancel.log"; then
	echo "CAPTURE MATCHMAKING: OK"
else
	echo "CAPTURE MATCHMAKING: FAIL (no queue_left) — logs kept off; rerun manually"
	tail -30 "$WORK/client-cancel.log"
	exit 1
fi
