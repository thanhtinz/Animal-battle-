#!/usr/bin/env bash
# Capture harness for the 17i leaderboard redesign (the
# friends-panel language applied to Bảng xếp hạng: one
# content card, segmented tabs, row cards, own-rank
# footer folded into the card):
#   1. empire_age_leaderboard_v2_server_v1.png   Toàn
#      server tab: 7-player ladder — wreaths + gold /
#      silver / bronze tints on top 3, plain numbers
#      below, the viewer (HiepSi, #7) gold-bordered in
#      the list AND in the footer strip.
#   2. empire_age_leaderboard_v2_friends_v1.png  Bạn bè
#      tab: the same table filtered to HiepSi + his 3
#      friends.
#   3. empire_age_leaderboard_v2_alliance_v1.png Liên
#      minh tab: 4 seeded alliances with weekly points
#      (432 / 300 / 180 / 155); #1 carries last week's
#      crown, the viewer's own alliance (#4, a plain
#      row) is gold-bordered and named in the footer.
#   4. empire_age_leaderboard_v2_empty_v1.png  Liên
#      minh tab against a store with NO alliances at
#      all: the centred empty state (FA shield + one
#      line) over the no-alliance footer. (The friends
#      board always contains the viewer, so its empty
#      state is not reachable through the real relay.)
# Modelled on tests/capture_friends_v2.sh (store seed)
# and tests/capture_lb4.sh (the proven ladder seed).
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

python3 - "$WORK/store.json" "$WORK/store_bare.json" <<'EOF'
import datetime, hashlib, json, sys
def pw(password, salt_hex):
    return hashlib.pbkdf2_hmac("sha256", password.encode(),
                               bytes.fromhex(salt_hex), 120000).hex()
salt = "00112233445566778899aabbccddeeff"
now = int(datetime.datetime.now().timestamp())
EPOCH = now - 91 * 86400  # season 2 (90-day seasons)
def rk(tier, div, stars, peak_tier, peak_div):
    return {"tier": tier, "division": div, "stars": stars,
            "streak": 0, "season": 2,
            "peak_tier": peak_tier, "peak_division": peak_div}
def acc(user, rank, wins, losses, mmr, extra=None):
    a = {"user": user, "salt": salt, "hash": pw("secret1", salt),
         "created": now - 90000, "wins": wins, "losses": losses,
         "matches": wins + losses, "mmr": mmr,
         "last_played": now - 3600, "rank": rank}
    if extra:
        a.update(extra)
    return a
accounts = {
  "CongTuocX": acc("CongTuocX", rk(6, 0, 27, 6, 0), 40, 18, 2130,
                   {"display_name": "Công Tước Ca",
                    "avatar_id": "art:07", "frame_id": "frame_06",
                    "granted_frames": ["frame_06"]}),
  "HauTuocX": acc("HauTuocX", rk(5, 2, 4, 5, 2), 31, 14, 1710,
                  {"display_name": "Hầu Tước Bay",
                   "avatar_id": "art:12"}),
  "BaTuocX": acc("BaTuocX", rk(4, 0, 3, 4, 2), 25, 20, 1560,
                 {"display_name": "Bá Tước Trầm",
                  "avatar_id": "art:05"}),
  "NamTuocX": acc("NamTuocX", rk(3, 2, 1, 3, 2), 19, 12, 1420,
                  {"display_name": "Nam Tước Nhỏ",
                   "avatar_id": "art:09"}),
  "KySiMot": acc("KySiMot", rk(2, 2, 1, 2, 2), 16, 13, 1330,
                 {"display_name": "Kỵ Sĩ Một",
                  "avatar_id": "art:03"}),
  "KySiHai": acc("KySiHai", rk(2, 1, 3, 2, 1), 15, 14, 1290,
                 {"display_name": "Kỵ Sĩ Hai",
                  "avatar_id": "art:11"}),
  "HiepSi": acc("HiepSi", rk(2, 1, 2, 4, 1), 18, 15, 1240,
                {"display_name": "Hiệp Sĩ",
                 "avatar_id": "art:02",
                 "friends": ["CongTuocX", "BaTuocX", "KySiHai"]}),
}
today = datetime.date.today()
monday = today - datetime.timedelta(days=today.weekday())
lastmonday = monday - datetime.timedelta(days=7)
wk = monday.strftime("%Y-%m-%d")
lwk = lastmonday.strftime("%Y-%m-%d")
def member(user, role, pts):
    return {"user": user, "role": role, "joined_at": now - 30 * 86400,
            "week_key": wk, "week_pts": pts,
            "week_games": 6, "week_wins": 3}
def ally(aid, name, tag, icon, color, leader, xp, members):
    return {"id": aid, "name": name, "tag": tag,
            "badge_icon": icon, "badge_color": color,
            "mode": "open", "leader": leader, "xp": xp,
            "created_at": now - 30 * 86400, "members": members,
            "quests": {"week": wk, "matches": 0, "wins": 0,
                       "ranked_wins": 0}}
alliances = {
  "ally_seed_1": ally("ally_seed_1", "Hội Sông Lam", "SLAM", 2, 1,
                      "CongTuocX", 5200,
                      [member("CongTuocX", "leader", 300),
                       member("HauTuocX", "member", 132)]),
  "ally_seed_2": ally("ally_seed_2", "Liên Minh Thép", "THEP", 6, 0,
                      "BaTuocX", 1500,
                      [member("BaTuocX", "leader", 210),
                       member("KySiHai", "member", 90)]),
  "ally_seed_4": ally("ally_seed_4", "Hội Gió Bắc", "GIOB", 4, 2,
                      "NamTuocX", 900,
                      [member("NamTuocX", "leader", 180)]),
  "ally_seed_3": ally("ally_seed_3", "Hội Tân Binh", "TANB", 7, 4,
                      "HiepSi", 400,
                      [member("HiepSi", "leader", 120),
                       member("KySiMot", "member", 35)]),
}
store = {
  "accounts": accounts,
  "alliances": alliances,
  "tokens": {},
  "meta": {"season_epoch": str(EPOCH),
           "alliance_champions": json.dumps(
               [{"week": lwk, "id": "ally_seed_1",
                 "name": "Hội Sông Lam", "points": 432}]),
           "alliance_champ_settled": lwk},
}
json.dump(store, open(sys.argv[1], "w"))
print("seeded store: 7 accounts, 4 alliances, week", wk)
# A second store with the SAME accounts but no alliances
# at all — for the alliance-tab empty state.
bare = {"accounts": accounts, "tokens": {},
        "meta": {"season_epoch": str(EPOCH)}}
json.dump(bare, open(sys.argv[2], "w"))
EOF

(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || { echo "BUILD FAIL"; exit 1; }

start_server() { # start_server <storefile>
  "$WORK/relay" -addr 127.0.0.1:8765 -store "$1" \
    > "$WORK/server.log" 2>&1 &
  SRV_PID=$!
  sleep 1
  curl -sf "http://127.0.0.1:8765/healthz" > /dev/null \
    || { echo "SERVER FAIL"; tail -5 "$WORK/server.log"; exit 1; }
  echo "server up (store $1)"
}
stop_server() {
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
  SRV_PID=""
  sleep 0.5
}

shot() { # shot <mode> <outfile> [account]
  local mode=$1 out=$2 acct=${3:-HiepSi}
  echo "== shot: $out (mode $mode, account $acct) =="
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" \
    "$GODOT" --path "$ROOT" --resolution 1152x648 \
    res://tests/capture_leaderboard_v2.tscn -- \
    --lb2-mode="$mode" --lb2-account="$acct" \
    --lb2-file="$ROOT/shots/$out" \
    > "$WORK/shot_${mode}_${acct}.log" 2>&1
  grep -a "MPLOG lb2 shot saved" "$WORK/shot_${mode}_${acct}.log" > /dev/null \
    || { echo "NO SHOT ($mode/$acct)"; tail -20 "$WORK/shot_${mode}_${acct}.log"; exit 1; }
  echo "CAPTURE OK: $out"
}

start_server "$WORK/store_bare.json"
shot alliance empire_age_leaderboard_v2_empty_v1.png
stop_server
start_server "$WORK/store.json"
shot ranked empire_age_leaderboard_v2_server_v1.png
shot friends empire_age_leaderboard_v2_friends_v1.png
shot alliance empire_age_leaderboard_v2_alliance_v1.png
