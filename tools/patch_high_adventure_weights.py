#!/usr/bin/env python3
"""
patch_high_adventure_weights.py: applies 10x civilization weight boost for all High Adventure civilizations
(Kobolds, Second Humans, Dark Dwarves, Drow, High Elves, Orcs, Illithids, Ancient Golems, Succubi)
and bundles illithid mountain/underdark cave site fixes, expanded start biomes, and baby/child reproduction tokens.
"""

import sys, shutil
from pathlib import Path

SOURCE_PATCH = Path("/home/gargantua/docs/games/df/amywebbskii-scripts/raw_patches/entity_high_adventure_weight_boost.txt")
TARGET_FILENAME = "entity_high_adventure_weight_boost.txt"

TARGET_DIRS = [
    Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/HIGH_ADVENTURE (20)/objects",
    Path("/home/gargantua/games/steam/steamapps/common/Dwarf Fortress/mods/high-adventure/objects"),
]

# Old standalone files to purge when applying or unapplying
OLD_FILES = [
    "entity_ha_kobold_weight_boost.txt",
    "entity_second_humans_weight_boost.txt",
]

def is_patched() -> bool:
    for d in TARGET_DIRS:
        dst = d / TARGET_FILENAME
        if dst.exists():
            return True
    return False

def purge_old_files() -> None:
    for d in TARGET_DIRS:
        for old in OLD_FILES:
            old_p = d / old
            if old_p.exists():
                old_p.unlink()
                print(f"Purged superseded standalone patch: {old_p}")

def apply_patch() -> None:
    if not SOURCE_PATCH.exists():
        print(f"Error: Source patch definition not found: {SOURCE_PATCH}")
        sys.exit(1)
    purge_old_files()
    applied_any = False
    for d in TARGET_DIRS:
        if d.exists():
            dst = d / TARGET_FILENAME
            shutil.copyfile(SOURCE_PATCH, dst)
            print(f"Applied unified High Adventure weight boost to: {dst}")
            applied_any = True
    if not applied_any:
        print("Warning: Target mod directories for HIGH_ADVENTURE not found.")

    # Bundle illithid spawn and reproduction fixes
    try:
        import patch_ha_illithid_spawns
        patch_ha_illithid_spawns.apply_patch()
    except Exception as e:
        print(f"Warning: Failed to apply bundled illithid spawn fixes: {e}")

def unapply_patch() -> None:
    purge_old_files()
    for d in TARGET_DIRS:
        dst = d / TARGET_FILENAME
        if dst.exists():
            dst.unlink()
            print(f"Removed unified High Adventure weight boost from: {dst}")

def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "--status"
    if cmd == "--apply":
        apply_patch()
    elif cmd == "--unapply":
        unapply_patch()
    elif cmd == "--status":
        print("Status:", "patched (10x boost active for all HA civs, illithid spawn fixes bundled)" if is_patched() else "unpatched")
    else:
        print(f"Unknown command: {cmd}. Usage: {sys.argv[0]} [--apply|--unapply|--status]")
        sys.exit(1)

if __name__ == "__main__":
    main()
