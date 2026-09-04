#!/usr/bin/env python3
import os
import sys

def patch_vanilla(df_dir):
    mat_file = os.path.join(df_dir, "data", "vanilla", "vanilla_materials", "objects", "material_template_default.txt")
    react_file = os.path.join(df_dir, "data", "vanilla", "vanilla_reactions", "objects", "reaction_other.txt")

    if not os.path.exists(mat_file) or not os.path.exists(react_file):
        print(f"Vanilla files not found under {df_dir}")
        return False

    # 1. Patch material_template_default.txt
    with open(mat_file, "r") as f:
        mat_text = f.read()

    if "[STOCKPILE_GLOB]" not in mat_text:
        target = "[ROTS]"
        replacement = "[ROTS]\n\t[STOCKPILE_GLOB]\n\t[DO_NOT_CLEAN_GLOB]\n\t[BUTCHER_SPECIAL:GLOB:NONE]\n\t[REACTION_CLASS:SKIN]"
        # Look specifically inside [MATERIAL_TEMPLATE:SKIN_TEMPLATE] block
        idx_skin = mat_text.find("[MATERIAL_TEMPLATE:SKIN_TEMPLATE]")
        if idx_skin != -1:
            idx_rots = mat_text.find("[ROTS]", idx_skin)
            if idx_rots != -1 and idx_rots < idx_skin + 2000:
                mat_text = mat_text[:idx_rots] + replacement + mat_text[idx_rots + len("[ROTS]"):]
                with open(mat_file, "w") as f:
                    f.write(mat_text)
                print(f"Patched: {mat_file} (added SKIN_TEMPLATE glob & reaction tokens)")
    else:
        print(f"Already patched: {mat_file}")

    # 2. Patch reaction_other.txt
    with open(react_file, "r") as f:
        react_text = f.read()

    react_modified = False
    old_tan = "[REACTION:TAN_A_HIDE]\n\t[NAME:tan a hide]\n\t[BUILDING:TANNER:CUSTOM_T]\n\t[REAGENT:A:1:NONE:NONE:NONE:NONE][USE_BODY_COMPONENT][UNROTTEN]"
    new_tan = "[REACTION:TAN_A_HIDE]\n\t[NAME:tan a hide]\n\t[BUILDING:TANNER:CUSTOM_T]\n\t[REAGENT:A:375:GLOB:NONE:NONE:NONE][REACTION_CLASS:SKIN][UNROTTEN]"

    if old_tan in react_text:
        react_text = react_text.replace(old_tan, new_tan)
        react_modified = True
        print(f"Patched: {react_file} (TAN_A_HIDE scaled to glob reagents)")

    old_parch = "[REACTION:MAKE_PARCHMENT]\n\t[NAME:make parchment]\n\t[BUILDING:TANNER:CUSTOM_P]\n\t[REAGENT:A:1:NONE:NONE:NONE:NONE][USE_BODY_COMPONENT][UNROTTEN]"
    new_parch = "[REACTION:MAKE_PARCHMENT]\n\t[NAME:make parchment]\n\t[BUILDING:TANNER:CUSTOM_P]\n\t[REAGENT:A:1:NONE:NONE:NONE:NONE][REACTION_CLASS:SKIN][UNROTTEN]"

    if old_parch in react_text:
        react_text = react_text.replace(old_parch, new_parch)
        react_modified = True
        print(f"Patched: {react_file} (MAKE_PARCHMENT scaled to skin class)")

    if react_modified:
        with open(react_file, "w") as f:
            f.write(react_text)
    else:
        print(f"Already patched: {react_file}")

    return True

if __name__ == "__main__":
    df_dir = sys.argv[1] if len(sys.argv) > 1 else "/home/gargantua/games/steam/steamapps/common/Dwarf Fortress"
    patch_vanilla(df_dir)
