-- amywebbskii-scripts: interactive switchboard, auto-run manager, and qol utilities for dwarf fortress
--@module = true

local gui = require('gui')
local widgets = require('gui.widgets')
local json = require('json')

local CONFIG_PATH = 'dfhack-config/amywebbskii-scripts.json'
local INIT_PATH = dfhack.getDFPath() .. '/dfhack-config/init/onMapLoad.init'

-- ---- path resolution helpers ------------------------------------------------
local function get_search_roots()
    local roots = {}
    local home = os.getenv('HOME')
    if home then
        table.insert(roots, home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods')
        table.insert(roots, home .. '/.local/share/Bay 12 Games/Dwarf Fortress/mods')
        table.insert(roots, home .. '/games/steam/steamapps/workshop/content/975370')
    end
    local df_p = dfhack.getDFPath()
    table.insert(roots, df_p .. '/data/installed_mods')
    table.insert(roots, df_p .. '/mods')
    return roots
end

local function find_mod_objects_dir(target_keyword)
    local roots = get_search_roots()
    local candidates = {
        'all_animal_people_civilized_and_playable (9)/objects',
        'all_animal_people_civilized_and_playable/objects',
        '3412625442/objects',
    }
    for _, root in ipairs(roots) do
        for _, c in ipairs(candidates) do
            local p = root .. '/' .. c
            local f = io.open(p .. '/item_size_patch.txt', 'r') or io.open(p .. '/c_variation_universal_animal_person_entity_preparations.txt', 'r')
            if f then
                f:close()
                return p
            end
        end
    end
    return nil
end

-- ---- vanilla raw patch helpers (brom's leather overhaul) --------------------
local function get_vanilla_mat_path()
    return dfhack.getDFPath() .. '/data/vanilla/vanilla_materials/objects/material_template_default.txt'
end

local function get_vanilla_react_path()
    return dfhack.getDFPath() .. '/data/vanilla/vanilla_reactions/objects/reaction_other.txt'
end

local function is_leather_target_installed()
    local f = io.open(get_vanilla_mat_path(), 'r')
    if f then
        f:close()
        return true
    end
    return false
end

local function is_leather_patched()
    local f = io.open(get_vanilla_mat_path(), 'r')
    if not f then return false end
    local content = f:read('*a')
    f:close()
    return content:find('%[STOCKPILE_GLOB%]') ~= nil
end

local function set_leather_patch(enable)
    local mat_p = get_vanilla_mat_path()
    local react_p = get_vanilla_react_path()

    -- 1. materials
    local f = io.open(mat_p, 'r')
    if not f then return false, 'cannot open ' .. mat_p end
    local mtext = f:read('*a')
    f:close()

    if enable then
        if not mtext:find('%[STOCKPILE_GLOB%]') then
            local repl = '[ROTS]\n\t[STOCKPILE_GLOB]\n\t[DO_NOT_CLEAN_GLOB]\n\t[BUTCHER_SPECIAL:GLOB:NONE]\n\t[REACTION_CLASS:SKIN]'
            local s_idx = mtext:find('%[MATERIAL_TEMPLATE:SKIN_TEMPLATE%]')
            if s_idx then
                local r_idx = mtext:find('%[ROTS%]', s_idx)
                if r_idx and r_idx < s_idx + 2000 then
                    mtext = mtext:sub(1, r_idx - 1) .. repl .. mtext:sub(r_idx + 6)
                    local out = io.open(mat_p, 'w')
                    if out then out:write(mtext); out:close() end
                end
            end
        end
    else
        mtext = mtext:gsub('%s*%[STOCKPILE_GLOB%]', '')
        mtext = mtext:gsub('%s*%[DO_NOT_CLEAN_GLOB%]', '')
        mtext = mtext:gsub('%s*%[BUTCHER_SPECIAL:GLOB:NONE%]', '')
        mtext = mtext:gsub('%s*%[REACTION_CLASS:SKIN%]', '')
        local out = io.open(mat_p, 'w')
        if out then out:write(mtext); out:close() end
    end

    -- 2. reactions
    local rf = io.open(react_p, 'r')
    if not rf then return false, 'cannot open ' .. react_p end
    local rtext = rf:read('*a')
    rf:close()

    if enable then
        -- 2a. TAN_A_HIDE: convert to 375 glob reagent
        rtext = rtext:gsub('(%[REACTION:TAN_A_HIDE%].-%[BUILDING:TANNER:CUSTOM_T%]\n\t)%[REAGENT:A:1:NONE:NONE:NONE:NONE%]%[USE_BODY_COMPONENT%]%[UNROTTEN%]', '%1[REAGENT:A:375:GLOB:NONE:NONE:NONE][REACTION_CLASS:SKIN][UNROTTEN]')
        -- 2b. MAKE_PARCHMENT: convert to REACTION_CLASS:SKIN
        rtext = rtext:gsub('(%[REACTION:MAKE_PARCHMENT%].-%[BUILDING:TANNER:CUSTOM_P%]\n\t)%[REAGENT:A:1:NONE:NONE:NONE:NONE%]%[USE_BODY_COMPONENT%]%[UNROTTEN%]', '%1[REAGENT:A:1:NONE:NONE:NONE:NONE][REACTION_CLASS:SKIN][UNROTTEN]')
    else
        rtext = rtext:gsub('(%[REACTION:TAN_A_HIDE%].-%[BUILDING:TANNER:CUSTOM_T%]\n\t)%[REAGENT:A:375:GLOB:NONE:NONE:NONE%]%[REACTION_CLASS:SKIN%]%[UNROTTEN%]', '%1[REAGENT:A:1:NONE:NONE:NONE:NONE][USE_BODY_COMPONENT][UNROTTEN]')
        rtext = rtext:gsub('(%[REACTION:MAKE_PARCHMENT%].-%[BUILDING:TANNER:CUSTOM_P%]\n\t)%[REAGENT:A:1:NONE:NONE:NONE:NONE%]%[REACTION_CLASS:SKIN%]%[UNROTTEN%]', '%1[REAGENT:A:1:NONE:NONE:NONE:NONE][USE_BODY_COMPONENT][UNROTTEN]')
    end
    local rout = io.open(react_p, 'w')
    if rout then rout:write(rtext); rout:close() end

    return true
end

-- ---- vanilla velociraptor walk speed patch helpers -------------------------
local function get_vanilla_cretaceous_path()
    return dfhack.getDFPath() .. '/data/vanilla/vanilla_creatures_extinct/objects/creature_cretaceous.txt'
end

local function is_velociraptor_speed_installed()
    local f = io.open(get_vanilla_cretaceous_path(), 'r')
    if f then
        f:close()
        return true
    end
    return false
end

local function is_velociraptor_speed_patched()
    local f = io.open(get_vanilla_cretaceous_path(), 'r')
    if not f then return false end
    local content = f:read('*a')
    f:close()
    return content:find('%[APPLY_CREATURE_VARIATION:STANDARD_BIPED_GAITS:900:375:250:125:1900:2900%]') ~= nil
end

local function set_velociraptor_speed_patch(enable)
    local p = get_vanilla_cretaceous_path()
    local f = io.open(p, 'r')
    if not f then return false, 'cannot open ' .. p end
    local txt = f:read('*a')
    f:close()

    if enable then
        txt = txt:gsub('%[APPLY_CREATURE_VARIATION:STANDARD_BIPED_GAITS:9900:375:250:125:1900:2900%]', '[APPLY_CREATURE_VARIATION:STANDARD_BIPED_GAITS:900:375:250:125:1900:2900]')
    else
        txt = txt:gsub('%[APPLY_CREATURE_VARIATION:STANDARD_BIPED_GAITS:900:375:250:125:1900:2900%]', '[APPLY_CREATURE_VARIATION:STANDARD_BIPED_GAITS:9900:375:250:125:1900:2900]')
    end

    local out = io.open(p, 'w')
    if not out then return false, 'cannot write ' .. p end
    out:write(txt)
    out:close()
    return true
end

-- ---- mod patch helpers (kobold civ diversity & weight boost) ----------------
local function get_raw_patches_dir()
    local home = os.getenv('HOME')
    if not home then return nil end
    local p = home .. '/docs/games/df/amywebbskii-scripts/raw_patches'
    local f = io.open(p .. '/entity_vanilla_weight_boost.txt', 'r')
    if f then
        f:close()
        return p
    end
    return nil
end

local function copy_file(src, dst)
    local inf = io.open(src, 'rb')
    if not inf then return false, 'cannot open source: ' .. tostring(src) end
    local data = inf:read('*a')
    inf:close()
    local outf = io.open(dst, 'wb')
    if not outf then return false, 'cannot open destination: ' .. tostring(dst) end
    outf:write(data)
    outf:close()
    return true
end

local function is_kobold_target_installed()
    return find_mod_objects_dir('animal_people') ~= nil
end

local function is_kobold_patch_active()
    local obj_dir = find_mod_objects_dir('animal_people')
    if not obj_dir then return false end
    local f = io.open(obj_dir .. '/entity_vanilla_weight_boost.txt', 'r')
    if f then
        f:close()
        return true
    end
    return false
end

local function set_kobold_patch(enable)
    local obj_dir = find_mod_objects_dir('animal_people')
    if not obj_dir then return false, 'all_animal_people_civilized_and_playable mod directory not found' end
    local target_file = obj_dir .. '/entity_vanilla_weight_boost.txt'

    if enable then
        local raw_dir = get_raw_patches_dir()
        if not raw_dir then return false, 'source patch backup not found in raw_patches/' end
        local ok, err = copy_file(raw_dir .. '/entity_vanilla_weight_boost.txt', target_file)
        if not ok then return false, err end
    else
        os.remove(target_file)
    end
    return true
end

local function get_kobold_name_targets()
    local home = os.getenv('HOME')
    if not home then return {} end
    return {
        home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/dnd_kobold_race (51)/objects/creature_5e_kobold.txt',
        home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/dnd_kobold_race (1)/objects/creature_5e_kobold.txt',
        home .. '/games/steam/steamapps/workshop/content/975370/3281525928/objects/creature_5e_kobold.txt',
        home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/intros_kobolds (21)/objects/creature_kobold.txt',
        home .. '/games/steam/steamapps/workshop/content/975370/2902807802/objects/creature_kobold.txt',
    }
end

local function is_vanilla_kobold_name_installed()
    for _, p in ipairs(get_kobold_name_targets()) do
        local f = io.open(p, 'r')
        if f then f:close() ; return true end
    end
    return false
end

local function is_vanilla_kobold_name_active()
    for _, p in ipairs(get_kobold_name_targets()) do
        local f = io.open(p, 'r')
        if f then
            local txt = f:read('*a')
            f:close()
            if txt:find('%[NAME:cobald:cobalds:cobald%]') or txt:find('%[CASTE_NAME:cobald:cobalds:cobald%]') then
                return false
            end
        end
    end
    return true
end

local function set_vanilla_kobold_name(enable)
    for _, p in ipairs(get_kobold_name_targets()) do
        local f = io.open(p, 'r')
        if f then
            local txt = f:read('*a')
            f:close()
            if enable then
                txt = txt:gsub('%[NAME:cobald:cobalds:cobald%]', '[NAME:kobold:kobolds:kobold]')
                txt = txt:gsub('%[CASTE_NAME:cobald:cobalds:cobald%]', '[CASTE_NAME:kobold:kobolds:kobold]')
            else
                if txt:find('%[SELECT_CREATURE:KOBOLD%]') then
                    txt = txt:gsub('%[NAME:kobold:kobolds:kobold%]', '[NAME:cobald:cobalds:cobald]')
                    txt = txt:gsub('%[CASTE_NAME:kobold:kobolds:cobald%]', '[CASTE_NAME:cobald:cobalds:cobald]')
                end
            end
            local out = io.open(p, 'w')
            if out then
                out:write(txt)
                out:close()
            end
        end
    end
    return true
end

local function get_lizardmen_gaits_targets()
    local home = os.getenv('HOME')
    if not home then return {} end
    return {
        home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/topples_cv_lizardmen (212)/objects/creature_lizardman.txt',
        home .. '/.local/share/Bay 12 Games/Dwarf Fortress/mods/3022911723 (212)/objects/creature_lizardman.txt',
        home .. '/games/steam/steamapps/workshop/content/975370/3022911723/objects/creature_lizardman.txt',
        home .. '/games/steam/steamapps/common/Dwarf Fortress/data/installed_mods/topples_cv_lizardmen (212)/objects/creature_lizardman.txt',
    }
end

local function is_lizardmen_gaits_installed()
    for _, p in ipairs(get_lizardmen_gaits_targets()) do
        local f = io.open(p, 'r')
        if f then f:close() ; return true end
    end
    return false
end

local function is_lizardmen_gaits_active()
    for _, p in ipairs(get_lizardmen_gaits_targets()) do
        local f = io.open(p, 'r')
        if f then
            local txt = f:read('*a')
            f:close()
            if txt:find('%[SELECT_CASTE:ALL%]\n%s*%[APPLY_CREATURE_VARIATION:STANDARD_WALK_CRAWL_GAITS') then
                return true
            elseif txt:find('%[APPLY_CREATURE_VARIATION:STANDARD_WALK_CRAWL_GAITS') then
                return false
            end
        end
    end
    return false
end

local function set_lizardmen_gaits(enable)
    local target_gait = '[APPLY_CREATURE_VARIATION:STANDARD_WALK_CRAWL_GAITS:900:750:600:439:1900:2900] 20 kph'
    local patched_token = '[SELECT_CASTE:ALL]\n\t' .. target_gait

    for _, p in ipairs(get_lizardmen_gaits_targets()) do
        local f = io.open(p, 'r')
        if f then
            local txt = f:read('*a')
            f:close()
            if enable then
                if not txt:find('%[SELECT_CASTE:ALL%]\n%s*%[APPLY_CREATURE_VARIATION:STANDARD_WALK_CRAWL_GAITS') then
                    txt = txt:gsub('%[APPLY_CREATURE_VARIATION:STANDARD_WALK_CRAWL_GAITS:900:750:600:439:1900:2900%] 20 kph', patched_token)
                    local out = io.open(p, 'w')
                    if out then out:write(txt) ; out:close() end
                end
            else
                if txt:find('%[SELECT_CASTE:ALL%]\n%s*%[APPLY_CREATURE_VARIATION:STANDARD_WALK_CRAWL_GAITS') then
                    txt = txt:gsub('%[SELECT_CASTE:ALL%]\n%s*%[APPLY_CREATURE_VARIATION:STANDARD_WALK_CRAWL_GAITS:900:750:600:439:1900:2900%] 20 kph', target_gait)
                    local out = io.open(p, 'w')
                    if out then out:write(txt) ; out:close() end
                end
            end
        end
    end
    return true
end

-- ---- mod patch helpers (better university 7-token reaction fix) -------------
local function get_better_university_targets()
    local home = os.getenv('HOME')
    if not home then return {} end
    return {
        home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/BetterUniversity (4)',
        home .. '/.local/share/Bay 12 Games/Dwarf Fortress/mods/3525344907 (4)',
        home .. '/games/steam/steamapps/workshop/content/975370/3525344907',
        home .. '/games/steam/steamapps/common/Dwarf Fortress/data/installed_mods/BetterUniversity (4)',
    }
end

local function is_better_university_installed()
    for _, d in ipairs(get_better_university_targets()) do
        local f = io.open(d .. '/info.txt', 'r')
        if f then f:close() ; return true end
    end
    return false
end

local function get_better_university_version()
    local max_ver = 0
    for _, d in ipairs(get_better_university_targets()) do
        local f = io.open(d .. '/info.txt', 'r')
        if f then
            for line in f:lines() do
                local ver = line:match('%[NUMERIC_VERSION:(%d+)%]')
                if ver then
                    local n = tonumber(ver)
                    if n and n > max_ver then max_ver = n end
                end
            end
            f:close()
        end
    end
    return max_ver
end

local function is_better_university_frozen()
    local ver = get_better_university_version()
    return ver > 4
end

local function is_better_university_patched()
    local broken = ':GEM_OF_KNOWLEDGE:NONE]'
    local checked_any = false
    for _, d in ipairs(get_better_university_targets()) do
        local test_f = io.open(d .. '/objects/reaction_training_hall_axe.txt', 'r')
        if test_f then
            checked_any = true
            local txt = test_f:read('*a')
            test_f:close()
            if txt:find(broken, 1, true) then return false end
        end
    end
    return checked_any
end

local function set_better_university_patch(enable)
    if is_better_university_frozen() then
        return false, 'upstream version > 4; patch is frozen and locked pending manual review'
    end
    local home = os.getenv('HOME')
    if not home then return false, 'home directory not found' end
    local script_p = home .. '/docs/games/df/amywebbskii-scripts/tools/patch_better_university_reactions.py'
    local flag = enable and '--apply' or '--unapply'
    local ret = os.execute(('python3 "%s" %s >/dev/null 2>&1'):format(script_p, flag))
    if ret == 0 or ret == true then
        return true
    end
    return false, 'patch script exited with error'
end

local function get_amy_bundle_objects_dirs()
    local home = os.getenv('HOME')
    local dirs = {}
    if home then
        table.insert(dirs, home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/amywebbskii_scripts (1)/objects')
        table.insert(dirs, home .. '/.local/share/Bay 12 Games/Dwarf Fortress/mods/amywebbskii_scripts/objects')
        table.insert(dirs, home .. '/docs/games/df/amywebbskii-scripts/objects')
    end
    return dirs
end

local function is_amy_bundle_installed()
    local home = os.getenv('HOME')
    if not home then return false end
    local p1 = home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/amywebbskii_scripts (1)/info.txt'
    local p2 = home .. '/.local/share/Bay 12 Games/Dwarf Fortress/mods/amywebbskii_scripts/info.txt'
    local f1 = io.open(p1, 'r')
    if f1 then f1:close() ; return true end
    local f2 = io.open(p2, 'r')
    if f2 then f2:close() ; return true end
    return false
end

local function is_bundle_module_active(raw_name)
    local home = os.getenv('HOME')
    if not home then return false end
    local primary = home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/amywebbskii_scripts (1)/objects/' .. raw_name
    local f = io.open(primary, 'r')
    if f then
        f:close()
        return true
    end
    local secondary = home .. '/.local/share/Bay 12 Games/Dwarf Fortress/mods/amywebbskii_scripts/objects/' .. raw_name
    local f2 = io.open(secondary, 'r')
    if f2 then
        f2:close()
        return true
    end
    local repo = home .. '/docs/games/df/amywebbskii-scripts/objects/' .. raw_name
    local f3 = io.open(repo, 'r')
    if f3 then
        f3:close()
        return true
    end
    return false
end

local function set_bundle_module(raw_name, enable)
    local home = os.getenv('HOME')
    if not home then return false, 'HOME environment variable not set' end
    local raw_dir = get_raw_patches_dir()
    local dirs = get_amy_bundle_objects_dirs()
    local success = false
    local err_msg = nil

    for _, dir in ipairs(dirs) do
        local active_path = dir .. '/' .. raw_name
        local disabled_path = dir .. '/' .. raw_name .. '.disabled'

        local test_f = io.open(dir .. '/../info.txt', 'r')
        if test_f then
            test_f:close()
            if enable then
                local f_dis = io.open(disabled_path, 'r')
                if f_dis then
                    f_dis:close()
                    os.remove(active_path)
                    os.rename(disabled_path, active_path)
                    success = true
                else
                    local f_act = io.open(active_path, 'r')
                    if f_act then
                        f_act:close()
                        success = true
                    elseif raw_dir then
                        local src = raw_dir .. '/' .. raw_name
                        local ok, err = copy_file(src, active_path)
                        if ok then
                            success = true
                        else
                            err_msg = err
                        end
                    end
                end
            else
                local f_act = io.open(active_path, 'r')
                if f_act then
                    f_act:close()
                    os.remove(disabled_path)
                    local ok = os.rename(active_path, disabled_path)
                    if not ok then
                        copy_file(active_path, disabled_path)
                        os.remove(active_path)
                    end
                    success = true
                else
                    success = true
                end
            end
        end
    end
    return success, err_msg
end

local function is_patch_file_present(mod_folders, file_name)
    local home = os.getenv('HOME')
    if not home then return false end
    local folders = type(mod_folders) == 'table' and mod_folders or {mod_folders}
    for _, folder in ipairs(folders) do
        local p = home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/' .. folder .. '/objects/' .. file_name
        local f = io.open(p, 'r')
        if f then
            f:close()
            return true
        end
    end
    return false
end

local function purge_ha_old_files()
    local home = os.getenv('HOME')
    if not home then return end
    local obj_dir = home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/HIGH_ADVENTURE (20)/objects/'
    os.remove(obj_dir .. 'entity_ha_kobold_weight_boost.txt')
    os.remove(obj_dir .. 'entity_second_humans_weight_boost.txt')
end

local function set_raw_patch_file(mod_folders, raw_name, enable)
    local home = os.getenv('HOME')
    if not home then return false, 'HOME environment variable not set' end
    local folders = type(mod_folders) == 'table' and mod_folders or {mod_folders}
    local success = false
    local err_msg = nil
    local raw_dir = get_raw_patches_dir()

    for _, folder in ipairs(folders) do
        local obj_dir = home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/' .. folder .. '/objects'
        local dst_file = obj_dir .. '/' .. raw_name
        if enable then
            if not raw_dir then return false, 'raw_patches directory not found' end
            local src_file = raw_dir .. '/' .. raw_name
            local ok, err = copy_file(src_file, dst_file)
            if ok then
                success = true
            else
                err_msg = err
            end
        else
            os.remove(dst_file)
            success = true
        end
    end
    return success, err_msg
end

local function make_weight_tool(key, name, mod_folders, raw_name, deps_name, desc_text)
    local folders = type(mod_folders) == 'table' and mod_folders or {mod_folders}
    return {
        key = key,
        name = name,
        category = 'raw patch',
        is_raw_patch = true,
        is_weight_boost = true,
        patch_type = 'mod patch',
        depends_on = deps_name,
        load_order = 'bottom / after deps',
        game_restart = 'required',
        new_world = 'required',
        check_installed = function()
            local home = os.getenv('HOME')
            if not home then return false end
            for _, folder in ipairs(folders) do
                local p = home .. '/.local/share/Bay 12 Games/Dwarf Fortress/data/installed_mods/' .. folder .. '/info.txt'
                local f = io.open(p, 'r')
                if f then f:close() ; return true end
            end
            return false
        end,
        desc = desc_text,
        get_status = function()
            return is_patch_file_present(folders, raw_name)
        end,
        toggle = function()
            local cur = is_patch_file_present(folders, raw_name)
            if key == 'ha-weights' then
                purge_ha_old_files()
                local home = os.getenv('HOME')
                if home then
                    local script_p = home .. '/docs/games/df/amywebbskii-scripts/tools/patch_ha_illithid_spawns.py'
                    local flag = (not cur) and '--apply' or '--unapply'
                    os.execute(('python3 "%s" %s >/dev/null 2>&1'):format(script_p, flag))
                end
            end
            local ok, err = set_raw_patch_file(folders, raw_name, not cur)
            if ok then
                local s = (not cur) and 'enabled (10x boost applied)' or 'disabled (boost removed)'
                print(('amywebbskii-scripts: %s %s. restart dwarf fortress to reload native raws.'):format(name, s))
            else
                dfhack.printerr(('amywebbskii-scripts: failed to toggle %s: %s'):format(name, tostring(err)))
            end
        end,
    }
end

local TOOLS = {
    {
        key = 'neighbors',
        name = 'neighbors',
        cmd = 'neighbors',
        category = 'dfhack script',
        patch_type = 'dfhack script',
        load_order = 'n/a',
        game_restart = 'not required',
        enable = function() end,
        disable = function() end,
        run = function()
            dfhack.run_command('neighbors')
        end,
    },
    {
        key = 'choose-hermit',
        name = 'choose hermit',
        cmd = 'choose-hermit',
        category = 'dfhack script',
        patch_type = 'dfhack script',
        load_order = 'n/a',
        game_restart = 'not required',
        new_world = 'required',
        desc = 'select a specific settler from your starting expedition to embark as a lone hermit, cleanly dismissing extra companions without relationship grief, baggage, or pop issues.',
        enable = function()
            if not dfhack.isMapLoaded() then return end
            pcall(dfhack.run_command, 'enable', 'hermit')
        end,
        disable = function()
            pcall(dfhack.run_command, 'disable', 'hermit')
        end,
        run = function()
            dfhack.run_command('choose-hermit')
        end,
    },
    {
        key = 'wagonless-hermit',
        name = 'wagonless hermit',
        cmd = 'wagonless-hermit',
        category = 'dfhack script',
        patch_type = 'dfhack script',
        load_order = 'n/a',
        game_restart = 'not required',
        new_world = 'required',
        desc = 'suppresses the embark wagon, excess draft animals, and loose wood clutter for a true wilderness hermit survival experience.',
        enable = function()
            if not dfhack.isMapLoaded() then return end
            pcall(dfhack.run_command, 'wagonless-hermit')
        end,
        disable = function() end,
        run = function()
            dfhack.run_command('wagonless-hermit')
        end,
    },
    {
        key = 'claim-foreign-items',
        name = 'claim foreign items',
        cmd = 'claim-foreign-items',
        category = 'dfhack script',
        patch_type = 'dfhack script',
        load_order = 'n/a',
        game_restart = 'not required',
        new_world = 'not required',
        desc = 'automatically or manually reclaims external items dropped by visiting caravans, merchants, and siegers.',
        enable = function()
            if not dfhack.isMapLoaded() then return end
            pcall(dfhack.run_command, 'claim-foreign-items', '--auto')
        end,
        disable = function()
            pcall(dfhack.run_command, 'claim-foreign-items', '--stop')
        end,
        run = function()
            dfhack.run_command('claim-foreign-items', '--force')
        end,
    },
    {
        key = 'slow-digging',
        name = 'slow digging',
        cmd = 'slow-digging',
        category = 'dfhack script',
        patch_type = 'dfhack script',
        load_order = 'n/a',
        game_restart = 'not required',
        new_world = 'not required',
        desc = 'slows down raw mining speed by a configurable multiplier to give fortress expansion deliberate pacing and architectural gravity.',
        enable = function()
            if not dfhack.isMapLoaded() then return end
            pcall(dfhack.run_command, 'enable', 'slow-digging')
        end,
        disable = function()
            pcall(dfhack.run_command, 'disable', 'slow-digging')
        end,
        run = function()
            dfhack.run_command('slow-digging')
        end,
    },
    {
        key = 'early-sieges',
        name = 'early sieges',
        category = 'bundle module',
        is_bundle_module = true,
        patch_type = 'bundle module',
        load_order = 'bottom (amywebbskii_scripts)',
        game_restart = 'not required',
        new_world = 'required',
        depends_on = 'amywebbskii scripts suite mod',
        check_installed = is_amy_bundle_installed,
        desc = 'packaged directly inside the amywebbskii scripts suite mod (objects/entity_early_sieges.txt).\n\nwhen enabled, dynamically adjusts population and wealth thresholds for ambushes and military sieges based on civilization aggression (tier 0 at 0 pop, tier 1 at 20 pop).\n\ntoggled via launcher tick. takes effect during world generation when amywebbskii scripts suite is active in the mod list.',
        get_status = function()
            return is_bundle_module_active('entity_early_sieges.txt')
        end,
        toggle = function()
            local cur = is_bundle_module_active('entity_early_sieges.txt')
            local ok, err = set_bundle_module('entity_early_sieges.txt', not cur)
            if ok then
                local s = (not cur) and 'enabled (module active in bundle)' or 'disabled (module removed from bundle)'
                print(('amywebbskii-scripts: early sieges %s. take effect on next worldgen.'):format(s))
            else
                dfhack.printerr(('amywebbskii-scripts: failed to toggle early sieges: %s'):format(tostring(err)))
            end
        end,
    },
    {
        key = 'cheaty-plant',
        name = 'cheaty plant allows populous harsh climate worldgen',
        category = 'bundle module',
        is_bundle_module = true,
        patch_type = 'bundle module',
        load_order = 'bottom (amywebbskii_scripts)',
        game_restart = 'not required',
        new_world = 'required',
        depends_on = 'amywebbskii scripts suite mod',
        check_installed = is_amy_bundle_installed,
        desc = 'packaged directly inside the amywebbskii scripts suite mod (objects/plant_cheaty_crop.txt).\n\nwhen enabled, provides standalone all-season frost bulb (underground & surface shrub yielding edible bulbs, seeds, and frost beer) and frost orchard (fruit tree bearing white frost apples and cider) across all biomes and subterranean depths 1-3 with frequency 1, resolving agriculture and orchard placement worldgen rejections without modifying vanilla plants or diluting crop pools.\n\ntoggled via launcher tick. takes effect during world generation when amywebbskii scripts suite is active in the mod list.',
        get_status = function()
            return is_bundle_module_active('plant_cheaty_crop.txt')
        end,
        toggle = function()
            local cur = is_bundle_module_active('plant_cheaty_crop.txt')
            local ok, err = set_bundle_module('plant_cheaty_crop.txt', not cur)
            if ok then
                local s = (not cur) and 'enabled (module active in bundle)' or 'disabled (module removed from bundle)'
                print(('amywebbskii-scripts: cheaty plant %s. take effect on next worldgen.'):format(s))
            else
                dfhack.printerr(('amywebbskii-scripts: failed to toggle cheaty plant: %s'):format(tostring(err)))
            end
        end,
    },
    {
        key = 'leather-scaling',
        name = 'leather scaling (broms)',
        category = 'raw patch',
        is_raw_patch = true,
        patch_type = 'core vanilla patch',
        depends_on = 'df core vanilla raws',
        load_order = 'n/a',
        game_restart = 'required',
        new_world = 'not required',
        check_installed = is_leather_target_installed,
        desc = 'based on: mod "leather output scales with creature size" by brom (steam id 2902752798).\n\nscales butchered creature leather and parchment outputs to body size (globs). modifies core vanilla raw files (material_template_default.txt and reaction_other.txt).',
        get_status = is_leather_patched,
        toggle = function()
            if not is_leather_target_installed() then
                dfhack.printerr('amywebbskii-scripts: cannot toggle patch — core vanilla files not found.')
                return
            end
            local cur = is_leather_patched()
            local ok, err = set_leather_patch(not cur)
            if ok then
                local state_str = (not cur) and 'enabled (applied to vanilla raws)' or 'disabled (restored vanilla raws)'
                print(('amywebbskii-scripts: leather-scaling %s. restart dwarf fortress to reload native raws.'):format(state_str))
            else
                dfhack.printerr(('amywebbskii-scripts: failed to patch vanilla files: %s'):format(tostring(err)))
            end
        end,
    },
    {
        key = 'vanilla-velociraptor-speed',
        name = 'vanilla velociraptor walk speed',
        category = 'raw patch',
        is_raw_patch = true,
        patch_type = 'core vanilla patch',
        depends_on = 'df core vanilla raws',
        load_order = 'n/a',
        game_restart = 'required',
        new_world = 'not required',
        check_installed = is_velociraptor_speed_installed,
        desc = 'fixes the vanilla raw typo for velociraptor man walk speed in creature_cretaceous.txt (replaces 0.4 km/h with 4 km/h standard biped walk).',
        get_status = is_velociraptor_speed_patched,
        toggle = function()
            if not is_velociraptor_speed_installed() then
                dfhack.printerr('amywebbskii-scripts: cannot toggle patch — creature_cretaceous.txt not found.')
                return
            end
            local cur = is_velociraptor_speed_patched()
            local ok, err = set_velociraptor_speed_patch(not cur)
            if ok then
                local state_str = (not cur) and 'enabled (fixed walk speed to 900 ticks / 4 km/h)' or 'disabled (restored vanilla 9900 ticks typo)'
                print(('amywebbskii-scripts: velociraptor walk speed %s. restart dwarf fortress to reload native raws.'):format(state_str))
            else
                dfhack.printerr(('amywebbskii-scripts: failed to patch velociraptor speed: %s'):format(tostring(err)))
            end
        end,
    },
    {
        key = 'core-races-weights',
        name = 'core races weight boost',
        category = 'raw patch',
        is_raw_patch = true,
        is_weight_boost = true,
        patch_type = 'mod patch',
        depends_on = 'all_animal_people_civilized_and_playable',
        load_order = 'bottom / after deps',
        game_restart = 'required',
        new_world = 'required',
        check_installed = is_kobold_target_installed,
        desc = 'multiplies spawn weight of core races (dwarves, humans, elves, goblins, kobolds) by 10x inside the animal people mod to prevent hundreds of beast civilizations from crowding out core civilizations during world generation.',
        get_status = is_kobold_patch_active,
        toggle = function()
            if not is_kobold_target_installed() then
                dfhack.printerr('amywebbskii-scripts: cannot toggle patch — target mod "all_animal_people_civilized_and_playable" is not installed.')
                return
            end
            local cur = is_kobold_patch_active()
            local ok, err = set_kobold_patch(not cur)
            if ok then
                local state_str = (not cur) and 'enabled (applied to mod raws)' or 'disabled (restored original raws)'
                print(('amywebbskii-scripts: core races weight boost %s. restart dwarf fortress to reload native raws.'):format(state_str))
            else
                dfhack.printerr(('amywebbskii-scripts: failed to patch mod files: %s'):format(tostring(err)))
            end
        end,
    },
    {
        key = 'vanilla-kobold-name',
        name = 'vanilla kobold name',
        category = 'raw patch',
        is_raw_patch = true,
        patch_type = 'mod patch',
        depends_on = 'dnd_kobold_race, intros_kobolds',
        load_order = 'bottom / after deps',
        game_restart = 'required',
        new_world = 'not required',
        check_installed = is_vanilla_kobold_name_installed,
        desc = 'restores the clean vanilla "kobold" name for base kobolds by reverting the "cobald" rename in dnd_kobold_race and intros_kobolds.',
        get_status = is_vanilla_kobold_name_active,
        toggle = function()
            local cur = is_vanilla_kobold_name_active()
            local ok = set_vanilla_kobold_name(not cur)
            if ok then
                local s = (not cur) and 'enabled (restored vanilla kobold name)' or 'disabled (restored custom cobald name)'
                print(('amywebbskii-scripts: vanilla kobold name %s. restart dwarf fortress to reload native raws.'):format(s))
            else
                dfhack.printerr('amywebbskii-scripts: failed to update kobold names')
            end
        end,
    },
    {
        key = 'lizardmen-gaits',
        name = 'lizardman female & caste gaits',
        category = 'raw patch',
        is_raw_patch = true,
        patch_type = 'mod patch',
        depends_on = 'topples_cv_lizardmen',
        load_order = 'n/a',
        game_restart = 'required',
        new_world = 'not required',
        check_installed = is_lizardmen_gaits_installed,
        desc = 'fixes topples lizardmen raw bug where gaits were placed after male castes without select_caste:all, restoring 8 km/h sprint and 5 km/h innate swim to all female castes.',
        get_status = is_lizardmen_gaits_active,
        toggle = function()
            local cur = is_lizardmen_gaits_active()
            local ok = set_lizardmen_gaits(not cur)
            if ok then
                local s = (not cur) and 'enabled (restored select_caste:all before gaits for all castes)' or 'disabled (reverted to male-only gaits)'
                print(('amywebbskii-scripts: lizardman caste gaits %s. restart dwarf fortress to reload native raws.'):format(s))
            else
                dfhack.printerr('amywebbskii-scripts: failed to update lizardman gaits')
            end
        end,
    },
    {
        key = 'better-university-reactions',
        name = 'better university reaction crash fix',
        category = 'raw patch',
        is_raw_patch = true,
        patch_type = 'mod patch',
        depends_on = 'BetterUniversity (3525344907)',
        load_order = 'n/a',
        game_restart = 'required',
        new_world = 'not required',
        check_installed = is_better_university_installed,
        is_frozen = is_better_university_frozen,
        desc = 'fixes 133 malformed 7-token reagent definitions in better university (dated aug 2 2025, version 4) that crash dwarf fortress with sigsegv when opening the labor screen; locks and freezes automatically if upstream version > 4.',
        get_status = is_better_university_patched,
        toggle = function()
            if not is_better_university_installed() then
                dfhack.printerr('amywebbskii-scripts: cannot toggle patch — target mod "BetterUniversity" is not installed.')
                return
            end
            if is_better_university_frozen() then
                dfhack.printerr('amywebbskii-scripts: cannot toggle patch — upstream version > 4; patch is locked pending manual review.')
                return
            end
            local cur = is_better_university_patched()
            local ok, err = set_better_university_patch(not cur)
            if ok then
                local s = (not cur) and 'enabled (fixed 133 reagent tokens to 6-element syntax)' or 'disabled (reverted to 7-token syntax)'
                print(('amywebbskii-scripts: better university reaction fix %s. restart dwarf fortress to reload native raws.'):format(s))
            else
                dfhack.printerr(('amywebbskii-scripts: failed to toggle better university patch: %s'):format(tostring(err)))
            end
        end,
    },
    make_weight_tool('5e-kobold-weights', '5e kobold weight boost', {'dnd_kobold_race (51)', 'dnd_kobold_race (1)'}, 'entity_5e_kobold_weight_boost.txt', 'dnd_kobold_race', 'multiplies spawn weight of 5e kobolds by 10x with 9 duplicate civilization definitions (5e_kobold_civ_2..10) to give them equal worldgen standing alongside core civilizations.'),
    make_weight_tool('intros-kobold-weights', 'intro kobold weight boost', 'intros_kobolds (21)', 'entity_intros_kobold_weight_boost.txt', 'intros_kobolds', 'multiplies spawn weight of intro\'s dragony kobolds by 10x with 9 duplicate civilization definitions (dragony_2..10) to give them equal worldgen standing alongside core civilizations.'),
    make_weight_tool('ha-weights', 'high adventure weight boost', 'HIGH_ADVENTURE (20)', 'entity_high_adventure_weight_boost.txt', 'high_adventure', 'multiplies spawn weight of all 9 high adventure civilizations (15x for core races, 10x for illithids/golems/succubi) with duplicate civ definitions; bundles illithid mountain/underdark cave site fixes, expanded start biomes, and baby/child reproduction tokens so illithid colonies successfully spawn and breed in worldgen.'),
    make_weight_tool('dark-elves-weights', 'dark elves weight boost', 'dark_elves_redux (6)', 'entity_dark_elves_weight_boost.txt', 'dark_elves_redux', 'multiplies spawn weight of dark elves by 15x (1.5x core modifier) with 14 duplicate civilization definitions to give them equal worldgen standing alongside core civilizations.'),
    make_weight_tool('high-elves-weights', 'high elves weight boost', 'playable_races_revisioned (161)', 'entity_high_elves_weight_boost.txt', 'playable_races_revisioned', 'multiplies spawn weight of high elves by 15x (1.5x core modifier) with 14 duplicate civilization definitions to give them equal worldgen standing alongside core civilizations.'),
    make_weight_tool('duergar-weights', 'duergar weight boost', 'playable_races_revisioned (161)', 'entity_duergar_weight_boost.txt', 'playable_races_revisioned', 'multiplies spawn weight of duergar deep dwarves by 15x (1.5x core modifier) with 14 duplicate civilization definitions to give them equal worldgen standing alongside core civilizations.'),
    make_weight_tool('hobgoblins-weights', 'hobgoblin weight boost', 'hobgoblins (191)', 'entity_hobgoblins_weight_boost.txt', 'hobgoblins', 'multiplies spawn weight of hobgoblins by 15x (1.5x core modifier) with 14 duplicate civilization definitions to give them equal worldgen standing alongside core civilizations.'),
    make_weight_tool('halflings-weights', 'halfling weight boost', 'topples_cv_halfling (218)', 'entity_halflings_weight_boost.txt', 'topples_cv_halfling', 'multiplies spawn weight of topples halflings by 15x (1.5x core modifier) with 14 duplicate civilization definitions to give them equal worldgen standing alongside core civilizations.'),
    make_weight_tool('lizardmen-weights', 'lizardman weight boost', 'topples_cv_lizardmen (212)', 'entity_lizardmen_weight_boost.txt', 'topples_cv_lizardmen', 'multiplies spawn weight of topples lizardmen by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
    make_weight_tool('gnolls-weights', 'gnoll weight boost', 'sm_cv_gnoll (3)', 'entity_gnolls_weight_boost.txt', 'sm_cv_gnoll', 'multiplies spawn weight of gnolls by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
    make_weight_tool('ratfolk-weights', 'ratfolk weight boost', 'sm_cv_ratfolk (2)', 'entity_ratfolk_weight_boost.txt', 'sm_cv_ratfolk', 'multiplies spawn weight of ratfolk by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
    make_weight_tool('valkyries-weights', 'valkyrie weight boost', 'sm_cv_valkyrie (4)', 'entity_valkyries_weight_boost.txt', 'sm_cv_valkyrie', 'multiplies spawn weight of valkyries by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
    make_weight_tool('ixthid-weights', 'ixthid weight boost', 'sm_cv_ixthid_forked (3)', 'entity_ixthid_weight_boost.txt', 'sm_cv_ixthid_forked', 'multiplies spawn weight of ixthid by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
    make_weight_tool('crundlekin-weights', 'crundlekin weight boost', 'Crund (1000)', 'entity_crundlekin_weight_boost.txt', 'Crund', 'multiplies spawn weight of crundlekin by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
    make_weight_tool('lupines-weights', 'lupine weight boost', 'gavins_lupine_mod (3)', 'entity_lupines_weight_boost.txt', 'gavins_lupine_mod', 'multiplies spawn weight of lupines by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
    make_weight_tool('avians-weights', 'avian weight boost', 'appw_avians (10)', 'entity_avians_weight_boost.txt', 'appw_avians', 'multiplies spawn weight of avians by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
    make_weight_tool('mau-weights', 'mau weight boost', 'the_mau (1)', 'entity_mau_weight_boost.txt', 'the_mau', 'multiplies spawn weight of mau by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
    make_weight_tool('nillians-weights', 'nillian weight boost', 'nillians (105)', 'entity_nillians_weight_boost.txt', 'nillians', 'multiplies spawn weight of nillians by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
    make_weight_tool('trolls-weights', 'playable troll weight boost', 'playable_trolls (1)', 'entity_trolls_weight_boost.txt', 'playable_trolls', 'multiplies spawn weight of playable trolls by 10x with 9 duplicate civilization definitions to give them equal worldgen standing alongside other playable races.'),
}

-- ---- configuration & persistence --------------------------------------------
local function load_config()
    local cfg = json.open(CONFIG_PATH)
    if not cfg.data or type(cfg.data) ~= 'table' then
        cfg.data = {}
    end
    for _, t in ipairs(TOOLS) do
        if cfg.data[t.key] == nil then
            if t.check_installed and not t.check_installed() then
                cfg.data[t.key] = false
            else
                cfg.data[t.key] = true
            end
        end
    end
    return cfg
end

local function is_on(key)
    local cfg = load_config()
    return cfg.data[key] == true
end

local function set_on(key, enabled)
    local cfg = load_config()
    cfg.data[key] = enabled and true or false
    cfg:write()
end

local function set_autostart(arm)
    local lines = {}
    local f = io.open(INIT_PATH, 'r')
    if f then
        for line in f:lines() do
            if not line:match('^%s*amywebbskii%-scripts') then
                lines[#lines + 1] = line
            end
        end
        f:close()
    end
    if arm then
        lines[#lines + 1] = 'amywebbskii-scripts apply'
    end
    local w = io.open(INIT_PATH, 'w')
    if not w then return false end
    w:write(table.concat(lines, '\n'))
    if #lines > 0 then w:write('\n') end
    w:close()
    return true
end

local function mode_active(m)
    if m == 'any' or m == 'embark' or m:find('embark') then return true end
    if m == 'dfhack script' then return true end
    if m == 'fort' then return dfhack.world.isFortressMode() and dfhack.isMapLoaded() end
    return true
end

local function apply_tool(tool)
    if tool.is_bundle_module or tool.is_raw_mod or tool.is_raw_patch then return end
    if tool.check_installed and not tool.check_installed() then return end
    if not mode_active(tool.category) then return end
    if is_on(tool.key) then
        if tool.enable then
            local ok, err = pcall(tool.enable)
            if not ok then print(('amywebbskii-scripts: enable error on %s: %s'):format(tool.name, tostring(err))) end
        end
    else
        if tool.disable then
            local ok, err = pcall(tool.disable)
            if not ok then print(('amywebbskii-scripts: disable error on %s: %s'):format(tool.name, tostring(err))) end
        end
    end
end

local function apply_all()
    for _, tool in ipairs(TOOLS) do
        apply_tool(tool)
    end
end

local function wrap_text(text, width)
    width = width or 70
    local lines = {}
    for paragraph in tostring(text):gmatch('[^\r\n]+') do
        local line = ''
        for word in paragraph:gmatch('%S+') do
            if #line == 0 then
                line = word
            elseif #line + 1 + #word <= width then
                line = line .. ' ' .. word
            else
                table.insert(lines, line)
                line = word
            end
        end
        if #line > 0 then
            table.insert(lines, line)
        end
    end
    return table.concat(lines, '\n')
end

-- ---- GUI --------------------------------------------------------------------
AmyWindow = defclass(AmyWindow, widgets.Window)
AmyWindow.ATTRS{
    frame_title = 'amywebbskii-scripts',
    frame = {w = 112, h = 30},
    resizable = true,
    resize_min = {w = 86, h = 24},
}

function AmyWindow:init()
    self.last_idx = 2
    self:addviews{
        widgets.Label{
            frame = {l = 0, t = 0},
            text = {
                {text = 'amywebbskii scripts suite', pen = COLOR_LIGHTCYAN},
                {text = '  (dfhack qol & fortress utilities)', pen = COLOR_DARKGREY},
            },
        },
        widgets.List{
            view_id = 'tool_list',
            frame = {l = 0, t = 2, w = 36, b = 2},
            on_select = function(idx, choice)
                if choice.is_header then
                    local list = self.subviews.tool_list
                    local dir = (self.last_idx and idx < self.last_idx) and -1 or 1
                    local next_idx = idx + dir
                    while list.choices[next_idx] and list.choices[next_idx].is_header do
                        next_idx = next_idx + dir
                    end
                    if next_idx < 1 then next_idx = 1 end
                    if next_idx > #list.choices then next_idx = #list.choices end
                    self.last_idx = next_idx
                    list:setSelected(next_idx)
                    return
                end
                self.last_idx = idx
                self:show_tool(choice.item)
            end,
        },
        widgets.Panel{
            frame = {l = 38, t = 2, r = 0, b = 2},
            subviews = {
                widgets.Label{
                    view_id = 'tool_title',
                    frame = {l = 0, t = 0},
                    text = '',
                },
                widgets.Label{
                    view_id = 'tool_meta',
                    frame = {l = 0, t = 2},
                    text = '',
                },
                widgets.Label{
                    view_id = 'tool_desc',
                    frame = {l = 0, t = 8, r = 0, b = 0},
                    auto_height = false,
                    text = '',
                },
            },
        },
        widgets.HotkeyLabel{
            view_id = 'toggle_label',
            frame = {l = 0, b = 0},
            key = 'CUSTOM_T',
            label = 'toggle autorun',
            on_activate = function()
                local _, choice = self.subviews.tool_list:getSelected()
                if choice and choice.item then self:toggle_tool(choice.item) end
            end,
        },
        widgets.HotkeyLabel{
            view_id = 'run_label',
            frame = {l = 22, b = 0},
            key = 'CUSTOM_R',
            label = 'run manually now',
            on_activate = function()
                local _, choice = self.subviews.tool_list:getSelected()
                if choice and choice.item and choice.item.category == 'dfhack script' then
                    self:run_tool(choice.item)
                end
            end,
        },
    }
    self:refresh()
end

function AmyWindow:onInput(keys)
    if keys.SELECT or keys.CUSTOM_SPACE or keys.CUSTOM_T then
        local _, choice = self.subviews.tool_list:getSelected()
        if choice and choice.item then
            self:toggle_tool(choice.item)
            return true
        end
    end
    if keys.CUSTOM_R then
        local _, choice = self.subviews.tool_list:getSelected()
        if choice and choice.item and choice.item.category == 'dfhack script' then
            self:run_tool(choice.item)
            return true
        end
    end
    return AmyWindow.super.onInput(self, keys)
end

function AmyWindow:refresh()
    local list = self.subviews.tool_list
    local choices = {}

    -- group 1: dfhack scripts
    table.insert(choices, {
        text = {{text = '-- dfhack scripts --', pen = COLOR_DARKGREY}},
        is_header = true,
    })
    for _, tool in ipairs(TOOLS) do
        if tool.category == 'dfhack script' then
            local installed = not tool.check_installed or tool.check_installed()
            if not installed then
                table.insert(choices, {
                    text = {
                        {text = '[-] ', pen = COLOR_DARKGREY},
                        {text = tool.name, pen = COLOR_DARKGREY},
                    },
                    item = tool,
                })
            else
                local on = is_on(tool.key)
                table.insert(choices, {
                    text = {
                        {text = on and '[x] ' or '[ ] ', pen = on and COLOR_LIGHTGREEN or COLOR_DARKGREY},
                        {text = tool.name, pen = on and COLOR_WHITE or COLOR_GREY},
                    },
                    item = tool,
                })
            end
        end
    end

    -- group 2: bundle modules
    table.insert(choices, {
        text = ' ',
        is_header = true,
    })
    table.insert(choices, {
        text = {{text = '-- bundle modules --', pen = COLOR_DARKGREY}},
        is_header = true,
    })
    for _, tool in ipairs(TOOLS) do
        if tool.is_bundle_module then
            local installed = not tool.check_installed or tool.check_installed()
            if not installed then
                table.insert(choices, {
                    text = {
                        {text = '[-] ', pen = COLOR_DARKGREY},
                        {text = tool.name, pen = COLOR_DARKGREY},
                    },
                    item = tool,
                })
            else
                local on = tool.get_status and tool.get_status() or false
                table.insert(choices, {
                    text = {
                        {text = on and '[x] ' or '[ ] ', pen = on and COLOR_LIGHTGREEN or COLOR_DARKGREY},
                        {text = tool.name, pen = on and COLOR_WHITE or COLOR_GREY},
                    },
                    item = tool,
                })
            end
        end
    end

    -- group 3: raw patches
    table.insert(choices, {
        text = ' ',
        is_header = true,
    })
    table.insert(choices, {
        text = {{text = '-- raw patches --', pen = COLOR_DARKGREY}},
        is_header = true,
    })
    for _, tool in ipairs(TOOLS) do
        if tool.is_raw_patch and not tool.is_weight_boost then
            local installed = not tool.check_installed or tool.check_installed()
            local frozen = tool.is_frozen and tool.is_frozen()
            if not installed then
                table.insert(choices, {
                    text = {
                        {text = '[-] ', pen = COLOR_DARKGREY},
                        {text = tool.name, pen = COLOR_DARKGREY},
                    },
                    item = tool,
                })
            elseif frozen then
                table.insert(choices, {
                    text = {
                        {text = '[!] ', pen = COLOR_LIGHTRED},
                        {text = tool.name .. ' (locked)', pen = COLOR_DARKGREY},
                    },
                    item = tool,
                })
            else
                local on = tool.get_status and tool.get_status() or false
                table.insert(choices, {
                    text = {
                        {text = on and '[x] ' or '[ ] ', pen = on and COLOR_LIGHTGREEN or COLOR_DARKGREY},
                        {text = tool.name, pen = on and COLOR_WHITE or COLOR_GREY},
                    },
                    item = tool,
                })
            end
        end
    end

    -- group 4: raw patches (weight boosts)
    table.insert(choices, {
        text = ' ',
        is_header = true,
    })
    table.insert(choices, {
        text = {{text = '-- raw patches (weight boosts) --', pen = COLOR_DARKGREY}},
        is_header = true,
    })
    for _, tool in ipairs(TOOLS) do
        if tool.is_weight_boost then
            local installed = not tool.check_installed or tool.check_installed()
            if not installed then
                table.insert(choices, {
                    text = {
                        {text = '[-] ', pen = COLOR_DARKGREY},
                        {text = tool.name, pen = COLOR_DARKGREY},
                    },
                    item = tool,
                })
            else
                local on = tool.get_status and tool.get_status() or false
                table.insert(choices, {
                    text = {
                        {text = on and '[x] ' or '[ ] ', pen = on and COLOR_LIGHTGREEN or COLOR_DARKGREY},
                        {text = tool.name, pen = on and COLOR_WHITE or COLOR_GREY},
                    },
                    item = tool,
                })
            end
        end
    end

    local prev_idx = list.selected or 2
    while choices[prev_idx] and choices[prev_idx].is_header do
        prev_idx = prev_idx + 1
    end
    if not choices[prev_idx] then prev_idx = 2 end
    list:setChoices(choices, prev_idx)
    local _, cur = list:getSelected()
    if cur and cur.item then
        self:show_tool(cur.item)
    else
        self:show_tool(TOOLS[1])
    end
end

function AmyWindow:toggle_tool(tool)
    if not tool then return end
    if tool.check_installed and not tool.check_installed() then
        print(('amywebbskii-scripts: cannot toggle "%s" — required dependency "%s" is not installed.'):format(tool.name, tool.depends_on or 'unknown'))
        return
    end
    if tool.is_frozen and tool.is_frozen() then
        dfhack.printerr(('amywebbskii-scripts: cannot toggle "%s" — patch is locked (upstream version > 4; manual audit required).'):format(tool.name))
        return
    end
    if tool.is_bundle_module then
        if tool.toggle then tool.toggle() end
        self:refresh()
        return
    end
    if tool.is_raw_patch then
        if tool.toggle then tool.toggle() end
        self:refresh()
        return
    end
    local new_state = not is_on(tool.key)
    set_on(tool.key, new_state)
    apply_tool(tool)
    self:refresh()
end

function AmyWindow:show_tool(tool)
    if not tool then return end
    local cat_color = tool.is_bundle_module and COLOR_LIGHTMAGENTA or (tool.is_raw_patch and COLOR_LIGHTYELLOW or COLOR_LIGHTCYAN)
    local p_type = tool.patch_type or tool.category
    local l_order = tool.load_order or 'n/a'
    local game_restart = tool.game_restart or 'not required'
    local new_world = tool.new_world or 'not required'

    local gr_pen = (game_restart:find('required') and not game_restart:find('not')) and COLOR_LIGHTRED or COLOR_GREY
    local nw_pen = (new_world:find('required') and not new_world:find('not')) and COLOR_LIGHTRED or COLOR_GREY

    local deps = tool.depends_on or 'none'
    local deps_pen = COLOR_CYAN
    local installed = not tool.check_installed or tool.check_installed()
    local frozen = tool.is_frozen and tool.is_frozen()
    if not installed then
        deps = deps .. ' (not installed)'
        deps_pen = COLOR_LIGHTRED
    end

    local status_text = ''
    local status_pen = COLOR_GREY
    if not installed then
        status_text = '[-] target dependency missing'
        status_pen = COLOR_DARKGREY
    elseif frozen then
        status_text = '[!] locked / frozen (upstream version > 4; manual review required)'
        status_pen = COLOR_LIGHTRED
    elseif tool.category == 'dfhack script' then
        local on = is_on(tool.key)
        status_text = on and '[x] autorun enabled (active on map load)' or '[ ] autorun disabled'
        status_pen = on and COLOR_LIGHTGREEN or COLOR_DARKGREY
    elseif tool.is_bundle_module then
        local on = tool.get_status and tool.get_status() or false
        status_text = on and '[x] module active in bundle' or '[ ] module disabled in bundle'
        status_pen = on and COLOR_LIGHTGREEN or COLOR_DARKGREY
    elseif tool.is_raw_patch then
        local on = tool.get_status and tool.get_status() or false
        status_text = on and '[x] patch applied (ready for game restart/worldgen)' or '[ ] patch unapplied (original raws active)'
        status_pen = on and COLOR_LIGHTGREEN or COLOR_DARKGREY
    end

    self.subviews.tool_title:setText({
        {text = tool.name, pen = (not installed or frozen) and COLOR_DARKGREY or COLOR_WHITE},
        {text = ('  [%s]'):format(tool.category), pen = (not installed or frozen) and COLOR_DARKGREY or cat_color},
    })

    self.subviews.tool_meta:setText({
        {text = 'status:       ', pen = COLOR_DARKGREY},
        {text = status_text, pen = status_pen},
        NEWLINE,
        {text = 'patch type:   ', pen = COLOR_DARKGREY},
        {text = p_type, pen = not installed and COLOR_DARKGREY or COLOR_LIGHTYELLOW},
        NEWLINE,
        {text = 'load order:   ', pen = COLOR_DARKGREY},
        {text = l_order, pen = not installed and COLOR_DARKGREY or COLOR_CYAN},
        NEWLINE,
        {text = 'game restart: ', pen = COLOR_DARKGREY},
        {text = game_restart, pen = not installed and COLOR_DARKGREY or gr_pen},
        NEWLINE,
        {text = 'new world:    ', pen = COLOR_DARKGREY},
        {text = new_world, pen = not installed and COLOR_DARKGREY or nw_pen},
        NEWLINE,
        {text = 'deps:         ', pen = COLOR_DARKGREY},
        {text = deps, pen = deps_pen},
    })

    local desc_w = math.max(38, self.frame.w - 40)
    self.subviews.tool_desc:setText(wrap_text(tool.desc, desc_w))

    if not installed then
        self.subviews.toggle_label:setLabel('dep missing')
        self.subviews.run_label.visible = false
        self.subviews.run_label:setLabel('')
    elseif frozen then
        self.subviews.toggle_label:setLabel('locked (v>4)')
        self.subviews.run_label.visible = false
        self.subviews.run_label:setLabel('')
    elseif tool.category == 'dfhack script' then
        self.subviews.toggle_label:setLabel('toggle autorun')
        self.subviews.run_label.visible = true
        self.subviews.run_label:setLabel('run manually now')
    elseif tool.is_bundle_module then
        local on = installed and tool.get_status and tool.get_status() or false
        self.subviews.toggle_label:setLabel(on and 'disable module' or 'enable module')
        self.subviews.run_label.visible = false
        self.subviews.run_label:setLabel('')
    elseif tool.is_raw_patch then
        local on = installed and tool.get_status and tool.get_status() or false
        self.subviews.toggle_label:setLabel(on and 'unapply patch' or 'apply patch')
        self.subviews.run_label.visible = false
        self.subviews.run_label:setLabel('')
    end
end

function AmyWindow:run_tool(tool)
    if not tool then return end
    if tool.check_installed and not tool.check_installed() then
        print(('amywebbskii-scripts: cannot run "%s" — required dependency "%s" is not installed.'):format(tool.name, tool.depends_on or 'unknown'))
        return
    end
    if tool.category ~= 'dfhack script' then return end
    print(('amywebbskii-scripts: manually executing `%s`...'):format(tool.cmd))
    if tool.run then
        tool.run()
    else
        dfhack.run_command(tool.cmd)
    end
end

AmyScreen = defclass(AmyScreen, gui.ZScreen)
AmyScreen.ATTRS{focus_path = 'amywebbskii-scripts', def_actions = {dismiss = 'LEAVESCREEN'}}

function AmyScreen:init()
    self:addviews{AmyWindow{}}
end

function AmyScreen:onDismiss()
    view = nil
end

-- ---- entry point ------------------------------------------------------------
local args = {...}
local cmd_arg = args[1]

if cmd_arg == 'apply' then
    apply_all()
    set_autostart(true)
    return
elseif cmd_arg == 'status' then
    print('amywebbskii-scripts configuration status:')
    for _, t in ipairs(TOOLS) do
        if t.is_bundle_module then
            local on = t.get_status and t.get_status() or false
            print(string.format('  [%s] %-24s (%s) - %s', on and 'x' or ' ', t.name, t.category, on and 'active in bundle' or 'disabled'))
        elseif t.is_raw_patch then
            local on = t.get_status and t.get_status() or false
            print(string.format('  [%s] %-24s (%s) - %s', on and 'x' or ' ', t.name, t.category, t.patch_type or t.cmd))
        else
            local on = is_on(t.key)
            print(string.format('  [%s] %-24s (%s) - cmd: %s', on and 'x' or ' ', t.name, t.category, t.cmd))
        end
    end
    return
elseif cmd_arg == 'enable' and args[2] then
    set_on(args[2], true)
    print(('amywebbskii-scripts: enabled %s'):format(args[2]))
    set_autostart(true)
    return
elseif cmd_arg == 'disable' and args[2] then
    set_on(args[2], false)
    print(('amywebbskii-scripts: disabled %s'):format(args[2]))
    return
elseif cmd_arg == 'help' or cmd_arg == '-h' or cmd_arg == '--help' then
    print('usage: amywebbskii-scripts [gui|apply|status|enable <key>|disable <key>|help]')
    print('without arguments or "gui": opens the interactive switchboard gui.')
    return
end

if not dfhack_flags.module then
    set_autostart(true)
    view = view and view:raise() or AmyScreen{}:show()
end
