#!/usr/bin/env bash
# Capture harness for 13r follow-up 2 (util column REMOVED from login):
# column on the entry backgrounds): one relay on a fresh
# store, an ISOLATED XDG profile, then:
#   1. empire_age_login_v4.png         login tab + util column
#   2. empire_age_login_v4_notice.png  Thông báo panel open
#   3. empire_age_welcome_v2.png       welcome screen (restored
#      session) + util column at the right edge (kept)
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
EPOCH = now - 91 * 86400  # season 2 (90-day seasons)
def acc(user, tier, div, stars, mmr, wins, losses, extra=None):
    a = {"user": user, "salt": salt, "hash": pw("secret1", salt),
         "created": now - 90000, "wins": wins, "losses": losses,
         "matches": wins + losses, "mmr": mmr, "last_played": now - 3600,
         "rank": {"tier": tier, "division": div, "stars": stars,
                  "streak": 0, "season": 2,
                  "peak_tier": tier, "peak_division": div}}
    if extra:
        a.update(extra)
    return a
accounts = {"HiepSi": acc("HiepSi", 2, 1, 2, 1240, 7, 3,
                          {"avatar_id": "ngan_ky", "season_stars": 13})}
store = {"accounts": accounts,
         "meta": {"season_epoch": str(EPOCH)},
         "sessions": {}}
json.dump(store, open(sys.argv[1], "w"), ensure_ascii=False)
print("seeded", len(accounts), "accounts")
EOF

cp "$WORK/store.json" "$WORK/store-run.json"

echo "== build relay =="
(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || exit 1
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store-run.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1
kill -0 "$SRV_PID" 2>/dev/null || { cat "$WORK/server.log"; exit 1; }

run() {
  local tag="$1"; shift
  echo "== $tag =="
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
    --resolution 1280x720 -- "$@" 2>&1 | grep -E "MPLOG|ERROR|SCRIPT" | head -30
}

run login   "--mp-shot-login=$ROOT/shots/empire_age_login_v4.png" --mp-norestore

ls -la "$ROOT/shots/empire_age_login_v4.png"
