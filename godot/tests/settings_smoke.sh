#!/usr/bin/env bash
# Empire Age 17d — PROFILE SETTINGS end-to-end smoke test.
#
# Real Go server (seeded store) + one headless Godot client
# (--mp-settings driver):
#   - the seeded account SetUser (display name TenCu17d,
#     granted frame_01 in the seed — items are grant-only) renames to
#     TenMoi17d (must succeed);
#   - a second rename immediately after must be BLOCKED by
#     the 30-day cooldown, carrying a future next date;
#   - avatar art:05 equips; frame_01 equips; the UNOWNED
#     frame_06 equip is rejected server-side;
#   - bubble style mac_dinh equips.
# The store is seeded directly (PBKDF2, the capture harness
# pattern) so the account starts WITH a display name — a
# rename, not a first set.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-settings-smoke.XXXXXX)
echo "settings smoke workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }

python3 - "$WORK/store.json" <<'EOF'
import hashlib, json, sys, time
def pw(password, salt_hex):
    return hashlib.pbkdf2_hmac("sha256", password.encode(),
                               bytes.fromhex(salt_hex), 120000).hex()
salt = "00112233445566778899aabbccddeeff"
now = int(time.time())
acct = {"user": "SetUser", "salt": salt, "hash": pw("secret1", salt),
        "created": now - 90000, "display_name": "TenCu17d",
        "wins": 0, "losses": 200, "matches": 200, "mmr": 1000,
        "last_played": now - 3600,
        "granted_frames": ["frame_01"],
        "rank": {"tier": 0, "division": 2, "stars": 0, "streak": 0,
                 "season": 1, "peak_tier": 0, "peak_division": 2}}
json.dump({"accounts": {"SetUser": acct}}, open(sys.argv[1], "w"))
print("seeded SetUser (granted frame_01)")
EOF

"$WORK/relay" -addr "$ADDR" -store "$WORK/store.json" \
	> "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR"

fail=0
chk() { # chk <pattern> <label>
	if grep -q "$1" "$WORK/client.log" 2>/dev/null; then
		echo "ok: $2"
	else
		echo "FAIL: $2 (missing '$1')"; fail=1
	fi
}

timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-account=SetUser:secret1 --mp-nokill --mp-settings=run \
	> "$WORK/client.log" 2>&1

chk "MPLOG settings rename ok name=TenMoi17d" "rename succeeds"
chk "MPLOG settings rename blocked next_valid=true" "cooldown blocks second rename with a future date"
chk "MPLOG settings avatar ok id=art:05" "avatar equip lands"
chk "MPLOG settings frame ok id=frame_01" "owned frame equips"
chk "MPLOG settings unowned frame rejected" "unowned frame rejected server-side"
chk "MPLOG settings bubble ok id=mac_dinh" "bubble equip lands"
chk "MPLOG settings done" "driver completed"

kill $SRV 2>/dev/null
if [ $fail -eq 0 ]; then
	echo "SETTINGS SMOKE: ALL PASS"
else
	echo "SETTINGS SMOKE: FAILURES — see $WORK/client.log"
	tail -30 "$WORK/client.log"
	exit 1
fi
