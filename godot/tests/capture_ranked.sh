#!/usr/bin/env bash
# Empire Age P4 stage-3 capture harness (NOT part of ranked_smoke.sh).
#
# Produces shots/empire_age_ranked_queue_v1.png: a logged-in client
# sitting in the ranked queue ("Đang tìm đối thủ…" + elapsed timer +
# cancel). A single queued client never pairs, so the queue view
# holds still for the capture. The server runs WITHOUT referee
# orchestration — no pairing means no referee is ever spawned.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-ranked-capture.XXXXXX)
SHOTS="$PWD/shots"
mkdir -p "$SHOTS"
echo "capture workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" -store "$WORK/accounts.json" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }

timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path . --resolution 1152x768 -- \
	--mp-shot-ranked="$SHOTS/empire_age_ranked_queue_v1.png" \
	--mp-account=RankShot:secret1 > "$WORK/shot.log" 2>&1
kill $SRV 2>/dev/null
grep -q "MPLOG ranked queue shot saved" "$WORK/shot.log" \
	&& echo "ranked queue shot saved" || echo "WARN: shot may be missing (see $WORK/shot.log)"
ls -la "$SHOTS/empire_age_ranked_queue_v1.png" 2>/dev/null
echo "logs: $WORK"
