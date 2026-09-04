#!/usr/bin/env python3
"""
tools/patch_animal_people_weights.py
automates consolidating animal people entities from 50 down to 9 broad groups
and applying the vanilla weight boost patch for "all animal people civilized & playable" (steam id 3412625442).
"""

import sys
import shutil
from pathlib import Path

PATCH_ROOT = Path(__file__).resolve().parent.parent / "raw_patches"
VANILLA_BOOST_SRC = PATCH_ROOT / "entity_vanilla_weight_boost.txt"
CONSOLIDATED_SRC_DIR = PATCH_ROOT / "consolidated_animal_people"

TARGET_DIRS = [
    Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/all_animal_people_civilized_and_playable (9)/objects",
    Path.home() / "games/steam/steamapps/workshop/content/975370/3412625442/objects"
]

CONSOLIDATED_FILES = [
    "entity_predator_animal_people.txt",
    "entity_ungulate_animal_people.txt",
    "entity_reptile_amphibian_animal_people.txt",
    "entity_small_mammal_animal_people.txt",
    "entity_invertebrate_animal_people.txt",
    "entity_aquatic_marine_animal_people.txt",
    "entity_avian_animal_people.txt",
    "entity_extinct_animal_people.txt",
    "entity_cavern_animal_people.txt"
]

def is_target_installed() -> bool:
    return any(d.exists() for d in TARGET_DIRS)

def is_patched() -> bool:
    for d in TARGET_DIRS:
        if (d / "entity_predator_animal_people.txt").exists():
            return True
    return False

def apply_patch() -> bool:
    if not VANILLA_BOOST_SRC.exists():
        print(f"error: source patch file not found: {VANILLA_BOOST_SRC}")
        return False
    if not CONSOLIDATED_SRC_DIR.exists():
        print(f"error: consolidated raw source dir not found: {CONSOLIDATED_SRC_DIR}")
        return False

    applied = False
    for d in TARGET_DIRS:
        if d.exists():
            # 1. apply vanilla weight boost
            dst_vanilla = d / "entity_vanilla_weight_boost.txt"
            shutil.copy2(VANILLA_BOOST_SRC, dst_vanilla)
            print(f"applied vanilla weight boost patch to: {dst_vanilla}")

            # 2. copy consolidated entity files
            for cfn in CONSOLIDATED_FILES:
                src_f = CONSOLIDATED_SRC_DIR / cfn
                dst_f = d / cfn
                shutil.copy2(src_f, dst_f)
                print(f"installed consolidated entity: {dst_f.name}")

            # 3. disable original 50 loose good/evil entity files
            loose_files = list(d.glob("entity_good_*.txt")) + list(d.glob("entity_evil_*.txt"))
            for lf in loose_files:
                dis_f = lf.with_suffix(".txt.disabled")
                lf.rename(dis_f)
            print(f"disabled {len(loose_files)} loose animal people entity definitions in: {d.name}")
            applied = True

    if not applied:
        print("notice: no target mod directories found (all animal people civilized & playable not installed).")
    return applied

def unapply_patch() -> bool:
    removed = False
    for d in TARGET_DIRS:
        if d.exists():
            # 1. remove vanilla weight boost
            dst_vanilla = d / "entity_vanilla_weight_boost.txt"
            if dst_vanilla.exists():
                dst_vanilla.unlink()
                print(f"removed: {dst_vanilla}")
                removed = True

            # 2. remove consolidated entity files
            for cfn in CONSOLIDATED_FILES:
                cf = d / cfn
                if cf.exists():
                    cf.unlink()
                    print(f"removed consolidated entity: {cf.name}")
                    removed = True

            # 3. re-enable disabled loose files
            disabled_files = list(d.glob("entity_good_*.txt.disabled")) + list(d.glob("entity_evil_*.txt.disabled"))
            for df in disabled_files:
                orig_f = df.with_name(df.name[:-9])  # strip .disabled
                df.rename(orig_f)
            if disabled_files:
                print(f"re-enabled {len(disabled_files)} original entity definitions in: {d.name}")
                removed = True

    return removed

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--unapply":
        unapply_patch()
    elif len(sys.argv) > 1 and sys.argv[1] == "--status":
        status = "PATCHED" if is_patched() else "UNPATCHED"
        print(f"animal people consolidated weights status: {status}")
    else:
        apply_patch()

if __name__ == "__main__":
    main()
