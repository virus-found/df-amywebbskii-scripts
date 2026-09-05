#!/usr/bin/env python3
"""
patch_lizardmen_gaits.py: fixes topples lizardmen asymmetric caste gaits in creature_lizardman.txt
by ensuring [SELECT_CASTE:ALL] is applied before gait definitions, restoring 8 km/h sprint
and 5 km/h innate swim to all female lizardmen castes.
"""

import sys
from pathlib import Path

TARGET_FILES = [
    Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/topples_cv_lizardmen (212)/objects/creature_lizardman.txt",
    Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/mods/3022911723 (212)/objects/creature_lizardman.txt",
    Path.home() / "games/steam/steamapps/workshop/content/975370/3022911723/objects/creature_lizardman.txt",
    Path.home() / "games/steam/steamapps/common/Dwarf Fortress/data/installed_mods/topples_cv_lizardmen (212)/objects/creature_lizardman.txt",
]

TARGET_GAIT = "[APPLY_CREATURE_VARIATION:STANDARD_WALK_CRAWL_GAITS:900:750:600:439:1900:2900] 20 kph"
PATCHED_TOKEN = "\t[SELECT_CASTE:ALL]\n\t" + TARGET_GAIT

def is_patched() -> bool:
    found = False
    for f in TARGET_FILES:
        if f.exists():
            txt = f.read_text(errors="ignore")
            if PATCHED_TOKEN in txt:
                found = True
            elif TARGET_GAIT in txt:
                return False
    return found

def apply_patch() -> None:
    patched_any = False
    for f in TARGET_FILES:
        if f.exists():
            txt = f.read_text(errors="ignore")
            if PATCHED_TOKEN in txt:
                print(f"Already patched: {f}")
                patched_any = True
            elif TARGET_GAIT in txt:
                new_txt = txt.replace("\t" + TARGET_GAIT, PATCHED_TOKEN)
                if new_txt == txt:
                    new_txt = txt.replace(TARGET_GAIT, "[SELECT_CASTE:ALL]\n\t" + TARGET_GAIT)
                f.write_text(new_txt)
                print(f"Applied lizardmen caste gaits fix to: {f}")
                patched_any = True
            else:
                print(f"Target gait token not found in: {f}")
    if not patched_any and not is_patched():
        print("No target creature_lizardman.txt files found to patch.")

def unapply_patch() -> None:
    for f in TARGET_FILES:
        if f.exists():
            txt = f.read_text(errors="ignore")
            if PATCHED_TOKEN in txt:
                new_txt = txt.replace(PATCHED_TOKEN, "\t" + TARGET_GAIT)
                f.write_text(new_txt)
                print(f"Reverted lizardmen caste gaits fix in: {f}")
            elif "[SELECT_CASTE:ALL]\n\t" + TARGET_GAIT in txt:
                new_txt = txt.replace("[SELECT_CASTE:ALL]\n\t" + TARGET_GAIT, TARGET_GAIT)
                f.write_text(new_txt)
                print(f"Reverted lizardmen caste gaits fix in: {f}")
            else:
                print(f"Already unpatched: {f}")

def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "--status"
    if cmd == "--apply":
        apply_patch()
    elif cmd == "--unapply":
        unapply_patch()
    elif cmd == "--status":
        print("Status:", "patched (all castes receive gaits)" if is_patched() else "unpatched (male-only gaits)")
    else:
        print(f"Unknown command: {cmd}. Usage: {sys.argv[0]} [--apply|--unapply|--status]")
        sys.exit(1)

if __name__ == "__main__":
    main()
