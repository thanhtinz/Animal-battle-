#!/usr/bin/env bash
# Replay screenshot harness (13h): plays one short scripted match
# (windowed auto clients), then opens the recording in a windowed
# playback client and photographs it mid-playback at 1280x720 —
# control bar, timeline and player chips visible.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-replay-capture.XXXXXX)
SHOT="$PWD/shots/empire_age_replay_v1.png"
mkdir -p "$PWD/shots"
echo "capture workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" -store "$WORK/accounts.json" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }

# The recording match runs HEADLESS (windowed clients under Xvfb
# step ~5x slower and would not finish in budget); only the
# playback client is windowed, for the photograph.
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=RepA --mp-account=RepA:secret1 > "$WORK/a.log" 2>&1 &
A=$!
CODE=""
for _ in $(seq 1 60); do
	CODE=$(grep -o "MPLOG room code=[A-Z0-9]*" "$WORK/a.log" 2>/dev/null | head -1 | cut -d= -f2)
	[ -n "$CODE" ] && break
	sleep 1
done
if [ -z "$CODE" ]; then
	echo "FAIL: no room (see $WORK/a.log)"; kill $A $SRV 2>/dev/null; exit 1
fi
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code="$CODE" --mp-name=RepB --mp-account=RepB:secret1 > "$WORK/b.log" 2>&1 &
B=$!
wait $A
wait $B

RID=$(grep -o "replay rp_[a-z0-9]* stored" "$WORK/server.log" | grep -o "rp_[a-z0-9]*" | head -1)
if [ -z "$RID" ]; then
	echo "FAIL: no replay sealed (see $WORK/server.log)"; kill $SRV 2>/dev/null; exit 1
fi
echo "replay id: $RID"

timeout 150 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path . --resolution 1280x720 -- \
	--mp-replay-fetch="$RID" --mp-replay-shot="$SHOT" \
	--mp-account=RepA:secret1 > "$WORK/c.log" 2>&1
kill $SRV 2>/dev/null
grep -q "MPLOG replay shot saved" "$WORK/c.log" \
	|| { echo "FAIL: no shot"; tail -20 "$WORK/c.log"; exit 1; }
python3 -c "
from PIL import Image
im = Image.open('$SHOT')
print('shot size:', im.size)
assert im.size == (1280, 720), 'unexpected size'
"
echo "REPLAY CAPTURE OK: $SHOT"
