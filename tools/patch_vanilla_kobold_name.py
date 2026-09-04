#!/usr/bin/env python3
"""
patch_vanilla_kobold_name.py: reverts 'cobald' rename back to 'kobold' in dnd_kobold_race and intros_kobolds
"""

import sys
from pathlib import Path

TARGET_FILES = [
    Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/dnd_kobold_race (51)/objects/creature_5e_kobold.txt",
    Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/dnd_kobold_race (1)/objects/creature_5e_kobold.txt",
    Path.home() / "games/steam/steamapps/workshop/content/975370/3281525928/objects/creature_5e_kobold.txt",
    Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/intros_kobolds (21)/objects/creature_kobold.txt",
    Path.home() / "games/steam/steamapps/workshop/content/975370/2902807802/objects/creature_kobold.txt",
]

COBALD_NAME = "[NAME:cobald:cobalds:cobald]"
COBALD_CASTE = "[CASTE_NAME:cobald:cobalds:cobald]"

KOBOLD_NAME = "[NAME:kobold:kobolds:kobold]"
KOBOLD_CASTE = "[CASTE_NAME:kobold:kobolds:kobold]"

def is_patched() -> bool:
    for f in TARGET_FILES:
        if f.exists():
            txt = f.read_text(errors="ignore")
            if COBALD_NAME in txt or COBALD_CASTE in txt:
                return False
    return True

def apply_patch() -> None:
    patched_any = False
    for f in TARGET_FILES:
        if f.exists():
            txt = f.read_text(errors="ignore")
            if COBALD_NAME in txt or COBALD_CASTE in txt:
                new_txt = txt.replace(COBALD_NAME, KOBOLD_NAME).replace(COBALD_CASTE, KOBOLD_CASTE)
                f.write_text(new_txt)
                print(f"Applied vanilla kobold name to: {f}")
                patched_any = True
            else:
                print(f"Already vanilla name: {f}")
    if not patched_any and not is_patched():
        print("No target files found to patch.")

def unapply_patch() -> None:
    for f in TARGET_FILES:
        if f.exists():
            txt = f.read_text(errors="ignore")
            if "[SELECT_CREATURE:KOBOLD]" in txt and (KOBOLD_NAME in txt or KOBOLD_CASTE in txt):
                new_txt = txt.replace(KOBOLD_NAME, COBALD_NAME).replace(KOBOLD_CASTE, COBALD_CASTE)
                f.write_text(new_txt)
                print(f"Restored cobald name to: {f}")
            else:
                print(f"Already cobald name: {f}")

def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "--status"
    if cmd == "--apply":
        apply_patch()
    elif cmd == "--unapply":
        unapply_patch()
    elif cmd == "--status":
        print("Status:", "patched (vanilla kobold name)" if is_patched() else "unpatched (custom cobald name)")
    else:
        print(f"Unknown command: {cmd}. Usage: {sys.argv[0]} [--apply|--unapply|--status]")
        sys.exit(1)

if __name__ == "__main__":
    main()
