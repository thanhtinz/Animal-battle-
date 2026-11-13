#!/usr/bin/env bash
# Capture harness for 17g (report / comments / shares) —
# REAL screens against a seeded server, all as SocA.
# Seeded: SocB's image post (with two seeded comments: a
# top-level from SocA + SocB's reply), SocA's hero post,
# and SocA's SHARE of SocB's post (oldest, so the feed
# opens on SocB's post).
#   empire_age_social17g_report_v1.png   feed: flag button +
#                                        Thích/Bình luận/Chia sẻ row
#   empire_age_social17g_comments_v1.png feed: comment section
#                                        open + reply chip
#   empire_age_social17g_share_v1.png    wall: the share with
#                                        its embedded original
#   empire_age_social17g_chooser_v1.png  the share chooser
#                                        (no alliance → disabled)
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
    "pshare1": {"id": "pshare1", "author": "SocA", "scope": "",
     "text": "", "at": now - 9000, "seq": 3,
     "shared_from": {"orig_post_id": "pseedb1", "orig_author": "SocB",
                     "orig_author_name": "SocB", "orig_scope": ""}},
}
comments = {
    "cseed1": {"id": "cseed1", "post_id": "pseedb1", "author": "SocA",
     "text": "Đúng đó, lên đời III là khác hẳn [e:vui]",
     "at": now - 3000, "seq": 10},
    "cseed2": {"id": "cseed2", "post_id": "pseedb1", "parent_id": "cseed1",
     "author": "SocB", "text": "Tối nay 8 giờ mình mở phòng, bạn vào nhé",
     "at": now - 2400, "seq": 11},
}
json.dump({"accounts": {
    "SocA": acct("SocA", ["SocB"], 12),
    "SocB": acct("SocB", ["SocA"], 9),
}, "posts": posts, "post_comments": comments}, open(sys.argv[1], "w"))
print("seeded SocA / SocB + 3 posts + 2 comments")
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

shot greport   empire_age_social17g_report_v1.png
shot gcomments empire_age_social17g_comments_v1.png
shot gshare    empire_age_social17g_share_v1.png
shot gchooser  empire_age_social17g_chooser_v1.png

ls -la "$ROOT/shots/"empire_age_social17g_*_v1.png
