#!/usr/bin/env bash
# TOUR capture — Chat hub "Hệ thống" tab (17e): the tab renders
# the real system feed + the account mailbox. Same seed family
# as capture_chathub.sh (HubShotA/HubShotB + DM thread), plus
# two real letters in HubShotA's mailbox so the tab has content.
# Driver scene: tests/capture_tour_system.tscn.
set -u
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
GO="${GO:-$HOME/workspace/tools/goroot/bin/go}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$(cd "$ROOT/../server" && pwd)"
WORK="$(mktemp -d)"
mkdir -p "$ROOT/shots" "$WORK/xdg"
export XDG_DATA_HOME="$WORK/xdg"
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
def acct(user, friends, extra=None):
    a = {"user": user, "salt": salt, "hash": pw("secret1", salt),
         "created": now - 90000, "display_name": user,
         "wins": 3, "losses": 2, "matches": 5, "mmr": 1000,
         "last_played": now - 3600, "friends": friends,
         "rank": {"tier": 0, "division": 2, "stars": 0, "streak": 0,
                  "season": 1, "peak_tier": 0, "peak_division": 2}}
    if extra:
        a.update(extra)
    return a
key = "HubShotA\x00HubShotB"
store = {"accounts": {
    "HubShotA": acct("HubShotA", ["HubShotB"], {
        "megaphones": 2,
        "letter_seq": 2,
        "letters": [
          {"id": 1, "title": "Chào mừng đến với Empire Age",
           "body": "Chào HubShotA! Tài khoản của bạn đã sẵn sàng.",
           "at": now - 86000, "read": True},
          {"id": 2, "title": "Bạn nhận được: Khung Dây Dâu Tây",
           "body": "Vật phẩm đã được cộng vào tài khoản. Mở Hồ sơ → Cài đặt → Avatar để trang bị.",
           "at": now - 3600, "read": False},
        ]}),
    "HubShotB": acct("HubShotB", ["HubShotA"]),
  },
  "dms": {key: {"key": key, "users": ["HubShotA", "HubShotB"],
    "unread": {"HubShotA": 1},
    "msgs": [
      {"from": "HubShotB", "name": "HubShotB",
       "text": "Toi nay danh tran khong? [e:vui]", "at": now - 600},
    ]}}}
json.dump(store, open(sys.argv[1], "w"), ensure_ascii=False)
print("seeded HubShotA (2 letters) + HubShotB")
EOF

(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || { echo "server build failed"; exit 1; }
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1
curl -sf "http://127.0.0.1:8765/healthz" > /dev/null || { echo "FAIL: server not up"; exit 1; }
echo "server up"

echo "== shot: chathub system tab =="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
  --resolution 1280x720 res://tests/capture_tour_system.tscn \
  2>&1 | grep -E "TOUR CHATHUB|SCRIPT ERROR" | head -4
ls -la "$ROOT/shots/empire_age_chathub_system_tour_v1.png"
