#!/usr/bin/env bash
# Capture harness for the home chip follow-up (name + Lv
# beside the top-left avatar; frameless top-right icons):
#   1. empire_age_home_namelv_v1.png        (HiepSi, Lv.2,
#      avatar lam_bao, 1 unread letter -> badge on the bare
#      envelope glyph; top-right mail/gear/ping frameless)
#   2. empire_age_home_namelv_v1_guest.png  (guest: "Khách"
#      / "Chưa đăng nhập")
# Seed mirrors capture_rail_v5.sh (same ladder accounts).
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
hiepsi = acc("HiepSi", 2, 1, 2, 1240, 7, 3, {
    "friends": ["CongTuoc1", "HauTuoc1", "BaTuoc1", "NamTuoc1"],
    "close_friends": ["CongTuoc1", "BaTuoc1", "HauTuoc1"],
    "avatar_id": "lam_bao",
    "letters": [{"id": 1, "title": "Chào mừng",
                 "body": "Chào mừng bạn đến với Empire Age.",
                 "at": now - 600, "read": False}],
    "letter_seq": 1,
})
store = {
  "accounts": {
    "HoangDe1": acc("HoangDe1", 6, 0, 27, 2560, 40, 5),
    "CongTuoc1": acc("CongTuoc1", 6, 0, 12, 1980, 30, 9,
                     {"avatar_id": "kim_hoa"}),
    "HauTuoc1": acc("HauTuoc1", 5, 0, 7, 1710, 22, 11,
                    {"avatar_id": "bach_sa", "last_online": now - 7 * 3600}),
    "BaTuoc1": acc("BaTuoc1", 4, 1, 1, 1490, 15, 10,
                   {"avatar_id": "ngan_ky", "last_online": now - 2 * 86400}),
    "NamTuoc1": acc("NamTuoc1", 3, 2, 0, 1330, 11, 9,
                    {"last_online": now - 35 * 60}),
    "HiepSi": hiepsi,
  },
  "tokens": {},
  "meta": {"season_epoch": str(EPOCH)},
}
json.dump(store, open(sys.argv[1], "w"))
print("seeded store")
EOF

(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || { echo "BUILD FAIL"; exit 1; }
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1

run_client() { # $1 = log name, remaining args = godot args
  local log="$1"; shift
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" \
    "$GODOT" --path "$ROOT" --resolution 1280x720 "$@" \
    > "$WORK/$log" 2>&1
}

SHOT1="$ROOT/shots/empire_age_home_namelv_v1.png"
run_client client1.log -- --mp-shot-home="$SHOT1" --mp-account=HiepSi:secret1
grep -a "home shot saved" "$WORK/client1.log" > /dev/null \
  || { echo "NO HOME SHOT (member)"; tail -20 "$WORK/client1.log"; exit 1; }
echo "MEMBER CAPTURE OK: $SHOT1"

SHOT2="$ROOT/shots/empire_age_home_namelv_v1_guest.png"
# Guests go through the dedicated scene harness: the
# --mp-shot-home driver waits on the login flow and never
# fires without an account (observed hang, 13i guest
# captures use scenes for the same reason).
timeout 100 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1280x720 \
  res://tests/capture_home_guest_namelv.tscn \
  > "$WORK/client2.log" 2>&1
grep -a "CAPTURE SAVED" "$WORK/client2.log" > /dev/null \
  || { echo "NO HOME SHOT (guest)"; tail -20 "$WORK/client2.log"; exit 1; }
echo "GUEST CAPTURE OK: $SHOT2"
grep -a -i "error" "$WORK/client1.log" | grep -v "0 error" | head -5 || true
