#!/usr/bin/env bash
# Empire Age 17e — CHAT HUB captures (all NEW filenames):
#   empire_age_chathub_world_v1.png     Thế giới tab: an emoticon
#                                       line + a voice bubble
#   empire_age_chathub_picker_v1.png    emoticon picker open
#   empire_age_chathub_alliance_v1.png  Liên minh tab in an alliance
#   empire_age_chathub_dm_list_v1.png   Chat riêng conversation list
#   empire_age_chathub_dm_thread_v1.png Chat riêng thread view
#   empire_age_chathub_marquee_v1.png   megaphone marquee mid-scroll
#
# One seeded account (HubShotA, friends with HubShotB, a
# persisted DM thread from HubShotB, 2 megaphones) drives
# every shot through the --mp-shot-chathub driver.
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
    "HubShotA": acct("HubShotA", ["HubShotB"], {"megaphones": 2}),
    "HubShotB": acct("HubShotB", ["HubShotA"]),
  },
  "dms": {key: {"key": key, "users": ["HubShotA", "HubShotB"],
    "unread": {"HubShotA": 1},
    "msgs": [
      {"from": "HubShotB", "name": "HubShotB",
       "text": "Toi nay danh tran khong? [e:vui]", "at": now - 600},
      {"from": "HubShotA", "name": "HubShotA",
       "text": "Ok, 20h tap trung [e:like]", "at": now - 540},
      {"from": "HubShotB", "name": "HubShotB",
       "text": "Nho mang theo Loa nhe [e:tim]", "at": now - 480},
    ]}}}
json.dump(store, open(sys.argv[1], "w"), ensure_ascii=False)
print("seeded HubShotA (megaphones=2) + HubShotB + DM thread")
EOF

(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || { echo "server build failed"; exit 1; }
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1

shot() { # shot <mode> <file>
  echo "== shot $1 -> $2"
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
    --resolution 1152x648 -- \
    --mp-account=HubShotA:secret1 --mp-nokill \
    --mp-shot-chathub=$1 --mp-shot-file="$ROOT/shots/$2" \
    > "$WORK/shot_$1.log" 2>&1
  grep -h "MPLOG chathub" "$WORK/shot_$1.log" | tail -2
  ls -la "$ROOT/shots/$2" 2>/dev/null || echo "MISSING $2"
}

shot world empire_age_chathub_world_v1.png
shot picker empire_age_chathub_picker_v1.png
shot alliance empire_age_chathub_alliance_v1.png
shot dm_list empire_age_chathub_dm_list_v1.png
shot dm_thread empire_age_chathub_dm_thread_v1.png
shot marquee empire_age_chathub_marquee_v1.png
echo "captures done"
