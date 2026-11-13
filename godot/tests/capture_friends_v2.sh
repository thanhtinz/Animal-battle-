#!/usr/bin/env bash
# Capture harness for the 17i friends-panel golden-screen
# redesign (two cards: menu/online/add card + list card):
#   1. empire_age_friends_v2_list_v1.png   Bạn bè view,
#      4 friends: CongTuoc1 ONLINE (idle client) wearing
#      a granted avatar frame, close friend; BaTuoc1
#      close, offline 2 days; HauTuoc1 offline 7h;
#      NamTuoc1 offline 35 min — tiers 6/5/4/3, Lv 5/4/3/2.
#   2. empire_age_friends_v2_empty_v1.png  fresh account
#      TanThu: the centred empty state.
#   3. empire_age_friends_v2_find_v1.png   Tìm bạn view:
#      the search field inside the right card's header.
# Modelled on tests/capture_friends.sh (13m); the seed
# uses the CURRENT avatar ids ("art:NN", 17d) and the
# grant-model frame fields (17e).
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
    "close_friends": ["CongTuoc1", "BaTuoc1"],
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
    "TanThu": acc("TanThu", 0, 2, 0, 1000, 0, 0,
                  {"display_name": "Tân Thủ", "avatar_id": "art:01"}),
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

# Idle friend: CongTuoc1 stays online for all captures.
timeout 300 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1152x648 \
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
    "$GODOT" --path "$ROOT" --resolution 1152x648 "$@" \
    > "$WORK/$log" 2>&1
}

# 1) Bạn bè view, populated.
SHOT1="$ROOT/shots/empire_age_friends_v2_list_v1.png"
run_client client1.log -- --mp-shot-friends="$SHOT1" --mp-friends-tab=all \
  --mp-account=HiepSi:secret1
grep -a "friends shot saved" "$WORK/client1.log" > /dev/null \
  || { echo "NO LIST SHOT"; tail -20 "$WORK/client1.log"; exit 1; }
echo "LIST CAPTURE OK: $SHOT1"

# 2) Empty state (fresh account, no friends).
SHOT2="$ROOT/shots/empire_age_friends_v2_empty_v1.png"
run_client client2.log -- --mp-shot-friends="$SHOT2" --mp-friends-tab=all \
  --mp-account=TanThu:secret1
grep -a "friends shot saved" "$WORK/client2.log" > /dev/null \
  || { echo "NO EMPTY SHOT"; tail -20 "$WORK/client2.log"; exit 1; }
echo "EMPTY CAPTURE OK: $SHOT2"

# 3) Tìm bạn view with the in-card header search.
SHOT3="$ROOT/shots/empire_age_friends_v2_find_v1.png"
run_client client3.log -- --mp-shot-friends="$SHOT3" --mp-friends-tab=find \
  --mp-account=HiepSi:secret1
grep -a "friends shot saved" "$WORK/client3.log" > /dev/null \
  || { echo "NO FIND SHOT"; tail -20 "$WORK/client3.log"; exit 1; }
echo "FIND CAPTURE OK: $SHOT3"
