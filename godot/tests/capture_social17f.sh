#!/usr/bin/env bash
# Capture harness for 17f (social + flag badge + create v2 +
# custom avatar) — REAL screens against a seeded server.
# Accounts: SocA (friends [SocB], granted frame_01, wins 12)
# and SocB; two posts are seeded in the store: SocB's image
# post (already liked by SocA — the red heart) and SocA's own
# hero post (the Album source).
#   empire_age_social17f_feed_v1.png          profile MXH — Bảng tin
#   empire_age_social17f_wall_v1.png          profile MXH — Tường nhà
#   empire_age_social17f_album_v1.png         profile MXH — Album ảnh
#   empire_age_social17f_allyposts_v1.png     alliance Bài viết tab
#                                             (+ FLAG on the profile card)
#   empire_age_social17f_allylb_v1.png        leaderboard rows (flag chips)
#   empire_age_social17f_create_v1.png        create form v2 (flag preview)
#   empire_age_social17f_avatarup_v1.png      settings avatar tab,
#                                             upload cell + custom equipped
#   empire_age_social17f_profilecustom_v1.png profile card wearing the
#                                             custom photo + frame_01
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
def acct(user, friends, wins):
    return {"user": user, "salt": salt, "hash": pw("secret1", salt),
            "created": now - 90000, "display_name": user,
            "wins": wins, "losses": 4, "matches": wins + 4, "mmr": 1000,
            "last_played": now - 3600, "friends": friends,
            "granted_frames": ["frame_01"],
            "rank": {"tier": 1, "division": 2, "stars": 1, "streak": 0,
                     "season": 1, "peak_tier": 1, "peak_division": 2}}
posts = {
    "pseedb1": {"id": "pseedb1", "author": "SocB", "scope": "",
     "text": "Chiều nay ai vào trận không? Bè của mình lên đời III rồi [e:vui]",
     "image": "art:07", "at": now - 3600, "seq": 1, "likes": ["SocA"]},
    "pseeda1": {"id": "pseeda1", "author": "SocA", "scope": "",
     "text": "Kỵ sĩ của mình vừa thắng trận đầu tiên!",
     "image": "hero:knight", "at": now - 7200, "seq": 2, "likes": ["SocB"]},
}
json.dump({"accounts": {
    "SocA": acct("SocA", ["SocB"], 12),
    "SocB": acct("SocB", ["SocA"], 9),
}, "posts": posts}, open(sys.argv[1], "w"))
print("seeded SocA / SocB + 2 posts")
EOF

"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1
curl -sf "http://127.0.0.1:8765/healthz" > /dev/null || { echo "FAIL: server not up"; exit 1; }
echo "server up"

shot() { # shot <mode> <outfile>
  local mode=$1 out=$2
  echo "== shot: $out (mode $mode) =="
  timeout 150 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
    --resolution 1280x720 -- \
    --mp-account=SocA:secret1 \
    --mp-shot-social="$mode" --mp-shot-file="$ROOT/shots/$out" \
    2>&1 | grep -E "MPLOG|SCRIPT ERROR" | head -4
}

# ORDER MATTERS: the store persists across shots in one
# run — "create" must run BEFORE the ally modes join SocA
# into an alliance.
shot feed          empire_age_social17f_feed_v1.png
shot wall          empire_age_social17f_wall_v1.png
shot album         empire_age_social17f_album_v1.png
shot create        empire_age_social17f_create_v2.png
shot allyposts     empire_age_social17f_allyposts_v1.png
shot allylb        empire_age_social17f_allylb_v1.png
shot avatarup      empire_age_social17f_avatarup_v1.png
shot profilecustom empire_age_social17f_profilecustom_v1.png

ls -la "$ROOT/shots/"empire_age_social17f_*_v1.png
