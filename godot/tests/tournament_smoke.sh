#!/usr/bin/env bash
# Empire Age 15h — TOURNAMENT end-to-end smoke test.
#
# Real Go server (referee orchestration on) + FOUR logged-in
# headless Godot clients running the --mp-tourn driver:
#
#   TournA creates a solo single-elim "Smoke Cup" (4 entries)
#   -> TournB/C/D join by id -> all four register -> TournA
#   opens check-in -> both semifinals + the final play as
#   dedicated referee rooms (--referee-test-kills=120:1 fells
#   slot 1 in the REFEREE's sim only; the referee's result is
#   canonical — a client whose sim resyncs from the referee
#   ends its match locally, the others leave once the server
#   shows the match banked — so side A = slot 0 wins every
#   match). Joiners launch SEQUENTIALLY (each waits for the
#   previous one's registration) so seeds are deterministic:
#   registration order A,B,C,D -> SF1 = 1v4 (A v D),
#   SF2 = 2v3 (B v C); slot 0 is side A in both -> winners
#   A and B; final A v B with slot 0 = A -> champion TournA,
#   runner-up TournB.
#
# Asserts: every client agrees on the finished bracket
# (champion=TournA from the same detail payload), the server
# banked all three match results through the referee path,
# the champion's account carries the tournament history +
# "Vô địch giải đấu" title with W/L banked per played match
# and NO ladder movement (MMR/stars untouched), and no
# resync failure occurred.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-tourn-smoke.XXXXXX)
echo "tournament smoke workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" -store "$WORK/accounts.json" \
	-referee-godot "$GODOT" -referee-project "$PWD" \
	-referee-extra-args "--referee-test-kills=120:1" \
	> "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR (referee orchestration on)"

PIDS=""
launch() { # launch <logname> <user> <role-args...>
	local log=$1 user=$2; shift 2
	timeout 900 "$GODOT" --headless --fixed-fps 30 --path . -- \
		--mp-account=$user:secret1 --mp-nokill --mp-hold=100000 "$@" \
		> "$WORK/$log.log" 2>&1 &
	PIDS="$PIDS $!"
}

launch tourna TournA --mp-tourn=create --mp-tourn-name="Smoke Cup"
# Wait for the creator to learn + print its tournament id.
TID=""
for _ in $(seq 1 60); do
	TID=$(grep -o "MPLOG tourn id=T[A-Z0-9]*" "$WORK/tourna.log" 2>/dev/null | head -1 | cut -d= -f2)
	[ -n "$TID" ] && break
	sleep 1
done
if [ -z "$TID" ]; then
	echo "FAIL: creator never printed a tournament id (see $WORK/tourna.log)"
	kill $SRV 2>/dev/null; exit 1
fi
echo "tournament id: $TID"
launch_joiner() { # launch_joiner <logname> <user> — sequential for seed order
	launch "$1" "$2" --mp-tourn=join --mp-tourn-id=$TID
	for _ in $(seq 1 90); do
		grep -q "MPLOG tourn registering user=$2" "$WORK/$1.log" 2>/dev/null && break
		sleep 1
	done
	sleep 2 # let the server record this seed before the next joiner
}
launch_joiner tournb TournB
launch_joiner tournc TournC
launch_joiner tournd TournD
for p in $PIDS; do wait $p; done
kill $SRV 2>/dev/null

fail=0
chk() { # chk <label> <ok:0/1>
	if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

grep -q "tournament $TID: match 1 room" "$WORK/server.log"; chk "server created a dedicated room for match 1" $?
WINS=$(grep -c "tournament $TID: match .* -> entry .* wins" "$WORK/server.log")
[ "$WINS" -eq 3 ]; chk "server banked 3 match results via the referee path (got $WINS)" $?
for f in tourna tournb tournc tournd; do
	grep -q "MPLOG tourn finished champion=TournA" "$WORK/$f.log"
	chk "client $f agrees: champion=TournA" $?
	grep -q "MPLOG resync failed" "$WORK/$f.log" && rc=1 || rc=0
	chk "client $f: no resync failure" $rc
done
grep -q "MPLOG tourn finished champion=TournA runner=TournB" "$WORK/tourna.log"
chk "runner-up is TournB (seed 2)" $?

# Account-side rewards, read straight from the store file.
python3 - "$WORK/accounts.json" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
acc = data["accounts"]
a, b = acc["TournA"], acc["TournB"]
ok = True
def need(cond, msg):
    global ok
    print(("PASS: " if cond else "FAIL: ") + msg)
    ok = ok and cond
hist = a.get("tournament_history", [])
need(len(hist) == 1 and hist[0]["place"] == "champion",
     "champion history recorded exactly once on TournA")
need("Vô địch giải đấu" in a.get("titles", []),
     "champion title on TournA's profile data")
need(a["wins"] == 2 and a["matches"] == 2,
     "TournA W/L banked per played match (2W/2M)")
need(a.get("mmr", 0) == 0 and a.get("season_stars", 0) == 0,
     "no ladder impact on TournA (MMR/stars untouched)")
histb = b.get("tournament_history", [])
need(len(histb) == 1 and histb[0]["place"] == "runner_up",
     "runner-up history recorded on TournB")
sys.exit(0 if ok else 1)
EOF
chk "account rewards in the store file" $?

echo "logs: $WORK/"
if [ $fail -eq 0 ]; then
	echo "TOURNAMENT SMOKE: ALL PASS"
else
	echo "TOURNAMENT SMOKE: FAILURES"
fi
exit $fail
