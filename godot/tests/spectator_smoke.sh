#!/usr/bin/env bash
# Empire Age 15e spectator smoke — two custom rooms on one relay:
#
#   Room 1 (the REAL 60s delay option): host A + player B +
#   observer OD attached in the LOBBY. The host starts; OD must
#   still be waiting at ~30 s (the server buffer holds the whole
#   match stream, match_start included) and its stream may only
#   go live after the delay (>= 55 s on the client's own clock).
#   The buffer itself is proven exhaustively at Go level
#   (spectator_test.go, synthetic clock, production 60 s value).
#
#   Room 2 (live): host A2 + player B2 + observer OF following
#   slot 1 + observer OA on auto-camera. The hero-test stage
#   (--mp-hero-test, --mp-nokill) spawns both heroes mid-map:
#   they charge each other and cast at ticks 55/100/150. OF's
#   follow target must be slot 1's HERO (the head of the follow
#   chain) fighting at the centre — not its Town Center — with
#   the camera settled on it; OA must log an auto-camera jump
#   to a hero cast. (An earlier draft staged the scripted TC
#   kill instead: the kill ELIMINATES slot 1, the match ends on
#   the spot, and the spectator correctly freezes with it —
#   a fine product behaviour but a useless stage.)
#
# No DESYNC may appear anywhere (presentation code never touches
# the sim). Everything ends on MPLOG asserts.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-spec-smoke.XXXXXX)
echo "smoke workdir: $WORK"
PASS=0; FAIL=0
ok()   { if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "PASS $2"; else FAIL=$((FAIL+1)); echo "FAIL $2"; fi }
has()  { grep -q "$1" "$2" 2>/dev/null; }
wait_line() { # file pattern timeout_s
	local f=$1 pat=$2 t=$3 n=0
	while [ $n -lt $t ]; do grep -q "$pat" "$f" 2>/dev/null && return 0; sleep 1; n=$((n+1)); done
	return 1
}
room_code() { sed -n 's/.*MPLOG room code=\([A-Z0-9]*\).*/\1/p' "$1" | head -1; }

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }

# ---------------------------------------------------------- room 1: delay 60s
timeout 240 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=ChuTre \
	--mp-room-name="Phong Tre" --mp-room-public --mp-room-obs \
	--mp-room-delay=60 --mp-hold=1500 > "$WORK/a.log" 2>&1 &
A=$!
wait_line "$WORK/a.log" "MPLOG room code=" 45; ok $? "delay room created"
CODE1=$(room_code "$WORK/a.log")
# The observer attaches FIRST, while the room is still in its
# lobby — only then does the second player join and ready up,
# so the observer's match_start is the broadcast one and the
# server's delay buffer provably holds it.
timeout 240 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=observe --mp-code=$CODE1 --mp-name=XemTre \
	--mp-hold=1500 > "$WORK/od.log" 2>&1 &
OD=$!
sleep 3
timeout 240 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code=$CODE1 --mp-name=NguoiChoi \
	--mp-hold=1500 > "$WORK/b.log" 2>&1 &
B=$!
wait_line "$WORK/od.log" "MPLOG observer waiting" 90
ok $? "delayed observer still waiting at ~30s (stream buffered)"
wait_line "$WORK/od.log" "MPLOG observer live" 150
ok $? "delayed observer stream goes live"
LIVE_MS=$(sed -n 's/.*MPLOG observer live ms=\([0-9]*\).*/\1/p' "$WORK/od.log" | head -1)
[ -n "$LIVE_MS" ] && [ "$LIVE_MS" -ge 55000 ]
ok $? "observer live only after >=55s on its own clock (ms=$LIVE_MS)"
wait_line "$WORK/od.log" "MPLOG observer checksum" 60
ok $? "delayed observer steps the sim (checksums flow)"
kill $A $B $OD 2>/dev/null; wait $A $B $OD 2>/dev/null

# ---------------------------------------------------------- room 2: follow + auto
timeout 200 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=ChuHai \
	--mp-room-name="Phong Xem" --mp-room-public --mp-room-obs \
	--mp-hero-test --mp-nokill --mp-hold=300 > "$WORK/a2.log" 2>&1 &
A2=$!
wait_line "$WORK/a2.log" "MPLOG room code=" 45; ok $? "live room created"
CODE2=$(room_code "$WORK/a2.log")
timeout 200 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code=$CODE2 --mp-name=NguoiHai \
	--mp-hero-test --mp-nokill --mp-hold=300 > "$WORK/b2.log" 2>&1 &
B2=$!
timeout 200 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=observe --mp-code=$CODE2 --mp-name=XemTheo \
	--mp-hero-test --mp-nokill \
	--mp-spec-follow=1 --mp-hold=300 > "$WORK/of.log" 2>&1 &
OF=$!
timeout 200 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=observe --mp-code=$CODE2 --mp-name=XemTuDong \
	--mp-hero-test --mp-nokill \
	--mp-spec-auto=1 --mp-hold=300 > "$WORK/oa.log" 2>&1 &
OA=$!
wait_line "$WORK/of.log" "MPLOG spec mode=follow slot=1" 90
ok $? "follow engages on slot 1"
wait_line "$WORK/of.log" "MPLOG heroes spawned" 90
ok $? "hero stage set (both heroes mid-map)"
wait_line "$WORK/of.log" "tick=210" 150
ok $? "follow observer reached tick 210"
wait_line "$WORK/oa.log" "MPLOG spec auto jump" 150
ok $? "auto-camera jumps when the action lands"
has "why=cast" "$WORK/oa.log" || has "why=battle" "$WORK/oa.log"
ok $? "auto jump is event-driven (cast/battle)"
python3 - "$WORK/of.log" "$WORK/oa.log" << 'PYEOF'
import re, sys
def states(path):
    out = []
    for line in open(path, errors="ignore"):
        m = re.search(r"MPLOG spec state mode=(\w+) slot=(-?\d+) cam=\(([-\d.]+), ([-\d.]+)\) target=(\(null\)|null|\(([-\d.]+), ([-\d.]+)\)) tick=(\d+)", line)
        if m:
            tgt = None
            if m.group(6):
                tgt = (float(m.group(6)), float(m.group(7)))
            out.append((int(m.group(8)), (float(m.group(3)), float(m.group(4))), tgt))
    return out
def dist(a, b):
    return ((a[0]-b[0])**2 + (a[1]-b[1])**2) ** 0.5
CENTRE = (1024.0, 1024.0)
of = [s for s in states(sys.argv[1]) if 60 <= s[0] <= 240 and s[2] is not None]
# The follow target is slot 1's hero fighting at the centre:
# most targets sit near the centre (NOT at a base TC), the
# camera settles on the target, and the target itself moves.
near = sum(1 for (_, _, t) in of if dist(t, CENTRE) < 280.0)
ok_near = len(of) >= 3 and near * 5 >= len(of) * 3
track = [dist(c, t) for (_, c, t) in of]
ok_track = len(track) >= 3 and sum(1 for d in track if d < 170.0) * 5 >= len(track) * 3
spread = 0.0
for i in range(len(of)):
    for j in range(i + 1, len(of)):
        spread = max(spread, dist(of[i][2], of[j][2]))
ok_move = spread > 25.0
oa = states(sys.argv[2])
ok_oa = len(oa) >= 1 and dist(oa[-1][1], CENTRE) < 450.0
print("follow samples=%d near_centre=%s tracking=%s spread=%.0f auto_cam_centre=%s"
      % (len(of), ok_near, ok_track, spread, ok_oa))
sys.exit(0 if (ok_near and ok_track and ok_move and ok_oa) else 1)
PYEOF
ok $? "follow tracks slot 1's hero at the centre; auto-cam settles on the fight"
kill $A2 $B2 $OF $OA $SRV 2>/dev/null; wait $A2 $B2 $OF $OA $SRV 2>/dev/null

# ---------------------------------------------------------- global invariants
BAD=0
for f in "$WORK"/*.log; do
	if grep -q "DESYNC" "$f"; then echo "DESYNC in $f"; BAD=1; fi
done
[ $BAD = 0 ]; ok $? "no DESYNC in any client (presentation-only code)"
echo "spectator smoke: PASS=$PASS FAIL=$FAIL (logs: $WORK)"
[ $FAIL = 0 ]
