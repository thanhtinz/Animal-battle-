#!/usr/bin/env bash
# Capture harness for 13t (mode panel rework):
#   1. empire_age_home_mode_panel_v3.png — BẮT ĐẦU panel with the
#      four entries (badges + Custom / Minigame buttons)
#   2. empire_age_custom_bot_v1.png     — Custom view (lobby menu)
#      showing the "Đánh với máy" entry
#   3. empire_age_matchmaking_normal_v1.png — the painted
#      matchmaking screen in NORMAL mode (guest queue, ~12 s state)
# Seeds a FileStore with the "HiepSi" account (same seed shape as
# capture_home_v6.sh), builds the relay from ../server, and
# drives the client three times against it.
set -u
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
GO="${GO:-$HOME/workspace/tools/goroot/bin/go}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$(cd "$ROOT/../server" && pwd)"
WORK="$(mktemp -d)"
mkdir -p "$ROOT/shots"
SRV_PID=""
cleanup() {
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

python3 - "$WORK/store.json" <<'EOF'
import hashlib, json, sys, time
def pw(password, salt_hex):
    return hashlib.pbkdf2_hmac("sha256", password.encode(),
                               bytes.fromhex(salt_hex), 120000).hex()
salt = "00112233445566778899aabbccddeeff"
now = int(time.time())
EPOCH = now - 91 * 86400  # season 2 (90-day seasons)
def acc(user, tier, div, stars, mmr, wins, losses, extra=None):
    a = {"user": user, "salt": salt, "hash": pw("secret1", salt),
         "created": now - 90000, "wins": wins, "losses": losses,
         "matches": wins + losses, "mmr": mmr,
         "rank": {"tier": tier, "division": div, "stars": stars,
                  "season": 2, "peak_tier": tier, "peak_division": div}}
    if extra:
        a.update(extra)
    return a
hiepsi = acc("HiepSi", 2, 1, 2, 1240, 7, 3, {
    "display_name": "HiepSi",
    "friends": ["CongTuoc1"],
    "letter_seq": 1,
    "letters": [{"id": 1, "title": "Chào mừng đến với Empire Age",
                 "body": "Chào HiepSi! Tài khoản của bạn đã sẵn sàng.",
                 "at": now - 86000, "read": False}],
})
store = {
  "accounts": {
    "HoangDe1": acc("HoangDe1", 6, 0, 27, 2560, 40, 5),
    "CongTuoc1": acc("CongTuoc1", 6, 0, 12, 1980, 30, 9),
    "HiepSi": hiepsi,
  },
  "meta": {"season_epoch": str(EPOCH)},
}
json.dump(store, open(sys.argv[1], "w"))
EOF

(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || { echo "BUILD FAIL"; exit 1; }
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1

echo "=== mode panel v3 ==="
timeout 280 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1280x720 \
  res://tests/capture_mode_panel_v3.tscn \
  > "$WORK/client1.log" 2>&1
grep -a "MODE PANEL V3 CAPTURE SAVED" "$WORK/client1.log" > /dev/null \
  || { echo "NO MODE PANEL SHOT"; tail -20 "$WORK/client1.log"; exit 1; }
echo "MODE PANEL CAPTURE OK: $ROOT/shots/empire_age_home_mode_panel_v3.png"

echo "=== custom view (bot entry) ==="
timeout 280 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1280x720 \
  res://tests/capture_custom_bot.tscn \
  > "$WORK/client2.log" 2>&1
grep -a "CUSTOM BOT CAPTURE SAVED" "$WORK/client2.log" > /dev/null \
  || { echo "NO CUSTOM BOT SHOT"; tail -20 "$WORK/client2.log"; exit 1; }
echo "CUSTOM BOT CAPTURE OK: $ROOT/shots/empire_age_custom_bot_v1.png"

echo "=== matchmaking screen, normal mode (guest) ==="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" \
  --path "$ROOT" --resolution 1152x768 \
  -- --mp-auto=off "--mp-shot-normal=$ROOT/shots/empire_age_matchmaking_normal_v1.png" \
  "--mp-name=NguoiChoi" "--mp-addr=127.0.0.1:8765" \
  > "$WORK/client3.log" 2>&1
grep -a "MPLOG normal queue shot saved" "$WORK/client3.log" > /dev/null \
  || { echo "NO NORMAL MM SHOT"; tail -20 "$WORK/client3.log"; exit 1; }
grep -a "MPLOG queue joined .* queue=normal" "$WORK/client3.log" > /dev/null \
  || { echo "CLIENT NEVER JOINED NORMAL QUEUE"; tail -20 "$WORK/client3.log"; exit 1; }
echo "NORMAL MATCHMAKING CAPTURE OK: $ROOT/shots/empire_age_matchmaking_normal_v1.png"
echo "CAPTURE 13T: ALL OK"
