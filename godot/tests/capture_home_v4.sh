#!/usr/bin/env bash
# Home-lobby screenshot harness (13g, v4 polish): seeds a FileStore whose
# viewer account "HiepSi" sits at Kỵ Sĩ II · 2 sao in season 2
# (epoch aged 91 days), with one friend, one unread system letter
# and two banked ranked results — boots the relay plus one
# windowed client whose Net auto-driver logs in and photographs
# the painted home screen at 1280x720.
set -u
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
GO="${GO:-$HOME/workspace/tools/goroot/bin/go}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$(cd "$ROOT/../server" && pwd)"
WORK="$(mktemp -d)"
SHOT="$ROOT/shots/empire_age_home_lobby_v4.png"
mkdir -p "$ROOT/shots"
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
EPOCH = now - 91 * 86400  # season 2
def acc(user, tier, div, stars, mmr, wins, losses, extra=None):
    a = {"user": user, "salt": salt, "hash": pw("secret1", salt),
         "created": now - 90000, "wins": wins, "losses": losses,
         "matches": wins + losses, "mmr": mmr,
         "rank": {"tier": tier, "division": div, "stars": stars,
                  "season": 2, "peak_tier": tier, "peak_division": div}}
    if extra:
        a.update(extra)
    return a
hiepsi = acc("HiepSi", 2, 1, 2, 1240, 7, 3, {
    "friends": ["CongTuoc1"],
    "letter_seq": 1,
    "letters": [{"id": 1, "title": "Chào mừng đến với Empire Age",
                 "body": "Chào HiepSi! Tài khoản của bạn đã sẵn sàng.",
                 "at": now - 86000, "read": False}],
    "match_history": [
        {"opponent": "NamTuoc1", "won": True, "rank_from": "Kỵ Sĩ II · 1 sao",
         "rank_to": "Kỵ Sĩ II · 2 sao", "star_delta": 1,
         "mmr_before": 1224, "mmr_after": 1240, "at": now - 7200},
        {"opponent": "CongTuoc1", "won": False, "rank_from": "Kỵ Sĩ II · 2 sao",
         "rank_to": "Kỵ Sĩ II · 2 sao", "star_delta": 0,
         "mmr_before": 1253, "mmr_after": 1240, "at": now - 3600}],
    "history": [{"season": 1, "final_tier": 1, "final_division": 0,
                 "final_stars": 2, "peak_tier": 1, "peak_division": 1}],
})
store = {
  "accounts": {
    "HoangDe1": acc("HoangDe1", 6, 0, 27, 2560, 40, 5),
    "CongTuoc1": acc("CongTuoc1", 6, 0, 12, 1980, 30, 9),
    "HauTuoc1": acc("HauTuoc1", 5, 0, 7, 1710, 22, 11),
    "BaTuoc1": acc("BaTuoc1", 4, 1, 1, 1490, 15, 10),
    "NamTuoc1": acc("NamTuoc1", 3, 2, 0, 1330, 11, 9),
    "HiepSi": hiepsi,
  },
  "meta": {"season_epoch": str(EPOCH)},
}
json.dump(store, open(sys.argv[1], "w"))
EOF

(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || { echo "BUILD FAIL"; exit 1; }
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1

timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1280x720 \
  -- --mp-shot-home="$SHOT" --mp-account=HiepSi:secret1 \
  > "$WORK/client.log" 2>&1
grep -a "home shot saved" "$WORK/client.log" > /dev/null \
  || { echo "NO SHOT"; tail -20 "$WORK/client.log"; exit 1; }
[ -f "$SHOT" ] || { echo "SHOT FILE MISSING"; exit 1; }
python3 -c "
from PIL import Image
im = Image.open('$SHOT')
print('shot size:', im.size)
assert im.size == (1280, 720), 'unexpected size'
" 2>/dev/null || file "$SHOT"
echo "HOME CAPTURE OK: $SHOT"
