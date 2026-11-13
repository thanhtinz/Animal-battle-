#!/usr/bin/env bash
# Capture harness for 17b (alliance expansion) — REAL screens,
# real server data:
#   1. empire_age_alliance17b_notice_crown_v1.png — the leader's
#      joined screen: profile card with the [SL17] tag, the
#      "Vô địch tuần trước" crown marker and the notice board.
#   2. empire_age_alliance17b_quests_v1.png — the Nhiệm vụ tab
#      with three weekly quests mid-progress.
#   3. empire_age_alliance17b_detail_v1.png — the member
#      detail card open over the Thành viên tab.
#   4. empire_age_alliance17b_tag_chat_v1.png — the alliance
#      chat view: persisted history lines with [SL17] tags.
#
# Seed flow: the real 17b smoke drivers (lead + mem) build a
# genuine alliance (tag, notice, chat history, deputy) against
# a persistent store; a python fixture pass then sets the
# weekly-quest progress + member counters and records last
# week's championship in the store meta (the same shape the
# server's own settlement writes) so the crown renders.
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

(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1
curl -sf "http://127.0.0.1:8765/healthz" > /dev/null || { echo "FAIL: server not up"; exit 1; }
echo "server up"

echo "== seed: real 17b drivers build the alliance =="
timeout 200 "$GODOT" --headless --fixed-fps 30 --path "$ROOT" -- \
  --mp-account=Ally2Lead:secret1 --mp-nokill --mp-hold=100000 \
  --mp-alliance2=lead --mp-alliance-name="Hội Sông Lam 17b" \
  --mp-alliance-tag=SL17 > "$WORK/lead.log" 2>&1 &
LEAD_PID=$!
for _ in $(seq 1 90); do
  grep -q "MPLOG ally2 created id=" "$WORK/lead.log" 2>/dev/null && break
  sleep 1
done
grep -q "MPLOG ally2 created id=" "$WORK/lead.log" || {
  echo "FAIL: leader never created the alliance"; tail -20 "$WORK/lead.log"; exit 1; }
timeout 200 "$GODOT" --headless --fixed-fps 30 --path "$ROOT" -- \
  --mp-account=Ally2Mem:secret1 --mp-nokill --mp-hold=100000 \
  --mp-alliance2=mem --mp-alliance-name="Hội Sông Lam 17b" \
  --mp-alliance-tag=SL17 > "$WORK/mem.log" 2>&1 &
MEM_PID=$!
wait $LEAD_PID $MEM_PID
grep -q "MPLOG ally2 lead done" "$WORK/lead.log" && grep -q "MPLOG ally2 mem done" "$WORK/mem.log" || {
  echo "FAIL: seed flow incomplete"; tail -5 "$WORK/lead.log" "$WORK/mem.log"; exit 1; }
echo "seed flow done"
kill "$SRV_PID" 2>/dev/null; SRV_PID=""
sleep 1

echo "== fixture: quest progress + crown record =="
python3 - "$WORK/store.json" <<'EOF'
import json, sys, datetime
path = sys.argv[1]
data = json.load(open(path))
today = datetime.date.today()
monday = today - datetime.timedelta(days=today.weekday())
lastmonday = monday - datetime.timedelta(days=7)
wk = monday.strftime("%Y-%m-%d")
lwk = lastmonday.strftime("%Y-%m-%d")
ally = next(iter(data["alliances"].values()))
ally["quests"] = {"week": wk, "matches": 27, "wins": 11, "ranked_wins": 3}
stats = {"Ally2Lead": (240, 12, 8), "Ally2Mem": (150, 9, 5)}
for m in ally["members"]:
    m["week_key"] = wk
    pts, games, wins = stats.get(m["user"], (0, 0, 0))
    m["week_pts"], m["week_games"], m["week_wins"] = pts, games, wins
now = int(datetime.datetime.now().timestamp())
ally.setdefault("chat", []).extend([
    {"user": "Ally2Mem", "name": "Ally2Mem",
     "text": "Tối nay mình đánh xếp hạng mấy giờ vậy mọi người?", "at": now - 3600},
    {"user": "Ally2Lead", "name": "Ally2Lead",
     "text": "20h nhé, ai vào được thì điểm danh ở đây", "at": now - 3500},
])
meta = data.setdefault("meta", {})
meta["alliance_champions"] = json.dumps(
    [{"week": lwk, "id": ally["id"], "name": ally["name"], "points": 432}])
meta["alliance_champ_settled"] = lwk
json.dump(data, open(path, "w"))
print("fixture ok: week", wk, "champ week", lwk, "alliance", ally["id"])
EOF

"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server2.log" 2>&1 &
SRV_PID=$!
sleep 1
curl -sf "http://127.0.0.1:8765/healthz" > /dev/null || { echo "FAIL: server not up (2)"; exit 1; }
echo "server up (seeded store)"

shot() { # shot <account> <outfile> <extra args...>
  local acct=$1 out=$2; shift 2
  echo "== shot: $out (account $acct) =="
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
    --resolution 1280x720 -- \
    --mp-shot-alliance2="$ROOT/shots/$out" \
    --mp-account="$acct:secret1" "$@" 2>&1 | grep -E "MPLOG|SCRIPT ERROR" | head -6
}

shot Ally2Lead empire_age_alliance17b_notice_crown_v1.png --mp-alliance2-tab=members
shot Ally2Mem empire_age_alliance17b_quests_v1.png --mp-alliance2-tab=quests
shot Ally2Lead empire_age_alliance17b_detail_v1.png --mp-alliance2-tab=members --mp-alliance2-member=Ally2Mem
shot Ally2Mem empire_age_alliance17b_tag_chat_v1.png --mp-alliance2-tab=chat
# TOUR additions: the Hoạt động (activity) tab + the leaderboard
# Liên minh tab against this same seeded store.
shot Ally2Lead empire_age_alliance_tour_activity_v1.png --mp-alliance2-tab=activity
echo "== shot: leaderboard alliance tab =="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
  --resolution 1280x720 res://tests/capture_tour_lb_alliance.tscn \
  2>&1 | grep -E "TOUR LB|SCRIPT ERROR" | head -4

ls -la "$ROOT/shots/empire_age_alliance_tour_activity_v1.png" \
       "$ROOT/shots/empire_age_leaderboard_tour_alliance_v1.png" \
       "$ROOT/shots/empire_age_alliance17b_notice_crown_v1.png" \
       "$ROOT/shots/empire_age_alliance17b_quests_v1.png" \
       "$ROOT/shots/empire_age_alliance17b_detail_v1.png" \
       "$ROOT/shots/empire_age_alliance17b_tag_chat_v1.png"
