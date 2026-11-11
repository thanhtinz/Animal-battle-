#!/usr/bin/env bash
# Capture harness for the ping-meter correction (Tín:
# the dot is the WiFi fan's BASE point below the arcs —
# bad = red dot + grey arcs, medium = yellow dot + grey
# arcs, good = the WHOLE glyph green; no dot above):
#   1. empire_age_home_ping_v2_medium.png (member on the
#      local relay, live 100–200 ms sample -> band 1,
#      yellow base dot + grey arcs)
#   2. empire_age_home_ping_v2_good.png   (only if a real
#      sub-100 ms sample occurs; sandbox floor ~110 ms,
#      so usually proven by the bands sheet instead)
#   3. empire_age_home_ping_v2_bad.png    (offline boot ->
#      band 0, red base dot + grey arcs, "—" text)
#   4. empire_age_home_ping_v2_bands.png  (GlassIcon sheet:
#      bands 0/1/2 big — band 2 = whole glyph green)
#   5. empire_age_home_ping_v2_zoom.png   (4x crop of the
#      bad shot's top-right corner) + _zoom_medium.png
# Seed mirrors capture_ping.sh (same ladder accounts).
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

SHOT_MED="$ROOT/shots/empire_age_home_ping_v2_medium.png"
PING_TARGET=medium PING_OUT="res://shots/empire_age_home_ping_v2_medium.png" \
  PING_TIMEOUT=40 run_client client_med.log res://tests/capture_home_ping_band.tscn
grep -a "medium ms=" "$WORK/client_med.log" > /dev/null \
  || { echo "MEDIUM BAND NOT REACHED:"; grep -a "CAPTURE SAVED" "$WORK/client_med.log"; \
       tail -5 "$WORK/client_med.log"; exit 1; }
grep -a "CAPTURE SAVED" "$WORK/client_med.log"
echo "MEDIUM CAPTURE OK: $SHOT_MED"

# Good band: a genuine sub-100 ms sample may never occur
# in this sandbox (localhost floor ~110 ms) — try for
# 60 s, keep the shot only if the band was truly hit;
# the all-green drawing is proven by the bands sheet.
SHOT_GOOD="$ROOT/shots/empire_age_home_ping_v2_good.png"
PING_TARGET=good PING_OUT="res://shots/empire_age_home_ping_v2_good.png" \
  PING_TIMEOUT=25 run_client client_good.log res://tests/capture_home_ping_band.tscn
if grep -a "good ms=" "$WORK/client_good.log" > /dev/null; then
  grep -a "CAPTURE SAVED" "$WORK/client_good.log"
  echo "GOOD CAPTURE OK: $SHOT_GOOD"
else
  grep -a "CAPTURE SAVED" "$WORK/client_good.log" || true
  echo "GOOD BAND NOT REACHED IN SANDBOX (see bands sheet) — removing shot"
  rm -f "$SHOT_GOOD"
fi

kill "$SRV_PID" 2>/dev/null; SRV_PID=""
sleep 0.5

run_client client_bands.log res://tests/capture_ping_bands.tscn
grep -a "CAPTURE SAVED" "$WORK/client_bands.log" > /dev/null \
  || { echo "NO BANDS SHEET"; tail -20 "$WORK/client_bands.log"; exit 1; }
echo "BANDS SHEET OK"

SHOT_BAD="$ROOT/shots/empire_age_home_ping_v2_bad.png"
run_client client_bad.log res://tests/capture_home_ping_bad.tscn
grep -a "CAPTURE SAVED" "$WORK/client_bad.log" > /dev/null \
  || { echo "NO BAD SHOT"; tail -20 "$WORK/client_bad.log"; exit 1; }
echo "BAD CAPTURE OK: $SHOT_BAD"

python3 - "$SHOT_BAD" "$ROOT/shots/empire_age_home_ping_v2_zoom.png" \
  "$SHOT_MED" "$ROOT/shots/empire_age_home_ping_v2_zoom_medium.png" <<'EOF'
import sys
from PIL import Image
bad = Image.open(sys.argv[1])
bad.crop((1020, 0, 1280, 80)).resize((1040, 320), Image.NEAREST).save(sys.argv[2])
print("zoom saved", sys.argv[2])
med = Image.open(sys.argv[3])
med.crop((1020, 0, 1280, 80)).resize((1040, 320), Image.NEAREST).save(sys.argv[4])
print("zoom saved", sys.argv[4])
EOF
echo "ALL DONE"
