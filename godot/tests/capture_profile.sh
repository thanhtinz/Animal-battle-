#!/usr/bin/env bash
# Capture harness for the profile screen (13l):
#   1. empire_age_profile_v1.png     (HiepSi: Lv.2, ID 4,
#      Kỵ Sĩ II with 13 season stars, prev season Hầu Tước I
#      with 37 stars, winrate 70,0%, credit 100)
#   2. empire_age_home_lobby_v10.png (Home after the 13l
#      addenda: SQUARE gold-framed avatar top-left, top-right
#      row without the friends icon, bottom row with only
#      BẢNG XẾP HẠNG + BẮT ĐẦU, display-only rank pill)
# Seeds a FileStore, builds the relay from ../server, and
# drives the client twice against it. The guest variant is
# tests/capture_profile_guest.tscn (no server needed).
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
accounts = {}
# A small ranked ladder above and around HiepSi, the subject.
accounts["HoangDe1"] = acc("HoangDe1", 6, 0, 27, 1900, 40, 12)
accounts["CongTuoc1"] = acc("CongTuoc1", 6, 0, 9, 1750, 33, 15)
accounts["HauTuoc1"] = acc("HauTuoc1", 5, 0, 6, 1600, 25, 14)
accounts["BaTuoc1"] = acc("BaTuoc1", 4, 0, 4, 1480, 19, 12)
accounts["NamTuoc1"] = acc("NamTuoc1", 3, 1, 1, 1330, 12, 11)
# HiepSi: 10 recorded matches, 7 wins -> XP 10*10 + 20*7 = 240
# -> Lv.2 (140/200 into the level). Current season 2: Kỵ Sĩ II,
# 2 division stars, 13 gross season stars. Season 1 finished
# at Hầu Tước I with 37 gross stars (archived history).
accounts["HiepSi"] = acc("HiepSi", 2, 1, 2, 1240, 7, 3, {
    "friends": ["CongTuoc1"],
    "avatar_id": "ngan_ky",
    "season_stars": 13,
    "history": [{"season": 1, "final_tier": 5, "final_division": 2,
                 "final_stars": 4, "peak_tier": 5, "peak_division": 2,
                 "total_stars": 37, "emperor": False}],
    "letters": [{"id": 1, "from": "Hệ thống",
                 "subject": "Chào mừng đến với Empire Age!",
                 "body": "Chúc bạn leo hạng vui vẻ.",
                 "sent": now - 86400, "read": False}]})
store = {"accounts": accounts,
         "meta": {"season_epoch": str(EPOCH)},
         "sessions": {}}
json.dump(store, open(sys.argv[1], "w"), ensure_ascii=False)
print("seeded", len(accounts), "accounts")
EOF

cp "$WORK/store.json" "$WORK/store-run.json"

echo "== build relay =="
(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || exit 1

"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store-run.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1
kill -0 "$SRV_PID" 2>/dev/null || { cat "$WORK/server.log"; exit 1; }

echo "== profile shot =="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
  --resolution 1280x720 -- \
  --mp-shot-profile="$ROOT/shots/empire_age_profile_v1.png" \
  --mp-account=HiepSi:secret1 2>&1 | grep -E "MPLOG|ERROR" | head -5

echo "== home shot (square avatar + slimmed rows) =="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
  --resolution 1280x720 -- \
  --mp-shot-home="$ROOT/shots/empire_age_home_lobby_v10.png" \
  --mp-account=HiepSi:secret1 2>&1 | grep -E "MPLOG|ERROR" | head -5

ls -la "$ROOT/shots/empire_age_profile_v1.png" \
       "$ROOT/shots/empire_age_home_lobby_v10.png"
