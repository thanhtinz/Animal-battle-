#!/usr/bin/env bash
# Empire Age 15e capture harness (functional shots, not a test):
#   empire_age_spectator_bar_v1.png   — a windowed OBSERVER in a
#     live custom match: the spectator bar at the bottom centre,
#     follow engaged on slot 1 ("Theo dõi: NguoiHai"), the slot
#     chip lit, the stream badge reading "Trực tiếp".
#   empire_age_spectator_delay_v1.png — the lobby create form
#     with the new "Trì hoãn người xem" selector set to 60 giây.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-spec-cap.XXXXXX)
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
# follow camera settles on slot 1's hero for the shot).
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=ChuMot \
	--mp-room-name="Phong Xem Truc Tiep" --mp-room-public --mp-room-obs \
	--mp-hero-test --mp-nokill --mp-hold=600 > "$WORK/h1.log" 2>&1 &
H1=$!
wait_line "$WORK/h1.log" "MPLOG room code=" 45
CODE=$(sed -n 's/.*MPLOG room code=\([A-Z0-9]*\).*/\1/p' "$WORK/h1.log" | head -1)
echo "room code: $CODE"
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code=$CODE --mp-name=NguoiHai \
	--mp-hero-test --mp-nokill --mp-hold=600 > "$WORK/h2.log" 2>&1 &
H2=$!

# Windowed observer: follow slot 1, shoot the bar once settled.
timeout 120 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
	--resolution 1152x864 -- \
	--mp-auto=observe --mp-code=$CODE --mp-name=NguoiXem \
	--mp-hero-test --mp-nokill \
	--mp-spec-follow=1 --mp-spec-shot-bar="$SHOTS/empire_age_spectator_bar_v1.png" \
	--mp-hold=600 > "$WORK/w1.log" 2>&1
grep -q "MPLOG spec bar shot saved" "$WORK/w1.log" \
	&& echo "bar shot saved" || echo "WARN: bar shot may be missing"

# Windowed lobby client: the create form with the delay set.
timeout 90 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
	--resolution 1152x864 -- \
	--mp-shot-create-delay="$SHOTS/empire_age_spectator_delay_v1.png" \
	--mp-name=NguoiChup > "$WORK/w2.log" 2>&1
grep -q "MPLOG create delay shot saved" "$WORK/w2.log" \
	&& echo "delay shot saved" || echo "WARN: delay shot may be missing"

kill $H1 $H2 $SRV 2>/dev/null
ls -la "$SHOTS/empire_age_spectator_bar_v1.png" "$SHOTS/empire_age_spectator_delay_v1.png" 2>/dev/null
echo "logs: $WORK"
