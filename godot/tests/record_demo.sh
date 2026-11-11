#!/usr/bin/env bash
# Demo-video recorder (13r follow-up): fresh-store relay +
# isolated XDG profile, Xvfb display, Godot running the
# demo driver scene (tests/demo_video.tscn), ffmpeg x11grab
# capturing the display in real time. Post: black-lead trim,
# H.264 encode (crf 26), stage thumbnails for verification.
set -u
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
GO="${GO:-$HOME/workspace/tools/goroot/bin/go}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$(cd "$ROOT/../server" && pwd)"
OUT="$ROOT/shots/empire_age_demo_flow_v1.mp4"
WORK="$(mktemp -d)"
mkdir -p "$ROOT/shots" "$WORK/xdg"
export XDG_DATA_HOME="$WORK/xdg"
DISP=99
SRV_PID="" XVFB_PID="" FF_PID=""
cleanup() {
  [ -n "$FF_PID" ] && kill -INT "$FF_PID" 2>/dev/null
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
  [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null
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

echo "== Xvfb :$DISP =="
Xvfb :$DISP -screen 0 1280x720x24 > "$WORK/xvfb.log" 2>&1 &
XVFB_PID=$!
sleep 1

echo "== godot (demo driver) =="
DISPLAY=:$DISP timeout 260 "$GODOT" --path "$ROOT" --resolution 1280x720 \
  res://tests/demo_video.tscn > "$WORK/godot.log" 2>&1 &
GODOT_PID=$!
sleep 1.2

echo "== ffmpeg x11grab =="
ffmpeg -y -f x11grab -framerate 30 -video_size 1280x720 -i :$DISP \
  -an -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  "$WORK/raw.mp4" > "$WORK/ffmpeg.log" 2>&1 &
FF_PID=$!

wait "$GODOT_PID"
echo "godot exit: $?"
kill -INT "$FF_PID" 2>/dev/null
wait "$FF_PID" 2>/dev/null
FF_PID=""
grep -E "DEMOLOG|ERROR|SCRIPT ERROR" "$WORK/godot.log" | head -60

# -- black-lead trim ------------------------------------------------
SS=0
BLK="$(ffmpeg -i "$WORK/raw.mp4" -vf blackdetect=d=0.2:pix_th=0.03 \
  -f null - 2>&1 | grep -o 'black_start:0 black_end:[0-9.]*' | head -1 \
  | grep -o '[0-9.]*$')"
if [ -n "$BLK" ]; then
  SS="$(awk -v b="$BLK" 'BEGIN{ if (b > 0.2) printf "%.2f", b - 0.05; else print 0 }')"
fi
echo "black lead trim: ss=$SS"

DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/raw.mp4")"
echo "raw duration: $DUR"
# Cap the total length at ~108 s (trim gameplay tail if needed).
LEN="$(awk -v d="$DUR" -v s="$SS" 'BEGIN{ r = d - s; if (r > 108) r = 108; printf "%.2f", r }')"

echo "== encode final =="
ffmpeg -y -ss "$SS" -i "$WORK/raw.mp4" -t "$LEN" -an \
  -c:v libx264 -preset medium -crf 26 -pix_fmt yuv420p \
  -movflags +faststart "$OUT" > "$WORK/encode.log" 2>&1 || {
    echo "ENCODE FAILED"; tail -5 "$WORK/encode.log"; exit 1; }

FDUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT")"
FSIZE="$(stat -c %s "$OUT")"
FRES="$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,codec_name -of csv=p=0 "$OUT")"
echo "FINAL: duration=${FDUR}s size=${FSIZE}B stream=$FRES"

# -- stage thumbnails (from DEMOLOG stage times, +0.9 s offset) ----
stage_t() { # $1=pattern $2=plus $3=fallback_fraction
  local line t
  line="$(grep -F "$1" "$WORK/godot.log" | head -1)"
  t="$(echo "$line" | sed -n 's/.*\[+\s*\([0-9.]*\)s\].*/\1/p')"
  if [ -n "$t" ]; then
    awk -v t="$t" -v p="$2" 'BEGIN{ printf "%.2f", t + 0.9 + p }'
  else
    awk -v d="$FDUR" -v f="$3" 'BEGIN{ printf "%.2f", d * f }'
  fi
}
thumb() { # $1=time $2=name
  ffmpeg -y -ss "$1" -i "$OUT" -frames:v 1 -q:v 3 \
    "$ROOT/shots/empire_age_demo_flow_v1_$2.jpg" > /dev/null 2>&1
  echo "thumb $2 @ $1s"
}
thumb "$(stage_t 'credentials typed' 0.2 0.17)" t1_register
thumb "$(stage_t 'dice pressed' 0.3 0.25)" t2_namepanel
thumb "$(stage_t 'home up' 1.0 0.33)" t3_lobby
thumb "$(stage_t 'camera back to base' 1.0 0.55)" t4_match_early
thumb "$(awk -v d="$FDUR" 'BEGIN{ printf "%.2f", d * 0.93 }')" t5_match_late

ls -la "$OUT" "$ROOT"/shots/empire_age_demo_flow_v1_t*.jpg
echo "workdir kept for logs: $WORK"
