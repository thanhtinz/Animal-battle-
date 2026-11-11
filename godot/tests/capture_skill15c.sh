#!/usr/bin/env bash
# Empire Age 15c capture harness (functional shots, not a test):
#   empire_age_skill_cluster_v1.png — a live match HUD with the
#     RAISED skill cluster: a clear gap under it above the action
#     panel, and each hero skill's NAME labelled under its button.
#   empire_age_skill_hold_v1.png — the same match a moment later:
#     Chiêu 2's button is being HELD by a real injected mouse
#     press; the info card floats above the cluster with the
#     skill's name, cooldown and effect description.
# Heroes come from the --mp-hero-test staging (spawned mid-map
# at tick 5); the windowed client is the host, the guest is
# headless (the capture_mp2.sh pattern — a windowed guest falls
# behind the tick pace on this machine).
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
GO=${GO:-$HOME/workspace/tools/goroot/bin/go}
ADDR=127.0.0.1:8765
WORK=$(mktemp -d /tmp/ea-skill15c.XXXXXX)
SHOTS="$PWD/shots"
mkdir -p "$SHOTS"
echo "capture workdir: $WORK"

(cd ../server && "$GO" build -o "$WORK/relay" .) || { echo "FAIL: server build"; exit 1; }
"$WORK/relay" -addr "$ADDR" > "$WORK/server.log" 2>&1 &
SRV=$!
sleep 1
curl -sf "http://$ADDR/healthz" > /dev/null || { echo "FAIL: server not up"; kill $SRV 2>/dev/null; exit 1; }

room_code_of() { # room_code_of <logfile>
	grep -o "MPLOG room code=[A-Z0-9]*" "$1" 2>/dev/null | head -1 | cut -d= -f2
}

run_shot() { # run_shot <label> <host-extra-args...> ; uses $SHOTFILE
	local label=$1; shift
	timeout 150 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
		--resolution 1152x864 -- \
		--mp-auto=create --mp-name=ChuPhong --mp-hero-test \
		--mp-hold=100000 "$@" > "$WORK/$label-host.log" 2>&1 &
	local wpid=$!
	local code=""
	for _ in $(seq 1 60); do
		code=$(room_code_of "$WORK/$label-host.log")
		[ -n "$code" ] && break
		sleep 1
	done
	echo "$label room: ${code:-<none>}"
	timeout 150 "$GODOT" --headless --fixed-fps 30 --path . -- \
		--mp-auto=join --mp-code="$code" --mp-name=NguoiChup \
		--mp-hero-test --mp-hold=100000 > "$WORK/$label-guest.log" 2>&1 &
	local gpid=$!
	wait $wpid 2>/dev/null
	kill $gpid 2>/dev/null
}

# --- shot 1: the raised cluster with name labels ----------------
run_shot cluster --mp-skill-shot="$SHOTS/empire_age_skill_cluster_v1.png"
grep -q "MPLOG skill cluster shot saved" "$WORK/cluster-host.log" \
	&& echo "cluster shot saved" || echo "WARN: cluster shot may be missing"

# --- shot 2: press-and-hold info card ---------------------------
run_shot hold --mp-skill-hold-shot="$SHOTS/empire_age_skill_hold_v1.png"
grep -q "MPLOG skill hold shot saved" "$WORK/hold-host.log" \
	&& echo "hold shot saved" || echo "WARN: hold shot may be missing"
grep "MPLOG skill" "$WORK/hold-host.log"

kill $SRV 2>/dev/null
ls -la "$SHOTS/empire_age_skill_cluster_v1.png" "$SHOTS/empire_age_skill_hold_v1.png" 2>/dev/null
echo "logs: $WORK"
