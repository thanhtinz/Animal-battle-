#!/usr/bin/env bash
# History-panel screenshot harness (13g): seeds a FileStore whose
# viewer "HiepSi" has five ranked results banked (mixed win/loss,
# maps + durations + star deltas, spread over the last days) and
# a device-local match log with three custom results, then
# photographs the reference-styled Lịch Sử Trận panel at 1280x720
# (page 1 of 2 at 5 rows/page).
set -u
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
GO="${GO:-$HOME/workspace/tools/goroot/bin/go}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$(cd "$ROOT/../server" && pwd)"
WORK="$(mktemp -d)"
SHOT="$ROOT/shots/empire_age_history_v1.png"
USERDIR="$HOME/.local/share/godot/app_userdata/Empire Age"
mkdir -p "$ROOT/shots" "$USERDIR"
SRV_PID=""
cleanup() {
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
  rm -f "$USERDIR/match_log.json"
  rm -rf "$WORK"
}
trap cleanup EXIT

python3 - "$WORK/store.json" "$USERDIR/match_log.json" <<'EOF'
import hashlib, json, sys, time
def pw(password, salt_hex):
    return hashlib.pbkdf2_hmac("sha256", password.encode(),
                               bytes.fromhex(salt_hex), 120000).hex()
salt = "00112233445566778899aabbccddeeff"
now = int(time.time())
EPOCH = now - 91 * 86400
def acc(user, tier, div, stars, mmr, wins, losses, extra=None):
    a = {"user": user, "salt": salt, "hash": pw("secret1", salt),
         "created": now - 90000, "wins": wins, "losses": losses,
         "matches": wins + losses, "mmr": mmr,
         "rank": {"tier": tier, "division": div, "stars": stars,
                  "season": 2, "peak_tier": tier, "peak_division": div}}
    if extra:
        a.update(extra)
    return a
def rec(opp, won, rf, rt, sd, mb, ma, at, biome, layout, ticks):
    return {"opponent": opp, "won": won, "rank_from": rf, "rank_to": rt,
            "star_delta": sd, "mmr_before": mb, "mmr_after": ma, "at": at,
            "biome": biome, "layout": layout, "duration_ticks": ticks}
hist = [  # oldest first (server appends chronologically)
  rec("BaTuoc1", False, "Kỵ Sĩ III · 2 sao", "Kỵ Sĩ III · 1 sao", -1,
      1180, 1168, now - 3 * 86400, "snow", "valley", 6100),
  rec("NamTuoc1", True, "Kỵ Sĩ III · 1 sao", "Kỵ Sĩ III · 2 sao", 1,
      1168, 1184, now - 26 * 3600, "grassland", "lakes", 7300),
  rec("BaTuoc1", True, "Kỵ Sĩ III · 2 sao", "Kỵ Sĩ II · 0 sao", 1,
      1184, 1201, now - 5 * 3600, "desert", "coast", 5400),
  rec("NamTuoc1", True, "Kỵ Sĩ II · 0 sao", "Kỵ Sĩ II · 2 sao", 2,
      1201, 1224, now - 2 * 3600, "grassland", "plains", 8900),
  rec("CongTuoc1", True, "Kỵ Sĩ II · 2 sao", "Kỵ Sĩ II · 2 sao", 0,
      1224, 1240, now - 12 * 60, "grassland", "hills", 4800),
]
hiepsi = acc("HiepSi", 2, 1, 2, 1240, 7, 3, {"match_history": hist})
store = {"accounts": {
    "HoangDe1": acc("HoangDe1", 6, 0, 27, 2560, 40, 5),
    "CongTuoc1": acc("CongTuoc1", 6, 0, 12, 1980, 30, 9),
    "HauTuoc1": acc("HauTuoc1", 5, 0, 7, 1710, 22, 11),
    "BaTuoc1": acc("BaTuoc1", 4, 1, 1, 1490, 15, 10),
    "NamTuoc1": acc("NamTuoc1", 3, 2, 0, 1330, 11, 9),
    "HiepSi": hiepsi},
  "meta": {"season_epoch": str(EPOCH)}}
json.dump(store, open(sys.argv[1], "w"))
# Device-local custom log (newest first).
log = [
  {"mode": "custom", "won": False, "biome": "desert", "layout": "coast",
   "players": [{"name": "HiepSi", "team": 0}, {"name": "CongTuoc1", "team": 1},
               {"name": "NamTuoc1", "team": 0}, {"name": "BaTuoc1", "team": 1}],
   "at": now - 48 * 60, "duration_ticks": 6600, "room": "AB3DE"},
  {"mode": "custom", "won": True, "biome": "grassland", "layout": "lakes",
   "players": [{"name": "HiepSi", "team": 0}, {"name": "Đối thủ máy", "team": 1}],
   "at": now - 7 * 3600, "duration_ticks": 9200, "room": ""},
  {"mode": "custom", "won": True, "biome": "snow", "layout": "plains",
   "players": [{"name": "HiepSi", "team": 0}, {"name": "NamTuoc1", "team": 1}],
   "at": now - 2 * 86400, "duration_ticks": 5100, "room": "XY9ZZ"},
]
json.dump(log, open(sys.argv[2], "w"))
EOF

(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || { echo "BUILD FAIL"; exit 1; }
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1

timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" \
  "$GODOT" --path "$ROOT" --resolution 1280x720 \
  -- --mp-shot-history="$SHOT" --mp-account=HiepSi:secret1 \
  > "$WORK/client.log" 2>&1
grep -a "history shot saved" "$WORK/client.log" > /dev/null \
  || { echo "NO SHOT"; tail -20 "$WORK/client.log"; exit 1; }
[ -f "$SHOT" ] || { echo "SHOT FILE MISSING"; exit 1; }
python3 -c "
from PIL import Image
im = Image.open('$SHOT')
print('shot size:', im.size)
assert im.size == (1280, 720), 'unexpected size'
" 2>/dev/null || file "$SHOT"
echo "HISTORY CAPTURE OK: $SHOT"
