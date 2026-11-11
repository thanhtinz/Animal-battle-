#!/usr/bin/env bash
# Capture harness for 13q-ter (profile frame gaps), derived from the 13q harness (shared info-page shell): ONE
# seeded server, three client runs photographing the three
# info pages that must now share PageShell's background +
# header:
#   1. empire_age_page_profile_v3.png  (Hồ sơ, HiepSi)
#   2. empire_age_page_friends_v1.png  (Bạn bè panel)
#   3. empire_age_page_bxh_v1.png      (Bảng xếp hạng)
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
accounts["HoangDe1"] = acc("HoangDe1", 6, 0, 27, 1900, 40, 12)
accounts["CongTuoc1"] = acc("CongTuoc1", 6, 0, 9, 1750, 33, 15)
accounts["HauTuoc1"] = acc("HauTuoc1", 5, 0, 6, 1600, 25, 14)
accounts["BaTuoc1"] = acc("BaTuoc1", 4, 0, 4, 1480, 19, 12)
accounts["NamTuoc1"] = acc("NamTuoc1", 3, 1, 1, 1330, 12, 11)
accounts["HiepSi"] = acc("HiepSi", 2, 1, 2, 1240, 7, 3, {
    "friends": ["CongTuoc1", "BaTuoc1"],
    "avatar_id": "ngan_ky",
    "season_stars": 13,
    "history": [{"season": 1, "final_tier": 5, "final_division": 2,
                 "final_stars": 4, "peak_tier": 5, "peak_division": 2,
                 "total_stars": 37, "emperor": False}]})
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

shot() {
  local arg="$1" out="$2"
  echo "== $out =="
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
    --resolution 1280x720 -- \
    "$arg=$ROOT/shots/$out" \
    --mp-account=HiepSi:secret1 2>&1 | grep -E "MPLOG|ERROR" | head -5
}

shot --mp-shot-profile empire_age_page_profile_v3.png
shot --mp-shot-friends empire_age_page_friends_v1.png
shot --mp-shot-ranklb empire_age_page_bxh_v1.png

ls -la "$ROOT/shots/empire_age_page_profile_v3.png" \
       "$ROOT/shots/empire_age_page_friends_v1.png" \
       "$ROOT/shots/empire_age_page_bxh_v1.png"
