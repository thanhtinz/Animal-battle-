#!/usr/bin/env bash
# Empire Age P4 stage-4 capture harness (NOT part of ranked_smoke.sh).
#
# Produces shots/empire_age_rank_lobby_v1.png: the ranked
# leaderboard open in the lobby, headed by the viewer's own rank
# badge (Kỵ Sĩ II · 2 sao, peak Bá Tước II, previous season
# archived), over five SEEDED accounts at varied ladder positions
# (Tân Binh / Chiến Binh / Kỵ Sĩ / Bá Tước / Công Tước flagged
# Hoàng Đế as the server's only duke).
#
# The store is seeded by writing the FileStore JSON directly
# (PBKDF2-HMAC-SHA256, 120k rounds — same KDF the server uses),
# with the season epoch 91 days back so the seeded ladder state
# sits in season 2 and no reset fires.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-ranklb-capture.XXXXXX)
SHOTS="$PWD/shots"
mkdir -p "$SHOTS"
echo "capture workdir: $WORK"

python3 - "$WORK/accounts.json" <<'PYEOF'
import hashlib, json, os, sys, time

def acct(user, rank, wins, losses, mmr, history=None):
    salt = os.urandom(16)
    key = hashlib.pbkdf2_hmac("sha256", b"secret1", salt, 120000, dklen=32)
    a = {
        "user": user, "salt": salt.hex(), "hash": key.hex(),
        "wins": wins, "losses": losses, "matches": wins + losses,
        "mmr": mmr, "last_played": int(time.time()), "created": int(time.time()),
        "rank": rank,
    }
    if history:
        a["history"] = history
    return a

def rk(tier, div, stars, streak, peak_tier, peak_div):
    return {"tier": tier, "division": div, "stars": stars, "streak": streak,
            "season": 2, "peak_tier": peak_tier, "peak_division": peak_div}

accounts = {}
accounts["CongTuocX"] = acct("CongTuocX", rk(6, 0, 27, 4, 6, 0), 40, 18, 2130)
accounts["BaTuocX"] = acct("BaTuocX", rk(4, 0, 3, 0, 4, 2), 25, 20, 1560)
accounts["HiepSi"] = acct("HiepSi", rk(2, 1, 2, 2, 4, 1), 18, 15, 1240,
    history=[{"season": 1, "final_tier": 5, "final_division": 2,
              "final_stars": 3, "peak_tier": 5, "peak_division": 2}])
accounts["ChienSi"] = acct("ChienSi", rk(1, 2, 2, 0, 1, 2), 9, 11, 980)
accounts["SiLe"] = acct("SiLe", rk(0, 0, 1, 1, 0, 1), 3, 7, 905)

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

timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path . --resolution 1152x768 -- \
	--mp-shot-ranklb="$SHOTS/empire_age_rank_lobby_v1.png" \
	--mp-account=HiepSi:secret1 > "$WORK/shot.log" 2>&1
kill $SRV 2>/dev/null
grep -q "MPLOG ranklb shot saved" "$WORK/shot.log" \
	&& echo "rank lobby shot saved" || echo "WARN: shot may be missing (see $WORK/shot.log)"
ls -la "$SHOTS/empire_age_rank_lobby_v1.png" 2>/dev/null
echo "logs: $WORK"
