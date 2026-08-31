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

### 6. **Instant Sieges** (`objects/entity_instant_sieges.txt`)
- Civilizations raw patch tuning hostile expansion and immediate siege readiness.

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
