#!/usr/bin/env bash
# Loading-screen capture for 13r follow-up 4b (ornate end caps +
# sparkle fill head): boot loading at mid-progress only.
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

echo "== loading v3 =="
timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" \
  --resolution 1280x720 -- \
  "--mp-shot-loading=$ROOT/shots/empire_age_loading_v3.png" \
  --mp-norestore 2>&1 | grep -E "MPLOG|ERROR|SCRIPT" | head -30

ls -la "$ROOT/shots/empire_age_loading_v3.png"
