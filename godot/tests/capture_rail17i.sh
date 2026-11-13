#!/usr/bin/env bash
# Capture harness for the 17i home-rail polish (glass strip,
# 40px medallions on the strip's top corners, dashed "+",
# 40px AvatarFrame portraits with presence dots):
#   empire_age_lobby_rail_v2.png — Home at 1152x648 for
#   account HiepSi with THREE close friends: CongTuoc1
#   ONLINE (idle client) wearing granted frame_06,
#   HauTuoc1 offline 7h, BaTuoc1 offline 2 days — so the
#   rail shows 3 portraits (1 green dot, 2 grey), the "+"
#   dashed chip (3 < 4 slots), and the friends medallion's
#   presence dot lit.
# Modelled on tests/capture_friends_v2.sh (same seed style,
# current "art:NN" avatar ids + grant-model frame fields).
set -u
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
GO="${GO:-$HOME/workspace/tools/goroot/bin/go}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$(cd "$ROOT/../server" && pwd)"
WORK="$(mktemp -d)"
mkdir -p "$ROOT/shots"
SRV_PID=""
IDLE_PID=""
cleanup() {
  [ -n "$IDLE_PID" ] && kill "$IDLE_PID" 2>/dev/null
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
    "display_name": "Hiệp Sĩ",
    "friends": ["CongTuoc1", "HauTuoc1", "BaTuoc1", "NamTuoc1"],
    "close_friends": ["CongTuoc1", "HauTuoc1", "BaTuoc1"],
    "avatar_id": "art:02",
})
store = {
  "accounts": {
    "CongTuoc1": acc("CongTuoc1", 6, 0, 12, 1980, 32, 7,
                     {"display_name": "Công Tước Ca",
                      "avatar_id": "art:07",
                      "frame_id": "frame_06",
                      "granted_frames": ["frame_06"]}),
    "HauTuoc1": acc("HauTuoc1", 5, 0, 7, 1710, 22, 11,
                    {"display_name": "Hầu Tước Bay",
                     "avatar_id": "art:12", "last_online": now - 7 * 3600}),
    "BaTuoc1": acc("BaTuoc1", 4, 1, 1, 1490, 15, 10,
                   {"display_name": "Bá Tước Trầm",
                    "avatar_id": "art:05", "last_online": now - 2 * 86400}),
    "NamTuoc1": acc("NamTuoc1", 3, 2, 0, 1330, 6, 4,
                    {"display_name": "Nam Tước Nhỏ",
                     "avatar_id": "art:09", "last_online": now - 35 * 60}),
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

# Idle friend: CongTuoc1 stays online for the capture.
timeout 300 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1152x648 \
  res://tests/capture_friend_idle.tscn \
  > "$WORK/idle.log" 2>&1 &
IDLE_PID=$!
for i in $(seq 1 75); do
  grep -a "IDLE FRIEND LOGIN SENT" "$WORK/idle.log" > /dev/null 2>&1 && break
  sleep 1
done
sleep 3
grep -a "IDLE FRIEND LOGIN SENT" "$WORK/idle.log" > /dev/null \
  || { echo "IDLE FRIEND FAILED"; tail -20 "$WORK/idle.log"; exit 1; }
echo "IDLE FRIEND ONLINE"

SHOT="$ROOT/shots/empire_age_lobby_rail_v2.png"
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1152x648 \
  -- --mp-shot-home="$SHOT" --mp-account=HiepSi:secret1 \
  > "$WORK/client.log" 2>&1
grep -a "home shot saved" "$WORK/client.log" > /dev/null \
  || { echo "NO SHOT"; tail -20 "$WORK/client.log"; exit 1; }
[ -f "$SHOT" ] || { echo "SHOT FILE MISSING"; exit 1; }
echo "HOME CAPTURE OK: $SHOT"

python3 - "$SHOT" "$ROOT/shots/empire_age_lobby_rail_v2_zoom.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
print("shot size:", im.size)
crop = im.crop((1000, 25, 1152, 400))
crop = crop.resize((crop.width * 4, crop.height * 4), Image.NEAREST)
crop.save(sys.argv[2])
print("zoom saved:", sys.argv[2], crop.size)
EOF
