#!/usr/bin/env python3
"""
patch_ratfolk_weights.py: applies weight boost for Ratfolk
"""
import sys, shutil
from pathlib import Path

SOURCE_PATCH = Path("/home/gargantua/docs/games/df/amywebbskii-scripts/raw_patches/entity_ratfolk_weight_boost.txt")
TARGET_FILENAME = "entity_ratfolk_weight_boost.txt"

TARGET_DIRS = [
    Path("/home/gargantua/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/sm_cv_ratfolk (2)/objects"),
]

def is_patched() -> bool:
    for d in TARGET_DIRS:
        if (d / TARGET_FILENAME).exists():
            return True
    return False

def apply_patch() -> None:
    if not SOURCE_PATCH.exists():
        print(f"Error: Source patch not found: {SOURCE_PATCH}")
        sys.exit(1)
    applied_any = False
    for d in TARGET_DIRS:
        if d.exists():
            dst = d / TARGET_FILENAME
            shutil.copyfile(SOURCE_PATCH, dst)
            print(f"Applied Ratfolk weight boost to: {dst}")
            applied_any = True
    if not applied_any:
        print("Warning: Target mod directories for Ratfolk not found.")

def unapply_patch() -> None:
    for d in TARGET_DIRS:
        dst = d / TARGET_FILENAME
        if dst.exists():
            dst.unlink()
            print(f"Removed Ratfolk weight boost from: {dst}")

def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "--status"
    if cmd == "--apply":
        apply_patch()
    elif cmd == "--unapply":
        unapply_patch()
    elif cmd == "--status":
        print("Status:", "patched" if is_patched() else "unpatched")
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)

if __name__ == "__main__":
    main()