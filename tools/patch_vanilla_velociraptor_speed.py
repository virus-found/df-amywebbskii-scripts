#!/usr/bin/env python3
"""
patch_vanilla_velociraptor_speed.py: fixes the vanilla raw typo for velociraptor man walk speed
in data/vanilla/vanilla_creatures_extinct/objects/creature_cretaceous.txt
(replaces 9900 ticks with 900 ticks in STANDARD_BIPED_GAITS).
"""

import sys
from pathlib import Path

DEFAULT_DF_DIR = Path("/home/gargantua/games/steam/steamapps/common/Dwarf Fortress")

TYPO_GAIT = "[APPLY_CREATURE_VARIATION:STANDARD_BIPED_GAITS:9900:375:250:125:1900:2900] 70 kph"
FIXED_GAIT = "[APPLY_CREATURE_VARIATION:STANDARD_BIPED_GAITS:900:375:250:125:1900:2900] 70 kph"

def get_target_files(df_dir: Path):
    candidates = [
        df_dir / "data/vanilla/vanilla_creatures_extinct/objects/creature_cretaceous.txt",
        Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/data/vanilla/vanilla_creatures_extinct/objects/creature_cretaceous.txt",
    ]
    return [p for p in candidates if p.exists()]

def is_patched(df_dir: Path) -> bool:
    files = get_target_files(df_dir)
    if not files:
        return False
    for f in files:
        txt = f.read_text(errors="ignore")
        if TYPO_GAIT in txt:
            return False
        if FIXED_GAIT in txt:
            continue
        # if neither is found, check if 900 is in velociraptor block
        idx = txt.find("[CREATURE:CRETACEOUS_VELOCIRAPTOR]")
        if idx != -1:
            end = txt.find("[CREATURE:", idx + 1)
            block = txt[idx:end] if end != -1 else txt[idx:]
            if ":9900:" in block:
                return False
    return True

def apply_patch(df_dir: Path) -> bool:
    files = get_target_files(df_dir)
    if not files:
        print("No target creature_cretaceous.txt found to patch.")
        return False
    patched_any = False
    for f in files:
        txt = f.read_text(errors="ignore")
        if TYPO_GAIT in txt:
            new_txt = txt.replace(TYPO_GAIT, FIXED_GAIT)
            f.write_text(new_txt)
            print(f"Applied velociraptor speed fix to: {f}")
            patched_any = True
        elif FIXED_GAIT in txt:
            print(f"Already patched: {f}")
        else:
            # fallback if spacing or comments differ
            idx = txt.find("[CREATURE:CRETACEOUS_VELOCIRAPTOR]")
            if idx != -1:
                end = txt.find("[CREATURE:", idx + 1)
                block = txt[idx:end] if end != -1 else txt[idx:]
                if ":9900:" in block:
                    fixed_block = block.replace(":9900:", ":900:")
                    new_txt = txt[:idx] + fixed_block + (txt[end:] if end != -1 else "")
                    f.write_text(new_txt)
                    print(f"Applied velociraptor speed fix (block replacement) to: {f}")
                    patched_any = True
                else:
                    print(f"Already fixed or missing target gait in: {f}")
    return patched_any or is_patched(df_dir)

def unapply_patch(df_dir: Path) -> bool:
    files = get_target_files(df_dir)
    if not files:
        print("No target creature_cretaceous.txt found to unpatch.")
        return False
    unpatched_any = False
    for f in files:
        txt = f.read_text(errors="ignore")
        if FIXED_GAIT in txt:
            new_txt = txt.replace(FIXED_GAIT, TYPO_GAIT)
            f.write_text(new_txt)
            print(f"Reverted velociraptor speed fix in: {f}")
            unpatched_any = True
        else:
            idx = txt.find("[CREATURE:CRETACEOUS_VELOCIRAPTOR]")
            if idx != -1:
                end = txt.find("[CREATURE:", idx + 1)
                block = txt[idx:end] if end != -1 else txt[idx:]
                if ":900:375:250:125:" in block:
                    reverted_block = block.replace(":900:375:250:125:", ":9900:375:250:125:")
                    new_txt = txt[:idx] + reverted_block + (txt[end:] if end != -1 else "")
                    f.write_text(new_txt)
                    print(f"Reverted velociraptor speed fix (block replacement) in: {f}")
                    unpatched_any = True
                else:
                    print(f"Already original or missing fixed gait in: {f}")
    return unpatched_any

def main() -> None:
    df_dir = DEFAULT_DF_DIR
    cmd = "--status"
    for arg in sys.argv[1:]:
        if arg in ("--apply", "--unapply", "--status"):
            cmd = arg
        elif not arg.startswith("--"):
            df_dir = Path(arg)

    if cmd == "--apply":
        apply_patch(df_dir)
    elif cmd == "--unapply":
        unapply_patch(df_dir)
    elif cmd == "--status":
        patched = is_patched(df_dir)
        print("Status:", "patched (walk speed 900 ticks / 4 km/h)" if patched else "unpatched (vanilla typo 9900 ticks / 0.4 km/h)")
    else:
        print(f"Usage: {sys.argv[0]} [--apply|--unapply|--status] [df_dir]")
        sys.exit(1)

if __name__ == "__main__":
    main()
