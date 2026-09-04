# Amywebbskii Scripts

Curated collection of DFHack quality-of-life scripts, embark inspectors, and fortress survival tools authored by **amywebbskii**.

Published as a unified Steam Workshop mod and standalone DFHack script repository. When subscribed on Steam Workshop or installed locally, all scripts activate automatically in Dwarf Fortress without requiring manual file placement or compilation.

---

## Included Tools & Features

### 1. **Embark Neighbors** (`neighbors` / `embark-neighbors`)
- An interactive, movable GUI table displayed on the fortress embark screen (`choose_start_site`).
- Shows live, slice-calculated local embark population (`pop: ~40`), origin civilizations, accurate diplomatic hostility vs war states, site types (`town`, `hamlet`, `tower`), and real travel distances.

### 2. **Choose Your Hermit** (`choose_hermit` / `choose-your-hermit`)
- Launch a fortress with a chosen single dwarf from your starting seven.
- Select your favored craftsdwarf or survivor and cleanly dismiss the remaining six.

### 3. **Wagonless Hermit** (`hermit-no-wagon` / `wagonless_hermit`)
- Suppresses the starting wagon and excess draft livestock on embark.
- Perfect for wilderness survival, mountain hermitages, and austere solo starts.

### 4. **Claim Foreign Items** (`claim_foreign_items` / `claim-foreign-items`)
- Automatically or on-demand reclaims items dropped across the map by trade caravans, traveling mercenaries, or dead invaders.
- Run `claim_foreign_items --auto` to passively monitor and claim dropped foreign goods.

### 5. **Slow Digging** (`slow_digging` / `slow-digging`)
- Configurable mining speed regulator that scales dig duration.
- Gives fortress expansion deliberate pacing and architectural gravity.

### 6. **Early Sieges** (`objects/entity_early_sieges.txt`)
- Civilizations raw patch tuning hostile expansion, lower population/wealth thresholds, and early siege readiness.

### 7. **Leather Scaling (Brom's Leather Overhaul)** (`tools/patch_vanilla_leather.py` & in-game patch switch)
- **Based on**: mod [Leather output scales with creature size](https://steamcommunity.com/sharedfiles/filedetails/?id=2902752798) by **Brom** (Steam ID 2902752798).
- **Dependencies**: `Dwarf Fortress Core Vanilla Raws`
- **Mechanism**: Modifies `[MATERIAL_TEMPLATE:SKIN_TEMPLATE]` so creature skins yield size-proportional globs upon butchering, updating `[REACTION:TAN_A_HIDE]` and `[REACTION:MAKE_PARCHMENT]` to tan leather proportionally to animal mass.
- **Why Integrated into this Bundle**: In modern Dwarf Fortress versions, loading Brom's original mod via the standard Mod Manager causes a hard duplicate reaction crash at worldgen (`Duplicate Object: reaction TAN_A_HIDE; Offending mods are broms_leather, vanilla_reactions`) because the engine prohibits mod files from redefining core vanilla reactions. To eliminate the friction of manually editing game files and prevent Steam game updates from silently wiping changes, `amywebbskii-scripts` includes both a 1-click in-game patch toggle in the GUI switchboard and an automated build hook (`tools/patch_vanilla_leather.py` / `make install`).

### 8. **Core Vanilla & 3rd-Party Mod Patch Architecture**
- **Principle**: All modifications to core game files or 3rd-party Steam Workshop mods must **never** be loose, unrecorded file edits. They must be maintained as managed, reproducible patches inside `amywebbskii-scripts`:
  1. Source patch definitions stored in `raw_patches/` (e.g. `raw_patches/entity_vanilla_weight_boost.txt`).
  2. Idempotent Python patch utilities in `tools/` with `--apply`, `--unapply`, and `--status` options.
  3. Hooked into `Makefile` (`make install`, `make patch-weights`, `make patch-vanilla`).
  4. Exposed via the in-game switchboard GUI (`CUSTOM_T` / `amywebbskii-scripts`) with top-level `Dependencies:` validation preventing broken file execution if the target mod is missing.

---

## Interactive Switchboard GUI

Open the built-in switchboard at any time in-game via DFHack console or `gui/launcher`:

```text
amywebbskii-scripts
```

Displays active tool status, command names, detailed descriptions, and allows one-click tool execution.

---

## Installation & Deployment

### Steam Workshop
1. Subscribe to **Amywebbskii Scripts** on Steam Workshop.
2. Enable the mod in your World / Mod list or activate it globally.

### Manual / Local Install
Copy scripts to DFHack's script search path:
```bash
make install DF_DIR="/path/to/Dwarf Fortress"
```

---

## Author & License
- **Author**: amywebbskii
- **License**: MIT
