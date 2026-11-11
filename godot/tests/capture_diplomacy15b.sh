#!/usr/bin/env bash
# Empire Age 15b capture harness (functional shots, not a test):
#   empire_age_diplomacy_panel_v1.png  — the Diplomacy modal on
#     the guest client while the host's ALLY invite is pending:
#     stance pill, the incoming-proposal line, accept/decline
#     buttons and the (hidden, enemy-stance) tribute row state.
#   empire_age_diplomacy_vision_v1.png — after the guest accepts:
#     the (windowed) host's camera sits on the GUEST's Town
#     Center, which the host's fog now reveals through shared
#     vision (before the alliance that whole corner was
#     unexplored black).
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-dip15b.XXXXXX)
SHOTS="$PWD/shots"
mkdir -p "$SHOTS"
echo "capture workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }

room_code_of() { # room_code_of <logfile>
	grep -o "MPLOG room code=[A-Z0-9]*" "$1" 2>/dev/null | head -1 | cut -d= -f2
}

# --- shot 1: the panel with a pending invite -------------------
timeout 200 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=ChuPhong --mp-diplomacy \
	--mp-dip --mp-hold=300 > "$WORK/h1.log" 2>&1 &
H1=$!
CODE=""
for _ in $(seq 1 60); do
	CODE=$(room_code_of "$WORK/h1.log")
	[ -n "$CODE" ] && break
	sleep 1
done
echo "panel-shot room: ${CODE:-<none>}"
timeout 150 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
	--resolution 1152x864 -- \
	--mp-auto=join --mp-code="$CODE" --mp-name=NguoiChup \
	--mp-hold=100000 \
	--mp-dip-shot-panel="$SHOTS/empire_age_diplomacy_panel_v1.png" \
	> "$WORK/w1.log" 2>&1
grep -q "MPLOG dip panel shot saved" "$WORK/w1.log" \
	&& echo "panel shot saved" || echo "WARN: panel shot may be missing"
kill $H1 2>/dev/null
wait $H1 2>/dev/null

# --- shot 2: shared vision on the guest's base -----------------
# The WINDOWED client is the host: it proposes, the headless
# guest accepts, and the host's fog unions with the guest's —
# the camera sits on the GUEST's Town Center, revealed through
# shared vision. (A windowed GUEST falls too far behind the
# server's tick pace on this machine for its fog to union in
# time; the host only needs the first ~60 ticks. Same pattern
# as capture_mp2.sh's in-match chat shot.) THREE players: with
# only two, the acceptance would instantly end the match in an
# allied victory and cover the scene with the result panel —
# the third, unallied player keeps the match running.
timeout 150 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
	--resolution 1152x864 -- \
	--mp-auto=create --mp-name=ChuPhong --mp-diplomacy \
	--mp-dip --mp-hold=100000 --mp-min-players=3 \
	--mp-dip-shot-vision-host="$SHOTS/empire_age_diplomacy_vision_v1.png" \
	> "$WORK/w2.log" 2>&1 &
W2=$!
CODE=""
for _ in $(seq 1 60); do
	CODE=$(room_code_of "$WORK/w2.log")
	[ -n "$CODE" ] && break
	sleep 1
done
echo "vision-shot room: ${CODE:-<none>}"
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code="$CODE" --mp-name=NguoiChup \
	--mp-dip --mp-hold=100000 > "$WORK/h2.log" 2>&1 &
H2=$!
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code="$CODE" --mp-name=NguoiThuBa \
	--mp-dip --mp-hold=100000 > "$WORK/h3.log" 2>&1 &
H3=$!
wait $W2 2>/dev/null
grep -q "MPLOG dip vision host shot saved" "$WORK/w2.log" \
	&& echo "vision shot saved" || echo "WARN: vision shot may be missing"
kill $H2 $H3 2>/dev/null
kill $SRV 2>/dev/null
ls -la "$SHOTS/empire_age_diplomacy_panel_v1.png" "$SHOTS/empire_age_diplomacy_vision_v1.png" 2>/dev/null
echo "logs: $WORK"
