--@module = true
--@enable = true
-- Removes foreign and merchant ownership locks from items, containers, and treasures on embark

local argparse = require('argparse')
local dialogs = require('gui.dialogs')

local GLOBAL_KEY = 'claim_foreign_items'

local function show_result_dialog(title, text, color)
    pcall(function()
        dialogs.showMessage(title, text, color or COLOR_GREEN)
    end)
end

function claim_all_items(quiet, force)
    if not dfhack.isMapLoaded() or df.global.gamemode ~= df.game_mode.DWARF then
        if not quiet then dfhack.printerr('Error: Must be in a loaded fortress game to claim items.') end
        return 0, 0
    end

    local site_data = dfhack.persistent.getSiteData(GLOBAL_KEY, {applied = false})
    if site_data.applied and not force then
        if not quiet then
            local msg = 'claim_foreign_items: already claimed on embark for this site (use --force or "run" to override).'
            print(msg)
        end
        return 0, 0
    end

    local items_claimed = 0
    local container_contents_dumped = 0

    for _, it in ipairs(df.global.world.items.other.IN_PLAY) do
        -- 1. Strip trader and foreign civilization ownership
        if it.flags.trader or it.flags.foreign then
            it.flags.trader = false
            it.flags.foreign = false

            -- Remove ENTITY_ITEMOWNER general references
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

        -- 2. Propagate dump flag to contents if container is marked for dumping
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
    end

    dfhack.persistent.saveSiteData(GLOBAL_KEY, {applied = true})

    if not quiet then
        print(string.format('claim_foreign_items: Successfully claimed %d item(s). Propagated dump flag to %d contained item(s).',
            items_claimed, container_contents_dumped))
    elseif items_claimed > 0 then
        local announcement = string.format('claim_foreign_items: Unlocked %d foreign site item(s).', items_claimed)
        print(announcement)
        dfhack.gui.showAnnouncement(announcement, COLOR_GREEN)

        local dlg_text = string.format('Successfully claimed and unlocked %d foreign/trader item(s) across the map.', items_claimed)
        if container_contents_dumped > 0 then
            dlg_text = dlg_text .. string.format('\nPropagated dump flag to %d contained item(s).', container_contents_dumped)
        end
        dlg_text = dlg_text .. '\n\nAll site weapons, armor, furniture, and containers are now claimed for your fortress.'
        show_result_dialog('claim foreign items', dlg_text, COLOR_GREEN)
    end
    return items_claimed, container_contents_dumped
end

local function print_help()
    print([==[
Usage: claim_foreign_items [<command>] [options]

Removes invisible foreign merchant and previous owner locks from items,
weapons, armor, furniture, and containers across the map.

Runs automatically on fresh embark (once per site) via dfhack persistent
site data so all items in ruins/towns/monasteries are immediately accessible.

Commands:
    help                     Display this help text.
    run                      Force claim all foreign/trader items immediately.
    status                   Show how many foreign/trader items exist on the map.
    auto                     Run embark auto-check (only claims if not already applied for this site).

Options:
    -f, --force              Force claiming even if already applied for this site.
]==])
end

local function print_status()
    local foreign_count = 0
    local trader_count = 0
    for _, it in ipairs(df.global.world.items.other.IN_PLAY) do
        if it.flags.foreign then foreign_count = foreign_count + 1 end
        if it.flags.trader then trader_count = trader_count + 1 end
    end
    local site_data = dfhack.persistent.getSiteData(GLOBAL_KEY, {applied = false})
    local text = string.format('Items currently locked on map: %d foreign, %d merchant/trader (embark claim applied: %s).',
        foreign_count, trader_count, tostring(site_data.applied))
    print(text)
end

dfhack.onStateChange[GLOBAL_KEY] = function(code)
    if code == SC_MAP_LOADED and df.global.gamemode == df.game_mode.DWARF then
        dfhack.timeout(5, 'ticks', function()
            if dfhack.isMapLoaded() then
                claim_all_items(true, false)
            end
        end)
    end
end

if dfhack.isMapLoaded() then
    claim_all_items(true, false)
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
        end
    end

    if cmd == 'help' then
        print_help()
    elseif cmd == 'status' then
        print_status()
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
