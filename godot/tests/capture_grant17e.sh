#!/usr/bin/env bash
# Capture harness for the 17e grant-model addendum — the
# Khung avatar tab under the ADMIN-GRANT ownership model
# (player-facing wording is events only; no "admin" text):
#   empire_age_settings_frames_grant_v1.png — SetUser owns
#     frame_01 via a grant (lit); every other frame is dimmed
#     with a small "Sự kiện" sub-line.
#   empire_age_settings_frame_detail_v1.png — the item-detail
#     popup on the UNOWNED frame_06: preview + name + the line
#     "Cách nhận: Nhận qua sự kiện" and NO equip button.
# Same seed pattern as capture_settings17d.sh.
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

python3 - "$WORK/store.json" <<'EOF'
import hashlib, json, sys, time
def pw(password, salt_hex):
    return hashlib.pbkdf2_hmac("sha256", password.encode(),
                               bytes.fromhex(salt_hex), 120000).hex()
salt = "00112233445566778899aabbccddeeff"
now = int(time.time())
acct = {"user": "SetUser", "salt": salt, "hash": pw("secret1", salt),
        "created": now - 90000, "display_name": "TenCu17d",
        "wins": 0, "losses": 200, "matches": 200, "mmr": 1000,
        "last_played": now - 3600,
        "granted_frames": ["frame_01"],
        "rank": {"tier": 0, "division": 2, "stars": 0, "streak": 0,
                 "season": 1, "peak_tier": 0, "peak_division": 2}}
json.dump({"accounts": {"SetUser": acct}}, open(sys.argv[1], "w"))
print("seeded SetUser (granted frame_01)")
EOF

"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1
curl -sf "http://127.0.0.1:8765/healthz" > /dev/null || { echo "FAIL: server not up"; exit 1; }
echo "server up"

shot() { # shot <panel> <outfile>
  local panel=$1 out=$2
  echo "== shot: $out (panel $panel) =="
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
    --resolution 1280x720 -- \
    --mp-account=SetUser:secret1 \
    --mp-shot-settings="$panel" --mp-shot-file="$ROOT/shots/$out" \
    2>&1 | grep -E "MPLOG|SCRIPT ERROR" | head -4
}

shot frames       empire_age_settings_frames_grant_v1.png
shot frames_popup empire_age_settings_frame_detail_v1.png

ls -la "$ROOT/shots/"empire_age_settings_frames_grant_v1.png \
       "$ROOT/shots/"empire_age_settings_frame_detail_v1.png
