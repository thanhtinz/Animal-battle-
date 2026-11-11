#!/usr/bin/env bash
# Empire Age 14c capture driver: Collection (8 heroes), Phong
# Linh in match (name overhead + skill buttons), cyclone Ulti.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/workspace/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
mkdir -p shots
timeout 180 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . \
	--resolution 1280x720 res://tests/capture_heroes14c.tscn 2>&1 \
	| grep -E "CAPTURE|ERROR" | head -10
ls -la shots/empire_age_heroes8_collection_v1.png \
	shots/empire_age_heroes8_match_v1.png \
	shots/empire_age_heroes8_skill_v1.png
