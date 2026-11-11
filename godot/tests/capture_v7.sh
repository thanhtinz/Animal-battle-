#!/usr/bin/env bash
# Capture harness for the 13i follow-up 3 changes (transparent
# bottom row + mode badges) and the Liên minh leaderboard tab:
#   1. empire_age_home_lobby_v7.png      (Home, seeded HiepSi)
#   2. empire_age_home_mode_panel_v2.png (mode panel, badges)
#   3. empire_age_leaderboard_v5.png     (Liên minh empty state)
# Seeds a FileStore (HiepSi at Kỵ Sĩ II · 2 sao, season 2, plus
# a small ladder above him), builds the relay from ../server,
# and drives the client three times against it.
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
         "matches": wins + losses, "mmr": mmr, "last_played": now - 3600,
         "rank": {"tier": tier, "division": div, "stars": stars,
                  "streak": 0, "season": 2,
                  "peak_tier": tier, "peak_division": div}}
    if extra:
        a.update(extra)
    return a
hiepsi = acc("HiepSi", 2, 1, 2, 1240, 7, 3, {
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
    "HauTuoc1": acc("HauTuoc1", 5, 0, 7, 1710, 22, 11),
    "BaTuoc1": acc("BaTuoc1", 4, 1, 1, 1490, 15, 10),
    "NamTuoc1": acc("NamTuoc1", 3, 2, 0, 1330, 11, 9),
    "HiepSi": hiepsi,
  },
  "tokens": {},
  "meta": {"season_epoch": str(EPOCH)},
}
json.dump(store, open(sys.argv[1], "w"))
print("seeded store")
EOF

(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || { echo "BUILD FAIL"; exit 1; }
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1

# 1) Home (the game's own --mp-shot-home auto-driver).
SHOT1="$ROOT/shots/empire_age_home_lobby_v7.png"
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1280x720 \
  -- --mp-shot-home="$SHOT1" --mp-account=HiepSi:secret1 \
  > "$WORK/client1.log" 2>&1
grep -a "home shot saved" "$WORK/client1.log" > /dev/null \
  || { echo "NO HOME SHOT"; tail -20 "$WORK/client1.log"; exit 1; }
echo "HOME CAPTURE OK: $SHOT1"

# 2) Mode-choice panel with the painted badges.
timeout 280 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1280x720 \
  res://tests/capture_mode_panel_v2.tscn \
  > "$WORK/client2.log" 2>&1
grep -a "MODE PANEL V2 CAPTURE SAVED" "$WORK/client2.log" > /dev/null \
  || { echo "NO MODE PANEL SHOT"; tail -20 "$WORK/client2.log"; exit 1; }
echo "MODE PANEL CAPTURE OK: $ROOT/shots/empire_age_home_mode_panel_v2.png"

# 3) Leaderboard on the Liên minh tab (empty state).
timeout 280 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1280x720 \
  res://tests/capture_lb_alliance.tscn \
  > "$WORK/client3.log" 2>&1
grep -a "LB ALLIANCE CAPTURE SAVED" "$WORK/client3.log" > /dev/null \
  || { echo "NO LB SHOT"; tail -20 "$WORK/client3.log"; exit 1; }
echo "LB CAPTURE OK: $ROOT/shots/empire_age_leaderboard_v5.png"
