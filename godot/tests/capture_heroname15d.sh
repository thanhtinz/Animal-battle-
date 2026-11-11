#!/usr/bin/env bash
# Empire Age 15d capture harness (functional shot, not a test):
#   empire_age_hero_name_v1.png — an SP match (account display
#   name "Tin"): the local hero's overhead label reads "Tin" and
#   the bot hero's reads "Máy" — the players-panel names, never
#   the old "Bạn" placeholder.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
SHOTS="$PWD/shots"
mkdir -p "$SHOTS"
timeout 120 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
	--resolution 1152x864 res://tests/capture_heroname15d.tscn -- \
	--hero-name-shot="$SHOTS/empire_age_hero_name_v1.png"
ls -la "$SHOTS/empire_age_hero_name_v1.png" 2>/dev/null
