#!/usr/bin/env bash
# Empire Age 17f — SOCIAL end-to-end smoke test.
#
# Real Go server (seeded store) + three headless Godot
# clients (--mp-social driver), then a fourth relogging as A:
#   A  — posts on its wall with a gallery image (feed source),
#        creates the open alliance "Hội Xã Hội", posts in it,
#        uploads a custom avatar through the settings import
#        pipeline (fixture file: the sandbox cannot drive the
#        OS file picker).
#   B  — A's friend: the post lands in B's feed, B's like
#        lands, B joins the alliance and sees its post, and
#        A's custom avatar resolves in B's friend rows.
#   C  — a stranger: feed stays clean, alliance posts empty.
#   A2 — fresh process: A's wall (the Album source) persisted.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-social-smoke.XXXXXX)
echo "social smoke workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }

python3 - "$WORK/store.json" <<'EOF'
import hashlib, json, sys, time
def pw(password, salt_hex):
    return hashlib.pbkdf2_hmac("sha256", password.encode(),
                               bytes.fromhex(salt_hex), 120000).hex()
salt = "00112233445566778899aabbccddeeff"
now = int(time.time())
def acct(user, friends):
    return {"user": user, "salt": salt, "hash": pw("secret1", salt),
            "created": now - 90000, "display_name": user,
            "wins": 3, "losses": 2, "matches": 5, "mmr": 1000,
            "last_played": now - 3600, "friends": friends,
            "rank": {"tier": 0, "division": 2, "stars": 0, "streak": 0,
                     "season": 1, "peak_tier": 0, "peak_division": 2}}
json.dump({"accounts": {
    "SocA": acct("SocA", ["SocB"]),
    "SocB": acct("SocB", ["SocA"]),
    "SocC": acct("SocC", []),
}}, open(sys.argv[1], "w"))
print("seeded SocA / SocB (friends) / SocC (stranger)")
EOF

"$WORK/relay" -addr "$ADDR" -store "$WORK/store.json" \
	> "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR"

fail=0
chk() { # chk <logfile> <pattern> <label>
	if grep -q "$2" "$1" 2>/dev/null; then
		echo "ok: $3"
	else
		echo "FAIL: $3 (missing '$2' in $1)"; fail=1
	fi
}

CLIENT_PIDS=""
run_client() { # run_client <logname> <account> <role>
	timeout 200 "$GODOT" --headless --fixed-fps 30 --path . -- \
		--mp-account=$2:secret1 --mp-nokill --mp-social=$3 \
		> "$WORK/$1.log" 2>&1 &
	CLIENT_PIDS="$CLIENT_PIDS $!"
}

run_client a SocA a
run_client b SocB b
run_client c SocC c
wait $CLIENT_PIDS

timeout 90 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-account=SocA:secret1 --mp-nokill --mp-social=a2 \
	> "$WORK/a2.log" 2>&1

chk "$WORK/a.log" "MPLOG social a post sent" "A posts on its wall"
chk "$WORK/a.log" "MPLOG social a wall ok" "A's wall returns the post"
chk "$WORK/a.log" "MPLOG social a ally post sent" "A posts in the alliance"
chk "$WORK/a.log" "MPLOG social a ally wall ok" "alliance posts return A's post"
chk "$WORK/a.log" "MPLOG social a avatar custom ok" "A's custom avatar equipped via import pipeline"
chk "$WORK/b.log" "MPLOG social b feed ok" "A's post appears in friend B's feed"
chk "$WORK/b.log" "MPLOG social b like ok" "B's like lands on A's post"
chk "$WORK/b.log" "MPLOG social b ally ok" "alliance post visible to member B"
chk "$WORK/b.log" "MPLOG social b sees custom avatar" "B resolves A's custom avatar in friend rows"
chk "$WORK/c.log" "MPLOG social c feed clean" "stranger C's feed has none of A's posts"
chk "$WORK/c.log" "MPLOG social c ally empty" "outsider C sees no alliance posts"
chk "$WORK/a2.log" "MPLOG social a2 album source ok" "A's wall + image persisted across relog (album source)"

kill $SRV 2>/dev/null
if [ $fail -eq 0 ]; then
	echo "SOCIAL SMOKE: ALL PASS"
else
	echo "SOCIAL SMOKE: FAILURES — see $WORK/*.log"
	for f in a b c a2; do echo "--- $f (tail)"; grep "social" "$WORK/$f.log" 2>/dev/null | tail -6; done
	exit 1
fi
