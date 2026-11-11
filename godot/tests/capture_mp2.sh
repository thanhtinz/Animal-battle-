#!/usr/bin/env bash
# Empire Age P4 stage-2 capture harness (NOT part of mp_smoke.sh).
#
# Produces the two stage-2 screenshots under shots/:
#   empire_age_account_lobby_v1.png — logged-in lobby, leaderboard
#     open. To make the board real, two account clients first play
#     a full scripted match against a relay using a temp account
#     store; the relay is then RESTARTED on the same store file
#     (persistence proof) and both clients log back in (register
#     fails -> driver falls back to login) for the lobby shot.
#   empire_age_chat_v1.png — in-match chat panel with both scripted
#     greetings (host at tick 8, peer at tick 14, panel opened at
#     tick 24 on the windowed host).
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-mp2-capture.XXXXXX)
SHOTS="$PWD/shots"
mkdir -p "$SHOTS"
echo "capture workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }

start_server() {
	"$WORK/relay" -addr "$ADDR" -store "$WORK/accounts.json" > "$1" 2>&1 &
	SRV=$!
	sleep 1
	curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }
}
wait_code() { # $1 = host log
	local code=""
	for _ in $(seq 1 60); do
		code=$(grep -o "MPLOG room code=[A-Z0-9]*" "$1" 2>/dev/null | head -1 | cut -d= -f2)
		[ -n "$code" ] && break
		sleep 1
	done
	echo "$code"
}

# ---------- Phase A: a real scripted match between two accounts ----------
echo "--- phase A: account match (banks W/L) ---"
start_server "$WORK/serverA.log"
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=create --mp-name=TinPro --mp-account=TinPro:secret1 > "$WORK/aA.log" 2>&1 &
A=$!
CODE=$(wait_code "$WORK/aA.log")
[ -n "$CODE" ] || { echo "FAIL: no room (phase A)"; kill $A $SRV 2>/dev/null; exit 1; }
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code="$CODE" --mp-name=MinhAnh --mp-account=MinhAnh:secret1 > "$WORK/bA.log" 2>&1 &
B=$!
wait $A; wait $B
kill $SRV 2>/dev/null
grep -q "MPLOG result victory" "$WORK/aA.log" && echo "phase A match done (host won)" || echo "WARN: phase A result unclear"
echo "store contents:"; cat "$WORK/accounts.json" 2>/dev/null | head -c 400; echo

# ---------- Phase B: account lobby + leaderboard shot ----------
echo "--- phase B: account lobby shot ---"
start_server "$WORK/serverB.log"
xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path . --resolution 1152x768 -- \
	--mp-auto=create \
	--mp-shot-account="$SHOTS/empire_age_account_lobby_v1.png" \
	--mp-account=TinPro:secret1 --mp-name=TinPro > "$WORK/aB.log" 2>&1 &
A=$!
CODE=$(wait_code "$WORK/aB.log")
[ -n "$CODE" ] || { echo "FAIL: no room (phase B)"; kill $A $SRV 2>/dev/null; exit 1; }
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code="$CODE" --mp-name=MinhAnh --mp-account=MinhAnh:secret1 --mp-hold=45 > "$WORK/bB.log" 2>&1 &
B=$!
wait $A
kill $B $SRV 2>/dev/null
grep -q "MPLOG account shot saved" "$WORK/aB.log" && echo "account lobby shot saved" || echo "WARN: account shot may be missing"

# ---------- Phase C: in-match chat shot ----------
echo "--- phase C: chat shot ---"
start_server "$WORK/serverC.log"
xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path . --resolution 1152x768 -- \
	--mp-auto=create --mp-name=TinPro --mp-chat-shot="$SHOTS/empire_age_chat_v1.png" > "$WORK/aC.log" 2>&1 &
A=$!
CODE=$(wait_code "$WORK/aC.log")
[ -n "$CODE" ] || { echo "FAIL: no room (phase C)"; kill $A $SRV 2>/dev/null; exit 1; }
timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
	--mp-auto=join --mp-code="$CODE" --mp-name=MinhAnh --mp-chat-peer --mp-hold=400 > "$WORK/bC.log" 2>&1 &
B=$!
wait $A
kill $B $SRV 2>/dev/null
grep -q "MPLOG chat shot saved" "$WORK/aC.log" && echo "chat shot saved" || echo "WARN: chat shot may be missing"

ls -la "$SHOTS/empire_age_account_lobby_v1.png" "$SHOTS/empire_age_chat_v1.png" 2>/dev/null
echo "logs: $WORK"
