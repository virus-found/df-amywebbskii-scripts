--@module = true
--@enable = true
-- suppresses starting wagon, draft animals, and embark wood clutter for solo hermit runs

local argparse = require('argparse')
local json = require('json')

local GLOBAL_KEY = 'wagonless_hermit'
local LAUNCHER_CONFIG_PATH = 'dfhack-config/amywebbskii-scripts.json'

local function is_launcher_enabled()
    local ok, cfg = pcall(json.open, LAUNCHER_CONFIG_PATH)
    if ok and cfg and cfg.data and type(cfg.data) == 'table' then
        if cfg.data['wagonless-hermit'] ~= nil then
            return cfg.data['wagonless-hermit'] == true
        end
    end
    return false
end

local function safe_get(fn)
    local ok, res = pcall(fn)
    if ok and res ~= nil then return res end
    return nil
end

local function purge_item_and_contents(item)
    if not item then return end
    pcall(function()
        if item.flags then
            item.flags.garbage_collect = true
            item.flags.forbid = true
            item.flags.dump = true
            item.flags.hidden = true
        end
        item.pos.x = -30000
        item.pos.y = -30000
        item.pos.z = -30000
    end)
    pcall(function() dfhack.items.remove(item) end)
end

local function clean_loose_wagon_logs(wagon_positions)
    local count = 0
    if not wagon_positions or #wagon_positions == 0 then return 0 end
    local items = df.global.world and df.global.world.items and df.global.world.items.all
    if items then
        for i = #items - 1, 0, -1 do
            local item = items[i]
            if item and df.item_woodst:is_instance(item) and not item.flags.in_inventory and not item.flags.in_building then
                for _, wp in ipairs(wagon_positions) do
                    if item.pos.z == wp.z and math.abs(item.pos.x - wp.x) <= 4 and math.abs(item.pos.y - wp.y) <= 4 then
                        purge_item_and_contents(item)
                        count = count + 1
                        break
                    end
                end
            end
        end
    end
    return count
end

local function clean_corpses_and_announcements(wagon_positions)
    -- 1. remove only corpse items resulting from wagon pack animals near wagon positions
    if wagon_positions and #wagon_positions > 0 then
        local items = df.global.world and df.global.world.items and df.global.world.items.all
        if items then
            for i = #items - 1, 0, -1 do
                local item = items[i]
                if item and (df.item_corpsest:is_instance(item) or df.item_corpsepiecest:is_instance(item)) then
                    for _, wp in ipairs(wagon_positions) do
                        if item.pos.z == wp.z and math.abs(item.pos.x - wp.x) <= 5 and math.abs(item.pos.y - wp.y) <= 5 then
                            purge_item_and_contents(item)
                            break
                        end
                    end
                end
            end
        end
    end

    -- 2. clear pack animal death announcements safely
    pcall(function()
        local status = df.global.world and df.global.world.status
        if status then
            local announcements = status.announcements
            if announcements then
                for i = #announcements - 1, 0, -1 do
                    local a = announcements[i]
                    local text = a and a.text or ""
                    if text:find("has been found dead") or text:find("Cauchemar") or text:find("Horse") or text:find("Yak") or text:find("Mule") or text:find("Ox") or text:find("Water buffalo") then
                        announcements:erase(i)
                    end
                end
            end

            local reports = status.reports
            if reports then
                for i = #reports - 1, 0, -1 do
                    local r = reports[i]
                    local text = r and r.text or ""
                    if text:find("has been found dead") or text:find("Cauchemar") or text:find("Horse") or text:find("Yak") or text:find("Mule") or text:find("Ox") or text:find("Water buffalo") then
                        reports:erase(i)
                    end
                end
            end

            status.display_timer = 0
        end
    end)
end

local function vaporize_unit(unit)
    if not unit then return end

    -- 1. remove any carried/equipped inventory items without leaving debris
    if unit.inventory then
        for i = #unit.inventory - 1, 0, -1 do
            local inv_item = unit.inventory[i]
            if inv_item and inv_item.item then
                pcall(function() dfhack.items.moveToGround(inv_item.item, {x=0, y=0, z=0}) end)
                pcall(function() dfhack.items.remove(inv_item.item) end)
            end
        end
    end

    -- 2. set blood count to 0 and vanish countdown so df engine clears the unit
    unit.body.blood_count = 0
    unit.flags2.slaughter = false
    unit.flags2.killed = false
    if unit.animal then
        unit.animal.vanish_countdown = 1
    else
        unit.flags2.killed = true
        dfhack.units.teleport(unit, {x = 0, y = 0, z = 0})
    end
end

function apply_no_wagon(force)
    if not dfhack.isMapLoaded() or df.global.gamemode ~= df.game_mode.DWARF then
        return false, 'must be in a loaded fortress mode game'
    end

    -- prevent running on established forts unless explicitly forced
    if df.global.cur_year_tick > 20000 and not force then
        return false, 'wagonless_hermit: refusing to run on established fortress (cur_year_tick > 20000); use --force to override'
    end

    local site_data = dfhack.persistent.getSiteData(GLOBAL_KEY, {applied = false})
    if site_data.applied and not force then
        return true, 'already applied for this site'
    end

    local wagons_removed = 0
    local draft_animals_removed = 0
    local logs_removed = 0
    local wagon_positions = {}

    -- 1. erase wagon buildings (df.building_wagonst)
    for i = #df.global.world.buildings.all - 1, 0, -1 do
        local bld = df.global.world.buildings.all[i]
        if df.building_wagonst:is_instance(bld) then
            table.insert(wagon_positions, {x = bld.centerx, y = bld.centery, z = bld.z})
            -- remove any contained items inside wagon (the 3 wood logs)
            if bld.contained_items then
                for j = #bld.contained_items - 1, 0, -1 do
                    local bitem = bld.contained_items[j]
                    if bitem and bitem.item then
                        pcall(function() dfhack.items.moveToGround(bitem.item, {x=0, y=0, z=0}) end)
                        pcall(function() dfhack.items.remove(bitem.item) end)
                    end
                end
            end
            -- cancel any pending deconstruct jobs
            if bld.jobs then
                for j = #bld.jobs - 1, 0, -1 do
                    local job = bld.jobs[j]
                    if job then
                        dfhack.job.removeJob(job)
                    end
                end
            end
            -- unlink from map tile blocks
            pcall(function()
                for x = bld.x1, bld.x2 do
                    for y = bld.y1, bld.y2 do
                        local block = dfhack.maps.getTileBlock(x, y, bld.z)
                        if block and block.buildings then
                            for bi = #block.buildings - 1, 0, -1 do
                                if block.buildings[bi] == bld.id then
                                    block.buildings:erase(bi)
                                end
                            end
                        end
                    end
                end
            end)
            bld.flags.almost_deleted = true
            wagons_removed = wagons_removed + 1
        end
    end

    -- 2. erase wagon units & draft/pack animals (only if wagon present or near wagon)
    for i = #df.global.world.units.active - 1, 0, -1 do
        local u = df.global.world.units.active[i]
        if u and not dfhack.units.isDead(u) then
            local craw = df.creature_raw.find(u.race)
            local cid = craw and craw.creature_id or ""

            if cid == "EQUIPMENT_WAGON" or cid == "WAGON" then
                vaporize_unit(u)
                wagons_removed = wagons_removed + 1
            elseif #wagon_positions > 0 and not dfhack.units.isCitizen(u) and (dfhack.units.isTame(u) or u.civ_id == df.global.plotinfo.civ_id) then
                -- domestic draft animals brought with embark wagon
                local near_wagon = false
                for _, wp in ipairs(wagon_positions) do
                    if u.pos.z == wp.z and math.abs(u.pos.x - wp.x) <= 10 and math.abs(u.pos.y - wp.y) <= 10 then
                        near_wagon = true
                        break
                    end
                end
                if near_wagon then
                    vaporize_unit(u)
                    draft_animals_removed = draft_animals_removed + 1
                end
            end
        end
    end

    -- 3. delete loose wagon wood logs resulting from wagon deconstruction near wagon
    logs_removed = clean_loose_wagon_logs(wagon_positions)

    -- 4. clean immediate corpses/announcements near wagon
    clean_corpses_and_announcements(wagon_positions)
    dfhack.timeout(1, 'ticks', function() clean_corpses_and_announcements(wagon_positions) end)
    dfhack.timeout(2, 'ticks', function() clean_corpses_and_announcements(wagon_positions) end)
    dfhack.timeout(5, 'ticks', function() clean_corpses_and_announcements(wagon_positions) end)
    dfhack.timeout(10, 'ticks', function() clean_corpses_and_announcements(wagon_positions) end)
    dfhack.timeout(20, 'ticks', function() clean_corpses_and_announcements(wagon_positions) end)

    dfhack.persistent.saveSiteData(GLOBAL_KEY, {applied = true})

    local msg = string.format('wagonless_hermit: %d wagon(s), %d pack animal(s), %d log(s) disintegrated.',
        wagons_removed, draft_animals_removed, logs_removed)
    print(msg)
    return true, msg
end

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc == SC_MAP_LOADED and df.global.gamemode == df.game_mode.DWARF then
        if not is_launcher_enabled() then return end
        if df.global.cur_year_tick > 20000 then return end
        dfhack.timeout(10, 'ticks', function()
            if dfhack.isMapLoaded() and is_launcher_enabled() and df.global.cur_year_tick <= 20000 then
                apply_no_wagon(false)
            end
        end)
    end
end

function main(...)
    local args = {...}
    local force = false
    for _, a in ipairs(args) do
        if a == '--force' or a == '-f' then force = true end
    end
    local ok, res = apply_no_wagon(force)
    if not ok then
        dfhack.printerr(res)
    end
end

if not dfhack_flags.module then
    main(...)
end
