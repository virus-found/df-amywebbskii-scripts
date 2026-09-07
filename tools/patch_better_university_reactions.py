#!/usr/bin/env python3
"""
patch_better_university_reactions.py: fixes 133 malformed 7-token reagent definitions
in Better University (mod ID: BetterUniversity, Steam ID: 3525344907).

Vanilla Dwarf Fortress expects 6-element reagent tokens:
  [REAGENT:id:quantity:item_type:item_subtype:mat_type:mat_index]
Better University defines:
  [REAGENT:A:1:SMALLGEM:NONE:INORGANIC:GEM_OF_KNOWLEDGE:NONE]
The trailing ':NONE]' shifts parameters and causes DF to dereference a null pointer
at 0x1d55154 (testb $0x8, (%rax)) when opening the Labor -> Stone Use tab.

Version guard:
  If NUMERIC_VERSION > 4, the patch freezes/locks to require manual review
  in case the upstream author (Do_oy) has fixed or modified the reactions.
"""

import sys
from pathlib import Path

TARGET_MOD_DIRS = [
    Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/BetterUniversity (4)",
    Path.home() / ".local/share/Bay 12 Games/Dwarf Fortress/mods/3525344907 (4)",
    Path.home() / "games/steam/steamapps/workshop/content/975370/3525344907",
    Path.home() / "games/steam/steamapps/common/Dwarf Fortress/data/installed_mods/BetterUniversity (4)",
]

BROKEN_TOKEN = ":GEM_OF_KNOWLEDGE:NONE]"
FIXED_TOKEN = ":GEM_OF_KNOWLEDGE]"

MAX_SUPPORTED_VERSION = 4

def get_installed_dirs():
    return [d for d in TARGET_MOD_DIRS if d.exists() and (d / "objects").exists()]

def check_upstream_version(mod_dir: Path) -> int:
    info_file = mod_dir / "info.txt"
    if not info_file.exists():
        return 0
    txt = info_file.read_text(errors="ignore")
    for line in txt.splitlines():
        line = line.strip()
        if line.startswith("[NUMERIC_VERSION:") and line.endswith("]"):
            val = line[len("[NUMERIC_VERSION:"): -1].strip()
            try:
                return int(val)
            except ValueError:
                pass
    return 0

def is_frozen() -> tuple[bool, str]:
    for d in get_installed_dirs():
        ver = check_upstream_version(d)
        if ver > MAX_SUPPORTED_VERSION:
            return True, f"upstream version {ver} > {MAX_SUPPORTED_VERSION} detected in {d.name}; manual audit required"
    return False, ""

def is_patched() -> bool:
    installed = get_installed_dirs()
    if not installed:
        return False
    for d in installed:
        obj_dir = d / "objects"
        for rf in obj_dir.glob("reaction_*.txt"):
            txt = rf.read_text(errors="ignore")
            if BROKEN_TOKEN in txt:
                return False
    return True

def apply_patch() -> bool:
    frozen, reason = is_frozen()
    if frozen:
        print(f"Error: patch is frozen/locked: {reason}")
        return False

    installed = get_installed_dirs()
    if not installed:
        print("No target BetterUniversity mod directories found.")
        return False

    total_patched = 0
    for d in installed:
        obj_dir = d / "objects"
        dir_patched = 0
        for rf in sorted(obj_dir.glob("reaction_*.txt")):
            txt = rf.read_text(errors="ignore")
            if BROKEN_TOKEN in txt:
                count = txt.count(BROKEN_TOKEN)
                new_txt = txt.replace(BROKEN_TOKEN, FIXED_TOKEN)
                rf.write_text(new_txt)
                dir_patched += count
        total_patched += dir_patched
        print(f"Applied BetterUniversity reaction fix to: {d} ({dir_patched} tokens fixed)")

    return True

def unapply_patch() -> bool:
    installed = get_installed_dirs()
    if not installed:
        print("No target BetterUniversity mod directories found.")
        return False

    total_reverted = 0
    for d in installed:
        obj_dir = d / "objects"
        dir_reverted = 0
        for rf in sorted(obj_dir.glob("reaction_*.txt")):
            txt = rf.read_text(errors="ignore")
            target = "SMALLGEM:NONE:INORGANIC:GEM_OF_KNOWLEDGE]"
            revert_to = "SMALLGEM:NONE:INORGANIC:GEM_OF_KNOWLEDGE:NONE]"
            if target in txt:
                count = txt.count(target)
                new_txt = txt.replace(target, revert_to)
                rf.write_text(new_txt)
                dir_reverted += count
        total_reverted += dir_reverted
        print(f"Reverted BetterUniversity reaction fix in: {d} ({dir_reverted} tokens reverted)")

    return True

def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "--status"
    frozen, reason = is_frozen()

    if cmd == "--apply":
        if not apply_patch():
            sys.exit(1)
    elif cmd == "--unapply":
        if not unapply_patch():
            sys.exit(1)
    elif cmd == "--status":
        if frozen:
            print(f"Status: frozen ({reason})")
        elif is_patched():
            print("Status: patched (all 133 reagent tokens fixed to 6-element syntax)")
        else:
            print("Status: unpatched (contains 133 broken 7-token reagents causing SIGSEGV on Labor screen)")
    else:
        print(f"Unknown command: {cmd}. Usage: {sys.argv[0]} [--apply|--unapply|--status]")
        sys.exit(1)

if __name__ == "__main__":
    main()
