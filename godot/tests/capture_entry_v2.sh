#!/usr/bin/env bash
# Capture + flow harness for 13r (entry flow): one relay on a
# fresh store, an ISOLATED XDG profile (so no remembered session
# leaks between runs), then:
#   1. empire_age_loading_v1.png         boot loading, mid-progress
#   2. empire_age_login_v2.png           login tab
#   3. empire_age_login_v2_register.png  register tab
#   4. empire_age_namepanel_v1.png       name panel after register
#   5. flow check: register -> dice name -> confirm -> the home
#      chip shows the display name (MPLOG lines compared below)
#   6. empire_age_welcome_v1.png         second boot with the
#      remembered session -> welcome-back screen
set -u
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
GO="${GO:-$HOME/workspace/tools/goroot/bin/go}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$(cd "$ROOT/../server" && pwd)"
WORK="$(mktemp -d)"
mkdir -p "$ROOT/shots" "$WORK/xdg"
export XDG_DATA_HOME="$WORK/xdg"
SRV_PID=""
cleanup() {
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

echo '{"accounts":{},"meta":{},"sessions":{}}' > "$WORK/store.json"

echo "== build relay =="
(cd "$SRV" && "$GO" build -o "$WORK/relay" .) || exit 1
"$WORK/relay" -addr 127.0.0.1:8765 -store "$WORK/store.json" \
  > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1
kill -0 "$SRV_PID" 2>/dev/null || { cat "$WORK/server.log"; exit 1; }

run() {
  local tag="$1"; shift
  echo "== $tag =="
  timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
    --resolution 1280x720 -- "$@" 2>&1 | grep -E "MPLOG|ERROR|SCRIPT" | head -30
}

:
run login    "--mp-shot-login=$ROOT/shots/empire_age_login_v2.png" --mp-norestore
run register "--mp-shot-login-register=$ROOT/shots/empire_age_login_v2_register.png" --mp-norestore
:
:

ls -la "$ROOT/shots/empire_age_login_v2.png" \
       "$ROOT/shots/empire_age_login_v2_register.png"
