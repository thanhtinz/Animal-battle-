#!/usr/bin/env python3
"""Empire Age 17d — account avatar asset build.

Copies the owner's anime avatar set (art_candidates/avatars_anime/
art_01..20.png) into the game as avatar_art_01..20.png. The stored
account avatar ids are "art:01".."art:20" (server catalogue in
server/cosmetics.go; client registry in scripts/avatars.gd).

Per OWNER CORRECTION 2 (2026-11-12) the catalogue is ONLY these
twenty: the zip fan-art set was dropped entirely and the old hero
portraits are no longer account avatars (they stay on hero
surfaces only). Nothing else is copied by this tool.

Repeatable: re-running just refreshes the copies.
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # godot/
SRC = os.path.join(ROOT, "..", "art_candidates", "avatars_anime")
DST = os.path.join(ROOT, "assets", "avatars")


def main() -> int:
    os.makedirs(DST, exist_ok=True)
    for i in range(1, 21):
        src = os.path.join(SRC, "art_%02d.png" % i)
        dst = os.path.join(DST, "avatar_art_%02d.png" % i)
        if not os.path.exists(src):
            print("MISSING source:", src)
            return 1
        shutil.copyfile(src, dst)
        print("art:%02d ->" % i, os.path.relpath(dst, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
