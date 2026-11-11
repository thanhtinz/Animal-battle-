#!/usr/bin/env bash
# Capture harness for 13m (friends + BXH right rail on Home,
# banner moved left, redesigned friends panel):
#   1. empire_age_home_rail_v1.png       (Home: banner on the
#      LEFT under the avatar; right rail with Bạn bè / BXH
#      glyph chips, 2 close-friend portraits — CongTuoc1
#      online with dot, BaTuoc1 offline — chevron, "+")
#   2. empire_age_friends_panel_v1.png   (Bạn bè tab: rows
#      with framed avatars, Lv badges, Online + last-seen)
#   3. empire_age_friends_panel_v2.png   (Tìm bạn tab)
# An idle second client keeps CongTuoc1 online throughout.
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
    "friends": ["CongTuoc1", "HauTuoc1", "BaTuoc1", "NamTuoc1"],
    "close_friends": ["CongTuoc1", "BaTuoc1"],
    "avatar_id": "lam_bao",
})
store = {
  "accounts": {
    "HoangDe1": acc("HoangDe1", 6, 0, 27, 2560, 40, 5),
    "CongTuoc1": acc("CongTuoc1", 6, 0, 12, 1980, 30, 9,
                     {"avatar_id": "kim_hoa"}),
    "HauTuoc1": acc("HauTuoc1", 5, 0, 7, 1710, 22, 11,
                    {"avatar_id": "bach_sa", "last_online": now - 7 * 3600}),
    "BaTuoc1": acc("BaTuoc1", 4, 1, 1, 1490, 15, 10,
                   {"avatar_id": "ngan_ky", "last_online": now - 2 * 86400}),
    "NamTuoc1": acc("NamTuoc1", 3, 2, 0, 1330, 11, 9,
                    {"last_online": now - 35 * 60}),
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

# Idle friend: CongTuoc1 stays online for all three captures.
timeout 300 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1280x720 \
  res://tests/capture_friend_idle.tscn \
  > "$WORK/idle.log" 2>&1 &
IDLE_PID=$!
for i in $(seq 1 30); do
  grep -a "IDLE FRIEND LOGIN SENT" "$WORK/idle.log" > /dev/null 2>&1 && break
  sleep 1
done
sleep 3
grep -a "IDLE FRIEND LOGIN SENT" "$WORK/idle.log" > /dev/null \
  || { echo "IDLE FRIEND FAILED"; tail -20 "$WORK/idle.log"; exit 1; }
echo "IDLE FRIEND ONLINE"

run_client() { # $1 = log name, remaining args = godot args
  local log="$1"; shift
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" \
    "$GODOT" --path "$ROOT" --resolution 1280x720 "$@" \
    > "$WORK/$log" 2>&1
}

# 1) Home with the rail + left banner.
SHOT1="$ROOT/shots/empire_age_home_rail_v1.png"
run_client client1.log -- --mp-shot-home="$SHOT1" --mp-account=HiepSi:secret1
grep -a "home shot saved" "$WORK/client1.log" > /dev/null \
  || { echo "NO HOME SHOT"; tail -20 "$WORK/client1.log"; exit 1; }
echo "HOME RAIL CAPTURE OK: $SHOT1"

# 2) Friends panel, Bạn bè tab.
SHOT2="$ROOT/shots/empire_age_friends_panel_v1.png"
run_client client2.log -- --mp-shot-friends="$SHOT2" --mp-friends-tab=all \
  --mp-account=HiepSi:secret1
grep -a "friends shot saved" "$WORK/client2.log" > /dev/null \
  || { echo "NO FRIENDS SHOT"; tail -20 "$WORK/client2.log"; exit 1; }
echo "FRIENDS PANEL CAPTURE OK: $SHOT2"

# 3) Friends panel, Tìm bạn tab.
SHOT3="$ROOT/shots/empire_age_friends_panel_v2.png"
run_client client3.log -- --mp-shot-friends="$SHOT3" --mp-friends-tab=find \
  --mp-account=HiepSi:secret1
grep -a "friends shot saved" "$WORK/client3.log" > /dev/null \
  || { echo "NO FIND SHOT"; tail -20 "$WORK/client3.log"; exit 1; }
echo "FIND TAB CAPTURE OK: $SHOT3"
