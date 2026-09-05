#!/usr/bin/env python3
"""
patch_ha_illithid_spawns.py: fixes high adventure illithid worldgen extinction.
replaces incompatible dark fortress on mountain with detailed cave / underdark / wetland
start biomes, adds site tolerances, increases starting civ count, and adds child reproduction
tokens so illithid colonies consistently generate and thrive alongside ixthids.
"""

import sys
from pathlib import Path

TARGET_DIRS = [
    Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/HIGH_ADVENTURE (20)/objects",
    Path("/home/gargantua/games/steam/steamapps/common/Dwarf Fortress/mods/high-adventure/objects"),
]

RAW_PATCH_WEIGHTS = Path("/home/gargantua/docs/games/df/amywebbskii-scripts/raw_patches/entity_high_adventure_weight_boost.txt")

ENTITY_ORIG = """\t[DEFAULT_SITE_TYPE:DARK_FORTRESS]
\t[LIKES_SITE:DARK_FORTRESS]"""

ENTITY_PATCHED = """\t[DEFAULT_SITE_TYPE:CAVE_DETAILED]
\t[LIKES_SITE:CAVE_DETAILED]
\t[LIKES_SITE:DARK_FORTRESS]
\t[TOLERATES_SITE:CAVE_DETAILED]
\t[TOLERATES_SITE:DARK_FORTRESS]
\t[TOLERATES_SITE:CAVE]
\t[TOLERATES_SITE:CITY]"""

BIOME_ORIG = "\t[EXCLUSIVE_START_BIOME:MOUNTAIN]"
BIOME_PATCHED = """\t[START_BIOME:MOUNTAIN]
\t[START_BIOME:DESERT_ROCK]
\t[START_BIOME:SUBTERRANEAN_CHASM]
\t[START_BIOME:ANY_WETLAND]"""

CIV_NUM_ORIG = "\t[MAX_STARTING_CIV_NUMBER:4]"
CIV_NUM_PATCHED = "\t[MAX_STARTING_CIV_NUMBER:50]"

CREATURE_ORIG = "\t[PREFSTRING:intelligence]"
CREATURE_PATCHED = """\t[PREFSTRING:intelligence]
\t[BABY:1]
\t[CHILD:12]"""

def is_file_patched(fpath: Path) -> bool:
    if not fpath.exists():
        return False
    txt = fpath.read_text(errors="ignore")
    if fpath.name == "entity_ha_illithid.txt":
        return ENTITY_PATCHED in txt
    if fpath.name == "creature_ha_illithid.txt":
        return CREATURE_PATCHED in txt
    return False

def is_patched() -> bool:
    all_ok = True
    found_any = False
    for d in TARGET_DIRS:
        ef = d / "entity_ha_illithid.txt"
        cf = d / "creature_ha_illithid.txt"
        if ef.exists() and cf.exists():
            found_any = True
            if not (is_file_patched(ef) and is_file_patched(cf)):
                all_ok = False
    return found_any and all_ok

def patch_weight_boost(file_path: Path, apply: bool) -> None:
    if not file_path.exists():
        return
    txt = file_path.read_text(errors="ignore")
    if apply:
        txt_new = txt.replace(
            "[EXCLUSIVE_START_BIOME:MOUNTAIN]",
            "[START_BIOME:MOUNTAIN]\n\t[START_BIOME:DESERT_ROCK]\n\t[START_BIOME:SUBTERRANEAN_CHASM]\n\t[START_BIOME:ANY_WETLAND]"
        )
        txt_new = txt_new.replace(
            "[MAX_STARTING_CIV_NUMBER:4]",
            "[MAX_STARTING_CIV_NUMBER:50]"
        )
        if txt_new != txt:
            file_path.write_text(txt_new)
            print(f"updated illithid weight boost parameters in: {file_path}")
    else:
        txt_new = txt.replace(
            "[START_BIOME:MOUNTAIN]\n\t[START_BIOME:DESERT_ROCK]\n\t[START_BIOME:SUBTERRANEAN_CHASM]\n\t[START_BIOME:ANY_WETLAND]",
            "[EXCLUSIVE_START_BIOME:MOUNTAIN]"
        )
        txt_new = txt_new.replace(
            "[MAX_STARTING_CIV_NUMBER:50]",
            "[MAX_STARTING_CIV_NUMBER:4]"
        )
        if txt_new != txt:
            file_path.write_text(txt_new)
            print(f"reverted illithid weight boost parameters in: {file_path}")

def apply_patch() -> None:
    for d in TARGET_DIRS:
        ef = d / "entity_ha_illithid.txt"
        cf = d / "creature_ha_illithid.txt"
        wf = d / "entity_high_adventure_weight_boost.txt"
        if ef.exists():
            txt = ef.read_text(errors="ignore")
            if ENTITY_ORIG in txt:
                txt = txt.replace(ENTITY_ORIG, ENTITY_PATCHED)
                txt = txt.replace(BIOME_ORIG, BIOME_PATCHED)
                txt = txt.replace(CIV_NUM_ORIG, CIV_NUM_PATCHED)
                ef.write_text(txt)
                print(f"applied illithid site & biome patch to: {ef}")
            else:
                print(f"entity already patched or target token missing in: {ef}")
        if cf.exists():
            ctxt = cf.read_text(errors="ignore")
            if CREATURE_ORIG in ctxt and CREATURE_PATCHED not in ctxt:
                ctxt = ctxt.replace(CREATURE_ORIG, CREATURE_PATCHED)
                cf.write_text(ctxt)
                print(f"applied illithid child reproduction tokens to: {cf}")
            else:
                print(f"creature already patched or target token missing in: {cf}")
        if wf.exists():
            patch_weight_boost(wf, apply=True)

    if RAW_PATCH_WEIGHTS.exists():
        patch_weight_boost(RAW_PATCH_WEIGHTS, apply=True)

def unapply_patch() -> None:
    for d in TARGET_DIRS:
        ef = d / "entity_ha_illithid.txt"
        cf = d / "creature_ha_illithid.txt"
        wf = d / "entity_high_adventure_weight_boost.txt"
        if ef.exists():
            txt = ef.read_text(errors="ignore")
            if ENTITY_PATCHED in txt:
                txt = txt.replace(ENTITY_PATCHED, ENTITY_ORIG)
                txt = txt.replace(BIOME_PATCHED, BIOME_ORIG)
                txt = txt.replace(CIV_NUM_PATCHED, CIV_NUM_ORIG)
                ef.write_text(txt)
                print(f"reverted illithid site & biome patch in: {ef}")
        if cf.exists():
            ctxt = cf.read_text(errors="ignore")
            if CREATURE_PATCHED in ctxt:
                ctxt = ctxt.replace(CREATURE_PATCHED, CREATURE_ORIG)
                cf.write_text(ctxt)
                print(f"reverted illithid child reproduction tokens in: {cf}")
        if wf.exists():
            patch_weight_boost(wf, apply=False)

    if RAW_PATCH_WEIGHTS.exists():
        patch_weight_boost(RAW_PATCH_WEIGHTS, apply=False)

def main():
    action = "--apply"
    if len(sys.argv) > 1:
        action = sys.argv[1]

    if action == "--status":
        if is_patched():
            print("patch_ha_illithid_spawns: applied")
            sys.exit(0)
        else:
            print("patch_ha_illithid_spawns: not applied")
            sys.exit(1)
    elif action == "--unapply":
        unapply_patch()
    elif action == "--apply":
        apply_patch()
    else:
        print(f"unknown argument: {action}. use --apply, --unapply, or --status")
        sys.exit(2)

if __name__ == "__main__":
    main()
