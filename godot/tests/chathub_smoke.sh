#!/usr/bin/env bash
# Empire Age 17e — CHAT HUB end-to-end smoke test.
#
# Real Go server (EMPIRE_AGE_ADMINS=HubAdmin; seeded store)
# + three headless Godot clients (--mp-chathub driver), then
# a fourth process relogging as A:
#   A     — world-sends with an emoticon token; receives B's
#           world reply, B's DM, B's voice note and B's
#           megaphone marquee; its own non-admin grant
#           attempt is refused.
#   B     — answers on world, DMs A, sends a SYNTHETIC voice
#           note (no mic in the sandbox — injected through
#           the recorder's output shape), is refused a
#           megaphone at 0, receives the admin grant (x2),
#           broadcasts a marquee, and lands at count 1.
#   Admin — grants HubB two megaphones (the only issuance
#           path; delivery letter + system note server-side).
#   A2    — fresh process: the DM history persisted
#           server-side across the relog.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-chathub-smoke.XXXXXX)
echo "chathub smoke workdir: $WORK"

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
    "HubA": acct("HubA", ["HubB"]),
    "HubB": acct("HubB", ["HubA"]),
    "HubAdmin": acct("HubAdmin", []),
}}, open(sys.argv[1], "w"))
print("seeded HubA / HubB (friends) / HubAdmin")
EOF

EMPIRE_AGE_ADMINS=HubAdmin "$WORK/relay" -addr "$ADDR" -store "$WORK/store.json" \
	> "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR (admin: HubAdmin)"

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
	timeout 170 "$GODOT" --headless --fixed-fps 30 --path . -- \
		--mp-account=$2:secret1 --mp-nokill --mp-chathub=$3 \
		> "$WORK/$1.log" 2>&1 &
	CLIENT_PIDS="$CLIENT_PIDS $!"
}

run_client a HubA a
run_client b HubB b
run_client admin HubAdmin admin
# Wait for the CLIENTS only — a bare `wait` would also block
# on the relay server job, which never exits.
wait $CLIENT_PIDS

# Relog phase: A returns in a fresh process; the DM from B
# must be in the server-stored thread history.
timeout 90 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-account=HubA:secret1 --mp-nokill --mp-chathub=a2 \
	> "$WORK/a2.log" 2>&1

chk "$WORK/a.log" "MPLOG chathub a world sent" "A sends on the world channel"
chk "$WORK/b.log" "MPLOG chathub b got world from a emote=true" "B receives A's world line with the emoticon token intact"
chk "$WORK/a.log" "MPLOG chathub a got world from b" "A receives B's world reply"
chk "$WORK/b.log" "MPLOG chathub b dm sent" "B sends a DM"
chk "$WORK/a.log" "MPLOG chathub a got dm from b" "A receives B's DM live"
chk "$WORK/b.log" "MPLOG chathub b voice sent" "B sends a synthetic voice note"
chk "$WORK/a.log" "MPLOG chathub a got voice world from b" "A receives B's voice note on the world channel"
chk "$WORK/b.log" "MPLOG chathub b megaphone refused" "empty megaphone use is refused"
chk "$WORK/admin.log" "MPLOG chathub admin grant sent" "admin issues the grant"
chk "$WORK/admin.log" "MPLOG megaphone granted user=HubB total=2" "grant lands on HubB (total 2)"
chk "$WORK/b.log" "MPLOG chathub b megaphones n=2" "B sees the granted count"
chk "$WORK/b.log" "MPLOG chathub b megaphone used" "B spends one megaphone"
chk "$WORK/a.log" "MPLOG chathub a got marquee" "bystander A receives the scrolling marquee"
chk "$WORK/b.log" "MPLOG chathub b megaphone left count=1" "the spend decremented B to 1"
chk "$WORK/a.log" "MPLOG chathub a grant refused" "non-admin grant attempt is refused"
chk "$WORK/a2.log" "MPLOG chathub a2 dm history ok" "DM history persisted across relog"

kill $SRV 2>/dev/null
if [ $fail -eq 0 ]; then
	echo "CHATHUB SMOKE: ALL PASS"
else
	echo "CHATHUB SMOKE: FAILURES — see $WORK/*.log"
	for f in a b admin a2; do echo "--- $f (tail)"; grep "chathub\|marquee\|megaphone" "$WORK/$f.log" 2>/dev/null | tail -8; done
	exit 1
fi
