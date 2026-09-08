DF_DIR ?= /home/gargantua/games/steam/steamapps/common/Dwarf Fortress
DFHACK_DIR ?= $(DF_DIR)
B12_DIR ?= /home/gargantua/.local/share/Bay 12 Games/Dwarf Fortress

SCRIPTS_DIR = $(DFHACK_DIR)/dfhack-config/scripts
DOCS_SCRIPTS_DIR = /home/gargantua/docs/games/df/dfhack-config/scripts
LOCAL_MODS_DIR = $(B12_DIR)/mods/amywebbskii_scripts
INSTALLED_MODS_DIR = $(B12_DIR)/data/installed_mods/amywebbskii_scripts (2)
INSTALLED_MODS_DIR_V1 = $(B12_DIR)/data/installed_mods/amywebbskii_scripts (1)

UPLOAD_MODS_DIR = $(B12_DIR)/mods/mod_upload/amywebbskii_scripts

.PHONY: all install install-scripts install-mod install-all-patches patch-vanilla patch-velociraptor-speed patch-weights patch-kobold-name patch-kobold-weights patch-ha-weights patch-subraces-weights patch-lizardmen-gaits patch-ha-illithid-spawns patch-better-university status

all: status

status:
	@echo "amywebbskii scripts suite"
	@echo "  DF_DIR:         $(DF_DIR)"
	@echo "  Scripts:        $(SCRIPTS_DIR)"
	@echo "  Upload Mod:     $(UPLOAD_MODS_DIR)"
	@echo "  Local Mod:      $(LOCAL_MODS_DIR)"
	@echo "  Installed Mod:  $(INSTALLED_MODS_DIR)"
	@echo "  Installed V1:   $(INSTALLED_MODS_DIR_V1)"

install: install-scripts install-mod

install-all-patches: patch-vanilla patch-velociraptor-speed patch-weights patch-kobold-name patch-kobold-weights patch-ha-weights patch-subraces-weights patch-lizardmen-gaits patch-ha-illithid-spawns patch-better-university

install-scripts:
	@mkdir -p "$(SCRIPTS_DIR)"
	@cp -pv scripts/*.lua "$(SCRIPTS_DIR)/"
	@if [ -d "$(DOCS_SCRIPTS_DIR)" ] ; then cp -pv scripts/*.lua "$(DOCS_SCRIPTS_DIR)/" ; fi
	@echo "Scripts installed into $(SCRIPTS_DIR)"

install-mod:
	@mkdir -p "$(UPLOAD_MODS_DIR)"
	@cp -pv info.txt preview.png "$(UPLOAD_MODS_DIR)/"
	@mkdir -p "$(UPLOAD_MODS_DIR)/scripts_modactive" "$(UPLOAD_MODS_DIR)/scripts_modinstalled" "$(UPLOAD_MODS_DIR)/objects"
	@cp -pv scripts_modactive/*.lua "$(UPLOAD_MODS_DIR)/scripts_modactive/"
	@cp -pv scripts_modactive/*.lua "$(UPLOAD_MODS_DIR)/scripts_modinstalled/"
	@cp -pv objects/*.txt* "$(UPLOAD_MODS_DIR)/objects/" 2>/dev/null || true
	@if [ -d raw_patches ] ; then \
		mkdir -p "$(UPLOAD_MODS_DIR)/raw_patches" ; \
		cp -rpv raw_patches/* "$(UPLOAD_MODS_DIR)/raw_patches/" ; \
	fi
	@echo "Mod deployed to $(UPLOAD_MODS_DIR)"
	@if [ "$$(realpath -q "$(LOCAL_MODS_DIR)")" != "$$(realpath -q .)" ] ; then \
		mkdir -p "$(LOCAL_MODS_DIR)" ; \
		cp -pv info.txt preview.png "$(LOCAL_MODS_DIR)/" ; \
		mkdir -p "$(LOCAL_MODS_DIR)/scripts_modactive" "$(LOCAL_MODS_DIR)/scripts_modinstalled" "$(LOCAL_MODS_DIR)/objects" ; \
		cp -pv scripts_modactive/*.lua "$(LOCAL_MODS_DIR)/scripts_modactive/" ; \
		cp -pv scripts_modactive/*.lua "$(LOCAL_MODS_DIR)/scripts_modinstalled/" ; \
		cp -pv objects/*.txt* "$(LOCAL_MODS_DIR)/objects/" 2>/dev/null || true ; \
		if [ -d raw_patches ] ; then \
			mkdir -p "$(LOCAL_MODS_DIR)/raw_patches" ; \
			cp -rpv raw_patches/* "$(LOCAL_MODS_DIR)/raw_patches/" ; \
		fi ; \
		echo "Mod deployed to $(LOCAL_MODS_DIR)" ; \
	else \
		echo "Local mod dir is symlinked to repo, skipping self-copy" ; \
	fi
	@mkdir -p "$(INSTALLED_MODS_DIR)"
	@cp -pv info.txt preview.png "$(INSTALLED_MODS_DIR)/"
	@mkdir -p "$(INSTALLED_MODS_DIR)/scripts_modactive" "$(INSTALLED_MODS_DIR)/scripts_modinstalled" "$(INSTALLED_MODS_DIR)/objects"
	@cp -pv scripts_modactive/*.lua "$(INSTALLED_MODS_DIR)/scripts_modactive/"
	@cp -pv scripts_modactive/*.lua "$(INSTALLED_MODS_DIR)/scripts_modinstalled/"
	@cp -pv objects/*.txt* "$(INSTALLED_MODS_DIR)/objects/" 2>/dev/null || true
	@if [ -d raw_patches ] ; then \
		mkdir -p "$(INSTALLED_MODS_DIR)/raw_patches" ; \
		cp -rpv raw_patches/* "$(INSTALLED_MODS_DIR)/raw_patches/" ; \
	fi
	@echo "Mod deployed to $(INSTALLED_MODS_DIR)"
	@mkdir -p "$(INSTALLED_MODS_DIR_V1)"
	@cp -pv info.txt preview.png "$(INSTALLED_MODS_DIR_V1)/"
	@mkdir -p "$(INSTALLED_MODS_DIR_V1)/scripts_modactive" "$(INSTALLED_MODS_DIR_V1)/scripts_modinstalled" "$(INSTALLED_MODS_DIR_V1)/objects"
	@cp -pv scripts_modactive/*.lua "$(INSTALLED_MODS_DIR_V1)/scripts_modactive/"
	@cp -pv scripts_modactive/*.lua "$(INSTALLED_MODS_DIR_V1)/scripts_modinstalled/"
	@cp -pv objects/*.txt* "$(INSTALLED_MODS_DIR_V1)/objects/" 2>/dev/null || true
	@if [ -d raw_patches ] ; then \
		mkdir -p "$(INSTALLED_MODS_DIR_V1)/raw_patches" ; \
		cp -rpv raw_patches/* "$(INSTALLED_MODS_DIR_V1)/raw_patches/" ; \
	fi
	@echo "Mod deployed to $(INSTALLED_MODS_DIR_V1)"

patch-vanilla:
	@python3 tools/patch_vanilla_leather.py "$(DF_DIR)"

patch-velociraptor-speed:
	@python3 tools/patch_vanilla_velociraptor_speed.py --apply "$(DF_DIR)"

patch-weights:
	@python3 tools/patch_animal_people_weights.py

patch-kobold-name:
	@python3 tools/patch_vanilla_kobold_name.py --apply

patch-kobold-weights:
	@python3 tools/patch_5e_kobold_weights.py --apply
	@python3 tools/patch_intros_kobold_weights.py --apply

patch-ha-weights:
	@python3 tools/patch_high_adventure_weights.py --apply

patch-subraces-weights:
	@python3 tools/patch_dark_elves_weights.py --apply
	@python3 tools/patch_high_elves_weights.py --apply
	@python3 tools/patch_duergar_weights.py --apply
	@python3 tools/patch_hobgoblins_weights.py --apply
	@python3 tools/patch_halflings_weights.py --apply
	@python3 tools/patch_lizardmen_weights.py --apply
	@python3 tools/patch_gnolls_weights.py --apply
	@python3 tools/patch_ratfolk_weights.py --apply
	@python3 tools/patch_valkyries_weights.py --apply
	@python3 tools/patch_ixthid_weights.py --apply
	@python3 tools/patch_crundlekin_weights.py --apply
	@python3 tools/patch_lupines_weights.py --apply
	@python3 tools/patch_avians_weights.py --apply
	@python3 tools/patch_mau_weights.py --apply
	@python3 tools/patch_nillians_weights.py --apply
	@python3 tools/patch_trolls_weights.py --apply

patch-lizardmen-gaits:
	@python3 tools/patch_lizardmen_gaits.py --apply

patch-ha-illithid-spawns:
	@python3 tools/patch_ha_illithid_spawns.py --apply

patch-better-university:
	@python3 tools/patch_better_university_reactions.py --apply

