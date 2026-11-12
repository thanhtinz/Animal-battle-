#!/usr/bin/env bash
# Capture harness for 17a (alliances) — REAL screens, real data:
#   1. empire_age_alliance_joined_v1.png — the joined screen
#      (mock B layout): ShotMem just joined the request-mode
#      alliance "Hội Sông Lam" founded by ShotLead; both
#      members online in the roster.
#   2. empire_age_alliance_join_v1.png   — the not-joined
#      browser for a fresh account: the recruiting list shows
#      "Hội Sông Lam" (2/30) with its Xin vào button.
# Seeds a FileStore with ShotLead + ShotMem + ShotNew (password
# secret1), builds the relay, and drives windowed clients.
set -u
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
GO="${GO:-$HOME/workspace/tools/goroot/bin/go}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$(cd "$ROOT/../server" && pwd)"
WORK="$(mktemp -d)"
mkdir -p "$ROOT/shots"
SRV_PID=""
LEAD_PID=""
cleanup() {
  [ -n "$LEAD_PID" ] && kill "$LEAD_PID" 2>/dev/null
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
accounts = {}
for user in ["ShotLead", "ShotMem", "ShotNew"]:
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

# Headless leader: founds the alliance and approves applicants
# (it stays in its stage-4 wait until killed — the 110s
# driver timeout is plenty for both shots).
timeout 300 "$GODOT" --headless --fixed-fps 30 --path "$ROOT" -- \
  --mp-account=ShotLead:secret1 --mp-nokill --mp-hold=100000 \
  --mp-alliance=create --mp-alliance-name="Hội Sông Lam" \
  > "$WORK/lead.log" 2>&1 &
LEAD_PID=$!
for _ in $(seq 1 90); do
  grep -q "MPLOG alliance created id=" "$WORK/lead.log" 2>/dev/null && break
  sleep 1
done
grep -q "MPLOG alliance created id=" "$WORK/lead.log" || {
  echo "FAIL: leader never created the alliance"; cat "$WORK/lead.log" | tail -20; exit 1; }
echo "alliance created"

echo "== joined shot (ShotMem applies, leader approves) =="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
  --resolution 1280x720 -- \
  --mp-shot-alliance="$ROOT/shots/empire_age_alliance_joined_v1.png" \
  --mp-account=ShotMem:secret1 \
  --mp-alliance-name="Hội Sông Lam" 2>&1 | grep -E "MPLOG|SCRIPT ERROR" | head -8

echo "== not-joined shot (ShotNew browses) =="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
  --resolution 1280x720 -- \
  --mp-shot-alliance="$ROOT/shots/empire_age_alliance_join_v1.png" \
  --mp-account=ShotNew:secret1 2>&1 | grep -E "MPLOG|SCRIPT ERROR" | head -8

ls -la "$ROOT/shots/empire_age_alliance_joined_v1.png" "$ROOT/shots/empire_age_alliance_join_v1.png"
