#!/usr/bin/env bash
# Capture harness for the 17e badge addendum (alliance badge
# = icon + colour):
#   empire_age_allybadge_create_v1.png  — create form, picker
#     preset Phượng Hoàng (icon 3) + Tím (colour 4).
#   empire_age_allybadge_create_v2.png  — create form, picker
#     preset Bánh Răng (icon 10) + Cam (colour 5).
#   empire_age_allybadge_profile_v1.png — joined profile card
#     of a seeded alliance wearing Phượng Hoàng tím.
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
def acct(user, name):
    return {"user": user, "salt": salt, "hash": pw("secret1", salt),
            "created": now - 90000, "display_name": name,
            "wins": 0, "losses": 0, "matches": 0, "mmr": 1000,
            "last_played": now - 3600}
ally = {"id": "ALB1", "name": "Hội Phượng Hoàng", "tag": "PHX",
        "badge_icon": 3, "badge_color": 4, "mode": "open",
        "desc": "Liên minh kiểm thử huy hiệu", "leader": "BadgeLead",
        "xp": 1200, "created_at": now - 86400,
        "members": [{"user": "BadgeLead", "role": "leader",
                     "joined_at": now - 86400, "week_key": "2026-11-09"}]}
json.dump({"accounts": {"BadgeShot": acct("BadgeShot", "NguoiTaoHoi"),
                        "BadgeLead": acct("BadgeLead", "TruongHoiPHX")},
           "alliances": {"ALB1": ally}},
          open(sys.argv[1], "w"))
print("seeded BadgeShot / BadgeLead + alliance ALB1 (icon 3, colour 4)")
EOF

"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1
curl -sf "http://127.0.0.1:8765/healthz" > /dev/null || { echo "FAIL: server not up"; exit 1; }
echo "server up"

shot_create() { # shot_create <badge> <outfile>
  echo "== shot: $2 (create form, badge $1) =="
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
    --resolution 1152x648 -- \
    --mp-account=BadgeShot:secret1 \
    --mp-shot-alliance="$ROOT/shots/$2" --mp-alliance-createform=1 \
    --mp-alliance-badge="$1" \
    2>&1 | grep -E "MPLOG|SCRIPT ERROR" | head -4
}

shot_create 3,4  empire_age_allybadge_create_v1.png
shot_create 10,5 empire_age_allybadge_create_v2.png

echo "== shot: empire_age_allybadge_profile_v1.png (joined, icon 3 colour 4) =="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
  --resolution 1152x648 -- \
  --mp-account=BadgeLead:secret1 \
  --mp-shot-alliance="$ROOT/shots/empire_age_allybadge_profile_v1.png" \
  2>&1 | grep -E "MPLOG|SCRIPT ERROR" | head -4

ls -la "$ROOT/shots/"empire_age_allybadge_*.png
