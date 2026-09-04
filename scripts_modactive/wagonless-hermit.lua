--@module = true
--@enable = true
-- Disintegrates the starting wagon, draft animals, logs, and corpses without leaving traces or announcements

local argparse = require('argparse')

local GLOBAL_KEY = 'wagonless_hermit'

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

local function clean_loose_wood_logs()
    local count = 0
    local items = df.global.world and df.global.world.items and df.global.world.items.all
    if items then
        for i = #items - 1, 0, -1 do
            local item = items[i]
            if item and df.item_woodst:is_instance(item) then
                purge_item_and_contents(item)
                count = count + 1
            end
        end
    end
    return count
end

local function clean_corpses_and_announcements()
    -- 1. Remove all corpse items resulting from wagon pack animals
    local items = df.global.world and df.global.world.items and df.global.world.items.all
    if items then
        for i = #items - 1, 0, -1 do
            local item = items[i]
            if item and (df.item_corpsest:is_instance(item) or df.item_corpsepiecest:is_instance(item)) then
                purge_item_and_contents(item)
            end
        end
    end

    -- 2. Remove all loose/limbo wood logs
    clean_loose_wood_logs()

    -- 3. Clear death announcements and reports
    local status = df.global.world.status
    if status then
        local announcements = status.announcements
        if announcements then
            for i = #announcements - 1, 0, -1 do
                local text = announcements[i].text or ""
                if text:find("has been found dead") or text:find("Cauchemar") or text:find("Horse") or text:find("Yak") or text:find("Mule") then
                    announcements:erase(i)
                end
            end
        end

        local reports = status.reports
        if reports then
            for i = #reports - 1, 0, -1 do
                local text = reports[i].text or ""
                if text:find("has been found dead") or text:find("Cauchemar") or text:find("Horse") or text:find("Yak") or text:find("Mule") then
                    reports:erase(i)
                end
            end
        end

        status.display_timer = 0
    end
end

local function vaporize_unit(unit)
    if not unit then return end
    
    -- 1. Remove any carried/equipped inventory items without leaving debris
    if unit.inventory then
        for i = #unit.inventory - 1, 0, -1 do
            local inv_item = unit.inventory[i]
            if inv_item and inv_item.item then
                pcall(function() dfhack.items.moveToGround(inv_item.item, {x=0, y=0, z=0}) end)
                pcall(function() dfhack.items.remove(inv_item.item) end)
            end
        end
    end

    -- 2. Set blood count to 0 and vanish countdown so DF engine clears the unit
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

    local site_data = dfhack.persistent.getSiteData(GLOBAL_KEY, {applied = false})
    if site_data.applied and not force then
        return true, 'already applied for this site'
    end

    local wagons_removed = 0
    local draft_animals_removed = 0
    local logs_removed = 0

    -- 1. Erase wagon buildings (df.building_wagonst)
    for i = #df.global.world.buildings.all - 1, 0, -1 do
        local bld = df.global.world.buildings.all[i]
        if df.building_wagonst:is_instance(bld) then
            -- Remove any contained items inside wagon (the 3 wood logs)
            if bld.contained_items then
                for j = #bld.contained_items - 1, 0, -1 do
                    local bitem = bld.contained_items[j]
                    if bitem and bitem.item then
                        pcall(function() dfhack.items.moveToGround(bitem.item, {x=0, y=0, z=0}) end)
                        pcall(function() dfhack.items.remove(bitem.item) end)
                    end
                end
            end
            -- Cancel any pending deconstruct jobs
            if bld.jobs then
                for j = #bld.jobs - 1, 0, -1 do
                    local job = bld.jobs[j]
                    if job then
                        dfhack.job.removeJob(job)
                    end
                end
            end
            -- Unlink from map tile blocks
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

    -- 2. Erase wagon units & draft/pack animals
    for i = #df.global.world.units.active - 1, 0, -1 do
        local u = df.global.world.units.active[i]
        if u and not dfhack.units.isDead(u) then
            local craw = df.creature_raw.find(u.race)
            local cid = craw and craw.creature_id or ""

            if cid == "EQUIPMENT_WAGON" or cid == "WAGON" then
                vaporize_unit(u)
                wagons_removed = wagons_removed + 1
            elseif not dfhack.units.isCitizen(u) and (dfhack.units.isTame(u) or u.civ_id == df.global.plotinfo.civ_id) then
                -- Domestic livestock/draft animals brought with embark
                vaporize_unit(u)
                draft_animals_removed = draft_animals_removed + 1
            end
        end
    end

    -- 3. Delete any loose/limbo wagon wood logs resulting from wagon deconstruction
    logs_removed = clean_loose_wood_logs()

    -- 4. Clean immediate corpses/announcements and schedule cleanup across initial ticks
    clean_corpses_and_announcements()
    dfhack.timeout(1, 'ticks', clean_corpses_and_announcements)
    dfhack.timeout(2, 'ticks', clean_corpses_and_announcements)
    dfhack.timeout(5, 'ticks', clean_corpses_and_announcements)
    dfhack.timeout(10, 'ticks', clean_corpses_and_announcements)
    dfhack.timeout(20, 'ticks', clean_corpses_and_announcements)
    dfhack.timeout(50, 'ticks', clean_corpses_and_announcements)
    dfhack.timeout(100, 'ticks', clean_corpses_and_announcements)

    dfhack.persistent.saveSiteData(GLOBAL_KEY, {applied = true})

    local msg = string.format('wagonless_hermit: %d wagon(s), %d pack animal(s), %d log(s) disintegrated.',
        wagons_removed, draft_animals_removed, logs_removed)
    print(msg)
    return true, msg
end

dfhack.onStateChange[GLOBAL_KEY] = function(code)
    if code == SC_WORLD_LOADED then
        if dfhack.isMapLoaded() then
            apply_no_wagon(false)
        end
    end
end

if dfhack.isMapLoaded() then
    apply_no_wagon(false)
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
