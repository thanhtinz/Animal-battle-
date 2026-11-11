#!/usr/bin/env bash
# Empire Age 15a capture harness (functional shots, not a test):
#   empire_age_room_create_v1.png  — lobby menu with the new
#     create-room options (name / password / public / observers).
#   empire_age_room_browser_v1.png — the room browser populated
#     by two headless hosts holding public rooms open (one open,
#     one passworded, both observer-friendly).
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-rooms15a.XXXXXX)
SHOTS="$PWD/shots"
mkdir -p "$SHOTS"
echo "capture workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }

# Two headless hosts hold public rooms open in their lobbies.
timeout 120 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=ChuPhong \
	--mp-room-name="Phong Cua Chu" --mp-room-public --mp-room-obs \
	> "$WORK/h1.log" 2>&1 &
H1=$!
timeout 120 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=ChuKhoa \
	--mp-room-name="Phong Khoa Ne" --mp-room-pass=abc \
	--mp-room-public --mp-room-obs \
	> "$WORK/h2.log" 2>&1 &
H2=$!
for i in $(seq 1 45); do
	grep -q "MPLOG room code=" "$WORK/h1.log" 2>/dev/null \
		&& grep -q "MPLOG room code=" "$WORK/h2.log" 2>/dev/null && break
	sleep 1
done
echo "hosts up after ${i}s"

# Windowed client 1: the create form.
timeout 90 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
	--resolution 1152x864 -- \
	--mp-shot-create="$SHOTS/empire_age_room_create_v1.png" \
	--mp-name=NguoiChup > "$WORK/w1.log" 2>&1
grep -q "MPLOG create shot saved" "$WORK/w1.log" \
	&& echo "create shot saved" || echo "WARN: create shot may be missing"

# Windowed client 2: the populated browser.
timeout 90 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
	--resolution 1152x864 -- \
	--mp-shot-browser="$SHOTS/empire_age_room_browser_v1.png" \
	--mp-name=NguoiChup > "$WORK/w2.log" 2>&1
grep -q "MPLOG browser shot saved" "$WORK/w2.log" \
	&& echo "browser shot saved" || echo "WARN: browser shot may be missing"

kill $H1 $H2 $SRV 2>/dev/null
ls -la "$SHOTS/empire_age_room_create_v1.png" "$SHOTS/empire_age_room_browser_v1.png" 2>/dev/null
echo "logs: $WORK"
