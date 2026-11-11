#!/usr/bin/env bash
# Leaderboard v3 screenshot harness (rank emblem textures) (13g addendum): seeds seven
# accounts on a strict ladder and photographs the restyled board
# (Toàn server tab) at 1280x720 with the viewer "HiepSi" at
# position 7 — outside the top 5 — so the sticky footer proves a
# real full-ladder position.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-lb2-capture.XXXXXX)
SHOTS="$PWD/shots"
mkdir -p "$SHOTS"
SHOT="$SHOTS/empire_age_leaderboard_v3.png"

python3 - "$WORK/accounts.json" <<'PYEOF'
import hashlib, json, os, sys, time

def acct(user, rank, wins, losses, mmr):
    salt = os.urandom(16)
    key = hashlib.pbkdf2_hmac("sha256", b"secret1", salt, 120000, dklen=32)
    return {"user": user, "salt": salt.hex(), "hash": key.hex(),
            "wins": wins, "losses": losses, "matches": wins + losses,
            "mmr": mmr, "last_played": int(time.time()),
            "created": int(time.time()), "rank": rank}

def rk(tier, div, stars, peak_tier, peak_div):
    return {"tier": tier, "division": div, "stars": stars, "streak": 0,
            "season": 2, "peak_tier": peak_tier, "peak_division": peak_div}

accounts = {}
accounts["CongTuocX"] = acct("CongTuocX", rk(6, 0, 27, 6, 0), 40, 18, 2130)  # 1 Hoàng Đế
accounts["HauTuocX"] = acct("HauTuocX", rk(5, 2, 4, 5, 2), 31, 14, 1710)     # 2 Hầu Tước I
accounts["BaTuocX"] = acct("BaTuocX", rk(4, 0, 3, 4, 2), 25, 20, 1560)       # 3 Bá Tước III
accounts["NamTuocX"] = acct("NamTuocX", rk(3, 2, 1, 3, 2), 19, 12, 1420)      # 4 Nam Tước I
accounts["KySiMot"] = acct("KySiMot", rk(2, 2, 1, 2, 2), 16, 13, 1330)       # 5 Kỵ Sĩ I
accounts["KySiHai"] = acct("KySiHai", rk(2, 1, 3, 2, 1), 15, 14, 1290)       # 6 Kỵ Sĩ II · 3 sao
accounts["HiepSi"] = acct("HiepSi", rk(2, 1, 2, 4, 1), 18, 15, 1240)         # 7 viewer

store = {"accounts": accounts, "tokens": {},
         "meta": {"season_epoch": str(int(time.time()) - 91 * 24 * 3600)}}
with open(sys.argv[1], "w") as f:
    json.dump(store, f)
print("seeded", len(accounts), "accounts")
PYEOF

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" -store "$WORK/accounts.json" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }

timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path . --resolution 1280x720 -- \
	--mp-shot-ranklb="$SHOT" \
	--mp-account=HiepSi:secret1 > "$WORK/shot.log" 2>&1
kill $SRV 2>/dev/null
grep -q "MPLOG ranklb shot saved" "$WORK/shot.log" \
	&& echo "lb2 shot saved" || { echo "FAIL: no shot"; tail -20 "$WORK/shot.log"; exit 1; }
python3 -c "
from PIL import Image
im = Image.open('$SHOT')
print('shot size:', im.size)
assert im.size == (1280, 720), 'unexpected size'
"
echo "LB2 CAPTURE OK: $SHOT"
