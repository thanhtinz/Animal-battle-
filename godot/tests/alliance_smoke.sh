#!/usr/bin/env bash
# Empire Age 17a — ALLIANCE end-to-end smoke test.
#
# Real Go server + THREE logged-in headless Godot clients
# running the --mp-alliance driver:
#
#   AllyLead (--mp-alliance=create) founds the request-mode
#     alliance "Hội Khói Lam" and approves the applicant;
#   AllyMem  (--mp-alliance=apply) finds it in the browser,
#     applies, joins on approval, receives the leader's
#     alliance chat, then leaves;
#   AllyOut  (--mp-alliance=outside) never joins anything and
#     must receive NO alliance chat (member-only fan-out).
#
# Asserts (from the clients' MPLOG lines): creation, request +
# approval, roles visible on both sides, chat delivered to the
# member (and echoed to the leader), chat NOT delivered to the
# outsider, and the member's clean leave shrinking the roster
# back to the leader alone.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-alliance-smoke.XXXXXX)
echo "alliance smoke workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" -store "$WORK/accounts.json" \
	> "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
echo "server up on $ADDR"

PIDS=""
launch() { # launch <logname> <user> <role-args...>
	local log=$1 user=$2; shift 2
	timeout 300 "$GODOT" --headless --fixed-fps 30 --path . -- \
		--mp-account=$user:secret1 --mp-nokill --mp-hold=100000 "$@" \
		> "$WORK/$log.log" 2>&1 &
	PIDS="$PIDS $!"
}

# The outsider connects FIRST so it is provably online (and
# registered for lobby fan-out) before any chat is sent.
launch out AllyOut --mp-alliance=outside
launch lead AllyLead --mp-alliance=create --mp-alliance-name="Hội Khói Lam"
# The member starts once the alliance exists server-side.
for _ in $(seq 1 90); do
	grep -q "MPLOG alliance created id=" "$WORK/lead.log" 2>/dev/null && break
	sleep 1
done
grep -q "MPLOG alliance created id=" "$WORK/lead.log" || {
	echo "FAIL: leader never created the alliance (see $WORK/lead.log)"
	kill $SRV 2>/dev/null; exit 1; }
launch mem AllyMem --mp-alliance=apply --mp-alliance-name="Hội Khói Lam"
for p in $PIDS; do wait $p; done
kill $SRV 2>/dev/null

fail=0
chk() { # chk <logfile> <pattern> <label>
	if grep -q "$2" "$WORK/$1.log"; then
		echo "ok: $3"
	else
		echo "FAIL: $3 (missing '$2' in $1.log)"; fail=1
	fi
}
chk lead "MPLOG alliance created id=A" "leader created the alliance"
chk lead "MPLOG alliance approving user=AllyMem" "leader approved the request"
chk lead "MPLOG alliance member user=AllyLead role=leader" "leader sees own leader role"
chk lead "MPLOG alliance member user=AllyMem role=member" "leader sees member role"
chk lead "MPLOG alliance chat sent" "leader sent alliance chat"
chk lead "MPLOG alliance flow done" "leader flow completed (member left)"
chk mem "MPLOG alliance found id=A" "member found the alliance in the browser"
chk mem "MPLOG alliance joined role=member" "member joined as member"
chk mem "MPLOG alliance chat from=AllyLead text=Xin chào liên minh 17a" "member received alliance chat"
chk mem "MPLOG alliance flow done" "member flow completed (left)"
chk out "MPLOG alliance outsider clean mine=0 chats=0" "outsider stayed unaffiliated, no chat"
if grep -q "MPLOG alliance chat from" "$WORK/out.log"; then
	echo "FAIL: outsider received alliance chat (member-only violated)"; fail=1
else
	echo "ok: outsider received no alliance chat"
fi
for f in lead mem out; do
	if grep -q "SCRIPT ERROR" "$WORK/$f.log"; then
		echo "FAIL: script error in $f.log"; grep "SCRIPT ERROR" "$WORK/$f.log" | head -3; fail=1
	fi
	if grep -q "MPLOG alliance TIMEOUT" "$WORK/$f.log"; then
		echo "FAIL: alliance driver timeout in $f.log"; fail=1
	fi
done
if [ $fail -eq 0 ]; then
	echo "ALLIANCE SMOKE: ALL PASS"
else
	echo "ALLIANCE SMOKE: FAILURES (logs in $WORK)"
	exit 1
fi
