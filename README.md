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
- Civilizations raw patch tuning hostile expansion, lower population/wealth thresholds, and early siege readiness:
  - **Tier 0 (Ambush 0, Siege 0)**: Sinister & apex predatory races (goblins, kobolds, orcs, dark dwarves, drow, dark cultists, succubi, warlocks, trolls, ogres, gnolls, ratfolk, carnivore predators).
  - **Tier 1 (Ambush 0, Siege 0)**: Standard militaristic & expansionist civilized races (dwarves, humans, elves, duergar, halflings, illithids, lizardmen, avians, valkyries, lupines, dragon men, molemarians, troglodytes) configured with zero population/wealth triggers for solo hermit compatibility.
  - **Exceptions (Native Triggers Retained)**: Benign, gentle herbivore, or peaceful races (small mammal/hamster-people, invertebrate/butterfly-people, cat-people/Mau, ungulate/deer-people, snail-people, forest golems, nillians, etc.) are omitted to leave their vanilla/mod-defined `pop_siege` untouched.

### 7. **Leather Scaling (Brom's Leather Overhaul)** (`tools/patch_vanilla_leather.py` & in-game patch switch)
- **Based on**: mod [Leather output scales with creature size](https://steamcommunity.com/sharedfiles/filedetails/?id=2902752798) by **Brom** (Steam ID 2902752798).
- **Dependencies**: `Dwarf Fortress Core Vanilla Raws`
- **Mechanism**: Modifies `[MATERIAL_TEMPLATE:SKIN_TEMPLATE]` so creature skins yield size-proportional globs upon butchering, updating `[REACTION:TAN_A_HIDE]` and `[REACTION:MAKE_PARCHMENT]` to tan leather proportionally to animal mass.
- **Why Integrated into this Bundle**: In modern Dwarf Fortress versions, loading Brom's original mod via the standard Mod Manager causes a hard duplicate reaction crash at worldgen (`Duplicate Object: reaction TAN_A_HIDE; Offending mods are broms_leather, vanilla_reactions`) because the engine prohibits mod files from redefining core vanilla reactions. To eliminate the friction of manually editing game files and prevent Steam game updates from silently wiping changes, `amywebbskii-scripts` includes both a 1-click in-game patch toggle in the GUI switchboard and an automated build hook (`tools/patch_vanilla_leather.py` / `make install`).

### 8. core vanilla & 3rd-party mod patch architecture

many great steam workshop mods and even base game files have small bugs, speed typos, crash-causing errors, or world generation imbalances (like custom races never founding kingdoms because the game's spawn math ignores them). instead of editing game files by hand and losing your changes whenever steam updates dwarf fortress, this suite provides safe, one-click fixes directly through the in-game switchboard menu (`CUSTOM_T` / `amywebbskii-scripts`).

each fix can be toggled on or off individually, and automatically verifies that the required mod is actually installed before applying:

- **cheaty plant (harsh climate & populous worldgen)**: adds hardy frost crops and frost apple orchards across all biomes and caverns, stopping world generation from failing or rejecting worlds when generating cold, desolate, or extreme climates.
- **vanilla velociraptor walk speed fix**: fixes an old base game raw typo where velociraptor people crawled at 0.4 km/h instead of walking at normal humanoid speeds (4 km/h).
- **better university reaction crash fix**: fixes broken workshop reaction syntax in the popular *better university* mod that causes an instant crash to desktop whenever you open the labor screen.
- **vanilla kobold name restore**: restores the clean vanilla name "kobold" if custom kobold mods rename the base race to "cobald".
- **lizardman female & caste gaits fix**: restores full 8 km/h sprint and 5 km/h swimming speeds for female lizardfolk in *topples' lizardmen* after an upstream mod tag oversight left them without proper movement speeds.
- **core races weight boost (animal people balance)**: balances civilizations when using *all animal people civilized and playable*, ensuring standard fantasy kingdoms (dwarves, humans, elves, goblins, kobolds) aren't completely wiped out or crowded off the map by hundreds of beast nations.
- **playable mod race civilization weight boosts**: in standard world generation, custom modded races often fail to spawn kingdoms because vanilla races have much higher priority. these simple toggles give custom races equal footing to build towns, spread across the map, and interact as neighbors:
  - **high adventure**: boosts all 9 civilizations, including mountain/underdark cavern colonies and breeding fixes for illithids, plus golems and succubi.
  - **dark elves (dark elves redux)**: establishes strong subterranean dark elven realms.
  - **high elves & duergar (playable races revisioned)**: enables majestic high elven cities and deep duergar dwarven fortresses.
  - **hobgoblins**: allows organized hobgoblin empires to establish a solid world footprint.
  - **halflings (topples' halflings)**: ensures peaceful halfling shires and hamlets spawn across temperate lands.
  - **lizardmen (topples' lizardmen)**: gives cold-blooded swamp and marsh kingdoms an equal chance to flourish.
  - **kobolds (5e kobolds & intro's dragony kobolds)**: boosts small dragon-kin tribes into lasting world civilizations.
  - **gnolls, ratfolk, valkyries & ixthids (sm / forked series)**: allows these distinct playable races to found settlements and trade with you.
  - **crundlekin, lupines, avians, the mau (cat-people), nillians & playable trolls**: guarantees these unique fantasy races spawn in numbers and appear on your embark diplomacy screen.

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
