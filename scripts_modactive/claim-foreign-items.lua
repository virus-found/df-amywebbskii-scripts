--@module = true
--@enable = true
-- Removes foreign and merchant ownership locks from items, containers, and treasures on embark

local argparse = require('argparse')
local dialogs = require('gui.dialogs')
local json = require('json')

local GLOBAL_KEY = 'claim_foreign_items'
local LAUNCHER_CONFIG_PATH = 'dfhack-config/amywebbskii-scripts.json'

local function is_launcher_enabled()
    local ok, cfg = pcall(json.open, LAUNCHER_CONFIG_PATH)
    if ok and cfg and cfg.data and type(cfg.data) == 'table' then
        if cfg.data['claim-foreign-items'] ~= nil then
            return cfg.data['claim-foreign-items'] == true
        end
    end
    return true
end

local function show_result_dialog(title, text, color)
    pcall(function()
        dialogs.showMessage(title, text, color or COLOR_GREEN)
    end)
end

local PRESERVE_CONTAINED_TYPES = {
    [df.item_type.DRINK] = true,
    [df.item_type.LIQUID_MISC] = true,
    [df.item_type.GLOB] = true,
    [df.item_type.POWDER_MISC] = true,
    [df.item_type.SEEDS] = true,
    [df.item_type.CHEESE] = true,
    [df.item_type.FOOD] = true,
    [df.item_type.MEAT] = true,
    [df.item_type.FISH] = true,
    [df.item_type.FISH_RAW] = true,
    [df.item_type.PLANT] = true,
    [df.item_type.PLANT_GROWTH] = true,
    [df.item_type.VERMIN] = true,
    [df.item_type.PET] = true,
    [df.item_type.CORPSE] = true,
    [df.item_type.CORPSEPIECE] = true,
    [df.item_type.REMAINS] = true,
    [df.item_type.EGG] = true,
}

local function is_in_stockpile(pos)
    local bld = dfhack.buildings.findAtTile(pos)
    return bld and bld:getType() == df.building_type.Stockpile
end

function claim_all_items(quiet, force)
    if not dfhack.isMapLoaded() or df.global.gamemode ~= df.game_mode.DWARF then
        if not quiet then dfhack.printerr('error: must be in a loaded fortress game to claim items.') end
        return 0, 0, 0, 0
    end

    if not force and not is_launcher_enabled() then
        if not quiet then
            print('claim-foreign-items: auto-claim is disabled in the amywebbskii-scripts launcher.')
        end
        return 0, 0, 0, 0
    end

    local site_data = dfhack.persistent.getSiteData(GLOBAL_KEY, {applied = false})
    if site_data.applied and not force then
        if not quiet then
            print('claim-foreign-items: all items on this site were already claimed. (use "run" or --force to re-scan).')
        end
        return 0, 0, 0, 0
    end

    local utils = require('utils')
    local eq = df.global.plotinfo.equipment
    local equip_types = {
        [df.item_type.WEAPON] = 'weapon',
        [df.item_type.ARMOR] = 'armor',
        [df.item_type.HELM] = 'helm',
        [df.item_type.PANTS] = 'pants',
        [df.item_type.GLOVES] = 'gloves',
        [df.item_type.SHOES] = 'shoes',
        [df.item_type.SHIELD] = 'shield',
        [df.item_type.AMMO] = 'ammo',
        [df.item_type.QUIVER] = 'quiver',
        [df.item_type.BACKPACK] = 'backpack',
        [df.item_type.FLASK] = 'flask',
    }

    local indexed = {}
    for t, _ in pairs(equip_types) do
        indexed[t] = {}
        for _, id in ipairs(eq.items_unassigned[t]) do indexed[t][id] = true end
        for _, id in ipairs(eq.items_assigned[t]) do indexed[t][id] = true end
    end

    local items_claimed = 0
    local items_unpacked = 0
    local container_contents_dumped = 0
    local equip_indexed = 0
    local categories_updated = {}

    -- 0. unpack equipment, weapons, and gear from loose ground containers
    -- in worldgen ruins/towns, items trapped inside loose bags/boxes on the ground
    -- have flags.in_inventory = true and pos = (-30000,-30000,-30000), making them
    -- completely unreachable for civilian labors (mining, woodcutting) and hauling.
    local unpacked_ids = {}
    local unpacked_any = true
    while unpacked_any do
        unpacked_any = false
        for _, it in ipairs(df.global.world.items.other.IN_PLAY) do
            if it.flags.container and it.flags.on_ground and not it.flags.in_building and not it.flags.removed and not it.flags.garbage_collect then
                if dfhack.items.getHolderUnit(it) == nil and not is_in_stockpile(it.pos) and it.general_refs then
                    for i = #it.general_refs - 1, 0, -1 do
                        local ref = it.general_refs[i]
                        if df.general_ref_contains_itemst:is_instance(ref) then
                            local sub = df.item.find(ref.item_id)
                            if sub and not unpacked_ids[sub.id] and not sub.flags.removed and not sub.flags.garbage_collect then
                                if not PRESERVE_CONTAINED_TYPES[sub:getType()] then
                                    if dfhack.items.moveToGround(sub, it.pos) then
                                        sub.flags.forbid = false
                                        if it.flags.dump then
                                            sub.flags.dump = true
                                        end
                                        unpacked_ids[sub.id] = true
                                        items_unpacked = items_unpacked + 1
                                        unpacked_any = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for _, it in ipairs(df.global.world.items.other.IN_PLAY) do
        -- 1. strip trader, foreign civilization, and worldgen site ownership locks
        local needs_claim = false
        if it.flags.trader or it.flags.foreign then
            it.flags.trader = false
            it.flags.foreign = false
            needs_claim = true
        end

        if it.world_data_id ~= -1 then
            it.world_data_id = -1
            it.world_data_subid = -1
            needs_claim = true
        end

        if needs_claim then
            -- remove entity_itemowner general references
            if it.general_refs then
                for i = #it.general_refs - 1, 0, -1 do
                    local ref = it.general_refs[i]
                    if df.general_ref_entity_itemownerst:is_instance(ref) then
                        it.general_refs:erase(i)
                    end
                end
            end
            items_claimed = items_claimed + 1
        end

        -- 2. propagate dump flag to contents if container is marked for dumping
        if it.flags.dump and it.flags.container and it.general_refs then
            for _, ref in ipairs(it.general_refs) do
                if df.general_ref_contains_itemst:is_instance(ref) then
                    local sub = df.item.find(ref.item_id)
                    if sub and not sub.flags.dump then
                        sub.flags.dump = true
                        container_contents_dumped = container_contents_dumped + 1
                    end
                end
            end
        end

        -- 3. register unassigned military equipment into fortress equipment pool
        local t = it:getType()
        local cat_name = equip_types[t]
        if cat_name and not indexed[t][it.id] and not it.flags.removed and not it.flags.garbage_collect and not it.flags.in_building then
            local held_by_non_citizen = false
            if it.general_refs then
                for _, r in ipairs(it.general_refs) do
                    if df.general_ref_unit_holderst:is_instance(r) then
                        local u = df.unit.find(r.unit_id)
                        if u and not (dfhack.units.isCitizen(u) or dfhack.units.isResident(u)) then
                            held_by_non_citizen = true
                            break
                        end
                    end
                end
            end

            if not held_by_non_citizen then
                utils.insert_sorted(eq.items_unassigned[t], it.id)
                indexed[t][it.id] = true
                equip_indexed = equip_indexed + 1
                categories_updated[cat_name] = true
            end
        end
    end

    for cat_name, _ in pairs(categories_updated) do
        if eq.update[cat_name] ~= nil then
            eq.update[cat_name] = true
        end
    end

    dfhack.persistent.saveSiteData(GLOBAL_KEY, {applied = true})

    if not quiet then
        if items_claimed > 0 or equip_indexed > 0 or items_unpacked > 0 then
            local lines = {}
            if items_claimed > 0 then
                table.insert(lines, string.format('claim-foreign-items: unlocked %d site item(s) for your fortress.', items_claimed))
            else
                table.insert(lines, 'claim-foreign-items: scanned site items.')
            end
            if items_unpacked > 0 then
                table.insert(lines, string.format('unpacked %d weapon(s), tool(s), and gear from loose containers to the ground.', items_unpacked))
            end
            if equip_indexed > 0 then
                table.insert(lines, string.format('%d weapons, armor, and gear are now ready for squad equipment.', equip_indexed))
            end
            if container_contents_dumped > 0 then
                table.insert(lines, string.format('marked %d item(s) inside dumped containers for dumping.', container_contents_dumped))
            end
            print(table.concat(lines, ' '))
        else
            print('claim-foreign-items: all items on the map are already claimed and available for use.')
        end
    elseif items_claimed > 0 or equip_indexed > 0 or items_unpacked > 0 then
        local announcement = string.format('claim-foreign-items: unlocked %d site item(s), unpacked %d from containers, %d military item(s) ready for squads.',
            items_claimed, items_unpacked, equip_indexed)
        print(announcement)
        dfhack.gui.showAnnouncement(announcement, COLOR_GREEN)

        local dlg_lines = {
            string.format('unlocked %d abandoned site and foreign item(s) across the map.', items_claimed)
        }
        if items_unpacked > 0 then
            table.insert(dlg_lines, string.format('\nunpacked %d weapon(s), tool(s), and clothes from loose ground containers.', items_unpacked))
        end
        if equip_indexed > 0 then
            table.insert(dlg_lines, string.format('\n%d weapons, armor, and gear pieces are now available for squad equipment.', equip_indexed))
        end
        if container_contents_dumped > 0 then
            table.insert(dlg_lines, string.format('\nmarked %d item(s) inside dumped containers for dumping.', container_contents_dumped))
        end
        table.insert(dlg_lines, '\nall site weapons, armor, furniture, and containers are now claimed and ready for fortress use.')
        show_result_dialog('claim foreign items', table.concat(dlg_lines, ''), COLOR_GREEN)
    end
    return items_claimed, container_contents_dumped, equip_indexed, items_unpacked
end

local function print_help()
    print([==[
usage: claim_foreign_items [<command>] [options]

removes invisible worldgen site, foreign, and merchant ownership locks from items,
weapons, armor, furniture, and containers across the map, unpacks gear trapped
inside loose ground containers, and indexes preplaced equipment for squad use.

runs automatically on fresh embark (once per site) if enabled in amywebbskii-scripts
launcher so all items in ruins/towns/monasteries are immediately accessible.

commands:
    help                     display this help text.
    run                      force claim all site/foreign/trader items immediately.
    status                   show how many locked items exist on the map.
    auto                     run embark auto-check (only claims if launcher enabled and not yet applied).
    disable, stop            deactivate auto-claiming for current session.

options:
    -f, --force              force claiming even if already applied or disabled in launcher.
]==])
end

local function print_status()
    local foreign_count = 0
    local trader_count = 0
    local world_data_count = 0
    local trapped_count = 0
    for _, it in ipairs(df.global.world.items.other.IN_PLAY) do
        if it.flags.foreign then foreign_count = foreign_count + 1 end
        if it.flags.trader then trader_count = trader_count + 1 end
        if it.world_data_id ~= -1 then world_data_count = world_data_count + 1 end
        if it.flags.container and it.flags.on_ground and not it.flags.in_building and not it.flags.removed and not it.flags.garbage_collect then
            if dfhack.items.getHolderUnit(it) == nil and not is_in_stockpile(it.pos) and it.general_refs then
                for _, ref in ipairs(it.general_refs) do
                    if df.general_ref_contains_itemst:is_instance(ref) then
                        local sub = df.item.find(ref.item_id)
                        if sub and not sub.flags.removed and not sub.flags.garbage_collect and not PRESERVE_CONTAINED_TYPES[sub:getType()] then
                            trapped_count = trapped_count + 1
                        end
                    end
                end
            end
        end
    end
    local site_data = dfhack.persistent.getSiteData(GLOBAL_KEY, {applied = false})
    local launcher_status = is_launcher_enabled() and 'enabled' or 'disabled'
    local text = string.format('items currently locked on map: %d worldgen site (world_data_id), %d foreign, %d merchant/trader, %d trapped in loose containers (launcher: %s, embark claim applied: %s).',
        world_data_count, foreign_count, trader_count, trapped_count, launcher_status, tostring(site_data.applied))
    print(text)
end

dfhack.onStateChange[GLOBAL_KEY] = function(code)
    if code == SC_MAP_LOADED and df.global.gamemode == df.game_mode.DWARF then
        dfhack.timeout(5, 'ticks', function()
            if dfhack.isMapLoaded() and is_launcher_enabled() then
                claim_all_items(true, false)
            end
        end)
    end
end

function main(...)
    local args = {...}
    local force = false
    local auto = false
    local cmd = nil

    for _, a in ipairs(args) do
        local lower_a = tostring(a):lower()
        if lower_a == '--force' or lower_a == '-f' then
            force = true
        elseif lower_a == '--auto' or lower_a == 'auto' then
            auto = true
        elseif lower_a == 'help' or lower_a == '-h' or lower_a == '--help' then
            cmd = 'help'
        elseif lower_a == 'status' or lower_a == 'count' then
            cmd = 'status'
        elseif lower_a == 'run' or lower_a == 'all' then
            cmd = 'run'
        elseif lower_a == 'disable' or lower_a == 'stop' or lower_a == '--stop' or lower_a == 'off' then
            cmd = 'stop'
        end
    end

    if cmd == 'help' then
        print_help()
    elseif cmd == 'status' then
        print_status()
    elseif cmd == 'stop' then
        print('claim_foreign_items: disabled.')
    elseif auto then
        claim_all_items(true, force)
    elseif cmd == 'run' or force or #args == 0 then
        claim_all_items(false, true)
    else
        claim_all_items(false, force)
    end
end

if not dfhack_flags.module then
    main(...)
end
