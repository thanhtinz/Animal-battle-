#!/usr/bin/env bash
# Empire Age 15f capture harness (functional shot, not a test):
#   empire_age_players_name_v1.png — the SP players panel of an
#   account named "Tin": the header reads "Tin đấu với Máy" and
#   the local player's card carries the same real name (never
#   the old "Bạn" placeholder).
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
SHOTS="$PWD/shots"
mkdir -p "$SHOTS"
timeout 120 xvfb-run -a -s "-screen 0 1400x1000x24" "$GODOT" --path . \
	--resolution 1152x864 res://tests/capture_players15f.tscn -- \
	--players-name-shot="$SHOTS/empire_age_players_name_v1.png"
ls -la "$SHOTS/empire_age_players_name_v1.png" 2>/dev/null
