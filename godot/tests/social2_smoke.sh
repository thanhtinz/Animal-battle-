#!/usr/bin/env bash
# Empire Age 17g — SOCIAL-2 end-to-end smoke test.
#
# Real Go server (seeded store) + three headless Godot
# clients (--mp-social2 driver):
#   X (SocA) — posts "Bài 17g của A" on its wall, comments
#              on it, shares it to its own wall.
#   Y (SocB) — A's friend: the post lands in Y's feed, Y
#              reports it (reported_by_me comes back), Y
#              comments, then replies to A's own comment
#              (the reply lands under the thread root).
#   Z (SocC) — a stranger: the 17g post never reaches Z.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-social2-smoke.XXXXXX)
echo "social2 smoke workdir: $WORK"

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
		--mp-account=$2:secret1 --mp-nokill --mp-social2=$3 \
		> "$WORK/$1.log" 2>&1 &
	CLIENT_PIDS="$CLIENT_PIDS $!"
}

run_client x SocA x
run_client y SocB y
run_client z SocC z
wait $CLIENT_PIDS

chk "$WORK/x.log" "MPLOG social2 x comment ok" "A comments on its own post"
chk "$WORK/x.log" "MPLOG social2 x image-comment ok" "A's image-only comment lands with its photo"
chk "$WORK/x.log" "MPLOG social2 x share ok" "A shares its post to its wall"
chk "$WORK/y.log" "MPLOG social2 y report ok" "B reports A's post (reported_by_me)"
chk "$WORK/y.log" "MPLOG social2 y comment ok" "B comments on A's post"
chk "$WORK/y.log" "MPLOG social2 y reply ok" "B's reply lands under the thread"
chk "$WORK/z.log" "MPLOG social2 z clean ok" "stranger Z never sees the 17g post"

kill $SRV 2>/dev/null
if [ $fail -eq 0 ]; then
	echo "SOCIAL2 SMOKE: ALL PASS"
else
	echo "SOCIAL2 SMOKE: FAILURES — see $WORK/*.log"
	for f in x y z; do echo "--- $f (tail)"; grep "social2" "$WORK/$f.log" 2>/dev/null | tail -6; done
	exit 1
fi
