#!/usr/bin/env bash
# Capture harness for the home rail's REFERENCE design
# (owner-sent screenshot: two-tab header with glowing
# underline, big square framed portraits, diamond badges).
# Portraits are composed by AvatarFrame with each person's
# OWN equipped frame from the owner's frame catalogue —
# the seed grants frames so the shots show them properly:
# CongTuoc1 frame_06 (Sao Vàng), HauTuoc1 frame_01 (Dây
# Dâu Tây), BaTuoc1 frame_08 (Mây Anh Đào), KySiMot
# frame_05 (Sân Khấu Trái Tim); NamTuoc1 and HiepSi carry
# no frame (AvatarFrame's no-frame path).
#   empire_age_rail_sys2_friends_v1.png + _crop — Bạn bè tab:
#     HiepSi's 3 close friends (CongTuoc1 ONLINE via the
#     idle client) + the dashed "+" tile.
#   empire_age_rail_sys2_rank_v1.png + _crop — Xếp hạng tab
#     (--mp-rail-tab=rank): the top 5 of the seeded
#     leaderboard (6 accounts; ladder order CongTuoc1,
#     HauTuoc1, BaTuoc1, NamTuoc1, KySiMot, then HiepSi),
#     diamonds carrying the gold rank numbers 1-5.
# Crops are NATIVE resolution (no upscale/resample) —
# the owner judges sharpness from true pixels.
# Seed modelled on capture_rail17i.sh + one extra
# leaderboard account (as capture_leaderboard_v2.sh).
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
                     "avatar_id": "art:12",
                     "frame_id": "frame_01",
                     "granted_frames": ["frame_01"],
                     "last_online": now - 7 * 3600}),
    "BaTuoc1": acc("BaTuoc1", 4, 1, 1, 1490, 15, 10,
                   {"display_name": "Bá Tước Trầm",
                    "avatar_id": "art:05",
                    "frame_id": "frame_08",
                    "granted_frames": ["frame_08"],
                    "last_online": now - 2 * 86400}),
    "NamTuoc1": acc("NamTuoc1", 3, 2, 0, 1330, 6, 4,
                    {"display_name": "Nam Tước Nhỏ",
                     "avatar_id": "art:09", "last_online": now - 35 * 60}),
    "KySiMot": acc("KySiMot", 1, 0, 1, 1100, 3, 5,
                   {"display_name": "Kỵ Sĩ Một",
                    "avatar_id": "art:11",
                    "frame_id": "frame_05",
                    "granted_frames": ["frame_05"],
                    "last_online": now - 3600}),
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

# Idle friend: CongTuoc1 stays online for the captures.
timeout 600 xvfb-run -a -s "-screen 0 1280x800x24" \
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

shoot() { # $1 = tag, $2 = extra args
  local shot="$ROOT/shots/empire_age_rail_sys2_$1_v1.png"
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" \
    "$GODOT" --path "$ROOT" --resolution 1152x648 \
    -- --mp-shot-home="$shot" --mp-account=HiepSi:secret1 $2 \
    > "$WORK/client_$1.log" 2>&1
  grep -a "home shot saved" "$WORK/client_$1.log" > /dev/null \
    || { echo "NO SHOT ($1)"; tail -20 "$WORK/client_$1.log"; exit 1; }
  [ -f "$shot" ] || { echo "SHOT FILE MISSING ($1)"; exit 1; }
  echo "CAPTURE OK ($1): $shot"
  python3 - "$shot" "$ROOT/shots/empire_age_rail_sys2_$1_crop_v1.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
print("shot size:", im.size)
crop = im.crop((1000, 40, 1152, 620))
crop.save(sys.argv[2])
print("native crop saved:", sys.argv[2], crop.size)
EOF
}

shoot friends ""
shoot rank "--mp-rail-tab=rank"
echo "ALL REF CAPTURES DONE"
