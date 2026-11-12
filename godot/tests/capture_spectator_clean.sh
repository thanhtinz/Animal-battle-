#!/usr/bin/env bash
# Empire Age 15e-ter capture harness (functional shots, not a
# test): a windowed OBSERVER in a live custom match, FOLLOW
# engaged on slot 1, proving the spectator screen is CLEAN of
# the player's gameplay HUD:
#   empire_age_spectator_clean_v1.png — world + minimap +
#     spectator bar ONLY (no top chips, no bottom action
#     panel, no skill buttons, no selection chip; the top
#     glass shrunk to the chat / people / settings buttons).
#   empire_age_spectator_clean_panel_v1.png — same observer
#     with the dedicated spectator panel open.
# Drivers reused as-is: --mp-spec-shot-bar / --mp-spec-shot-panel
# (net.gd, 15e / 15e-bis).
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-specclean-cap.XXXXXX)
SHOTS="$PWD/shots"
mkdir -p "$SHOTS"
echo "capture workdir: $WORK"
wait_line() { # file pattern timeout_s
	local f=$1 pat=$2 t=$3 n=0
	while [ $n -lt $t ]; do grep -q "$pat" "$f" 2>/dev/null && return 0; sleep 1; n=$((n+1)); done
	return 1
}

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }

# Headless host + player hold a live custom match open (the
# hero-test stage puts both heroes fighting mid-map, so the
# follow camera settles on slot 1's hero for the shots).
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=ChuMot \
	--mp-room-name="Phong Xem Sach" --mp-room-public --mp-room-obs \
	--mp-hero-test --mp-nokill --mp-hold=600 > "$WORK/h1.log" 2>&1 &
H1=$!
wait_line "$WORK/h1.log" "MPLOG room code=" 45
CODE=$(sed -n 's/.*MPLOG room code=\([A-Z0-9]*\).*/\1/p' "$WORK/h1.log" | head -1)
echo "room code: $CODE"
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code=$CODE --mp-name=NguoiHai \
	--mp-hero-test --mp-nokill --mp-hold=600 > "$WORK/h2.log" 2>&1 &
H2=$!

# Windowed observer 1: follow slot 1, shoot the clean screen.
timeout 120 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
	--resolution 1152x864 -- \
	--mp-auto=observe --mp-code=$CODE --mp-name=NguoiXem \
	--mp-hero-test --mp-nokill \
	--mp-spec-follow=1 --mp-spec-shot-bar="$SHOTS/empire_age_spectator_clean_v1.png" \
	--mp-hold=600 > "$WORK/w1.log" 2>&1
grep -q "MPLOG spec bar shot saved" "$WORK/w1.log" \
	&& echo "clean shot saved" || echo "WARN: clean shot may be missing"

# Windowed observer 2: same follow, spectator panel open.
timeout 120 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
	--resolution 1152x864 -- \
	--mp-auto=observe --mp-code=$CODE --mp-name=NguoiXem \
	--mp-hero-test --mp-nokill \
	--mp-spec-follow=1 --mp-spec-shot-panel="$SHOTS/empire_age_spectator_clean_panel_v1.png" \
	--mp-hold=600 > "$WORK/w2.log" 2>&1
grep -q "MPLOG spec panel shot saved" "$WORK/w2.log" \
	&& echo "clean panel shot saved" || echo "WARN: clean panel shot may be missing"

kill $H1 $H2 $SRV 2>/dev/null
ls -la "$SHOTS/empire_age_spectator_clean_v1.png" "$SHOTS/empire_age_spectator_clean_panel_v1.png" 2>/dev/null
echo "logs: $WORK"
