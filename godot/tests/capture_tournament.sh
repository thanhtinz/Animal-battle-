#!/usr/bin/env bash
# Capture harness for 15h (tournaments):
#   1. empire_age_tournament_list_v1.png    — the tournament
#      screen's list view with one freshly created OPEN
#      tournament (the shot client just created it).
#   2. empire_age_tournament_bracket_v1.png — the detail view
#      of a started 4-entry single-elim (both semifinals
#      visible) after 3 headless filler clients registered.
# Seeds a FileStore with ShotUser + Filler1..3 (password
# secret1), builds the relay, and drives windowed clients.
set -u
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
GO="${GO:-$HOME/workspace/tools/goroot/bin/go}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$(cd "$ROOT/../server" && pwd)"
WORK="$(mktemp -d)"
mkdir -p "$ROOT/shots"
SRV_PID=""
FILLERS=""
cleanup() {
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
  for p in $FILLERS; do kill "$p" 2>/dev/null; done
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
accounts = {}
for user in ["ShotUser", "Filler1", "Filler2", "Filler3"]:
    accounts[user] = {"user": user, "salt": salt, "hash": pw("secret1", salt),
                      "created": now - 90000, "wins": 0, "losses": 0,
                      "matches": 0, "mmr": 0,
                      "rank": {"tier": 0, "division": 3, "stars": 0,
                               "season": 1, "peak_tier": 0, "peak_division": 3}}
json.dump({"accounts": accounts, "tokens": {}, "meta": {}}, open(sys.argv[1], "w"))
EOF

(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1
curl -sf "http://127.0.0.1:8765/healthz" > /dev/null || { echo "FAIL: server not up"; exit 1; }
echo "server up"

echo "== tournament list shot =="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
  --resolution 1280x720 -- \
  --mp-shot-tourn-list="$ROOT/shots/empire_age_tournament_list_v1.png" \
  --mp-account=ShotUser:secret1 \
  --mp-tourn-name="Giải Vô Địch Mở Rộng" 2>&1 | grep -E "MPLOG|ERROR" | head -5

echo "== tournament bracket shot (3 fillers registering) =="
for i in 1 2 3; do
  timeout 240 "$GODOT" --headless --fixed-fps 30 --path "$ROOT" -- \
    --mp-tourn=joinany --mp-tourn-name="Giải Vô Địch Mở Rộng" \
    --mp-account=Filler$i:secret1 --mp-hold=100000 \
    > "$WORK/filler$i.log" 2>&1 &
  FILLERS="$FILLERS $!"
done
timeout 240 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
  --resolution 1280x720 -- \
  --mp-shot-tourn-bracket="$ROOT/shots/empire_age_tournament_bracket_v1.png" \
  --mp-account=ShotUser:secret1 \
  --mp-tourn-name="Giải Vô Địch Mở Rộng" 2>&1 | grep -E "MPLOG|ERROR" | head -5

ls -la "$ROOT/shots/empire_age_tournament_list_v1.png" \
       "$ROOT/shots/empire_age_tournament_bracket_v1.png"
