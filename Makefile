DF_DIR ?= /home/gargantua/games/steam/steamapps/common/Dwarf Fortress
DFHACK_DIR ?= $(DF_DIR)
B12_DIR ?= /home/gargantua/.local/share/Bay 12 Games/Dwarf Fortress

SCRIPTS_DIR = $(DFHACK_DIR)/dfhack-config/scripts
LOCAL_MODS_DIR = $(B12_DIR)/mods/amywebbskii_scripts

.PHONY: all install install-scripts install-mod status

all: status

status:
	@echo "Amywebbskii Scripts Suite"
	@echo "  DF_DIR:     $(DF_DIR)"
	@echo "  Scripts:    $(SCRIPTS_DIR)"
	@echo "  Local Mod:  $(LOCAL_MODS_DIR)"

install: install-scripts install-mod

install-scripts:
	@mkdir -p "$(SCRIPTS_DIR)"
	@cp -pv scripts/*.lua "$(SCRIPTS_DIR)/"
	@echo "Scripts installed into $(SCRIPTS_DIR)"

install-mod:
	@mkdir -p "$(LOCAL_MODS_DIR)"
	@cp -pv info.txt preview.png "$(LOCAL_MODS_DIR)/"
	@mkdir -p "$(LOCAL_MODS_DIR)/scripts_modactive" "$(LOCAL_MODS_DIR)/objects"
	@cp -pv scripts_modactive/*.lua "$(LOCAL_MODS_DIR)/scripts_modactive/"
	@cp -pv objects/*.txt "$(LOCAL_MODS_DIR)/objects/"
	@echo "Mod deployed to $(LOCAL_MODS_DIR)"
