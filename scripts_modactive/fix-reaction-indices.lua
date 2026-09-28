-- sanitizes entity reaction indices to prevent null pointer dereference crashes in the v50 item sheet (df bug 13552: https://dwarffortressbugtracker.com/view.php?id=13552)
--@module = true

local argparse = require('argparse')

local function sanitize_entity(ent, quiet)
    if not ent or not ent.resources or not ent.resources.reaction_idx then
        return 0, 0
    end

    local reactions = df.global.world and df.global.world.raws and df.global.world.raws.reactions and df.global.world.raws.reactions.reactions
    if not reactions then
        return 0, 0
    end

    local valid_indices = {}
    local pruned_count = 0
    local total_count = #ent.resources.reaction_idx

    for i = 0, total_count - 1 do
        local idx = ent.resources.reaction_idx[i]
        if idx and idx >= 0 and idx < #reactions and reactions[idx] then
            table.insert(valid_indices, idx)
        else
            pruned_count = pruned_count + 1
        end
    end

    if pruned_count > 0 then
        ent.resources.reaction_idx:resize(0)
        for _, idx in ipairs(valid_indices) do
            ent.resources.reaction_idx:insert('#', idx)
        end
        local name = dfhack.translation.translateName(ent.name)
        if not name or name == '' then
            name = string.format('entity #%d', ent.id)
        end
        print(string.format('[fix-reaction-indices] sanitized %s: removed %d invalid reaction index entries (%d remaining)', name, pruned_count, #valid_indices))
    elseif not quiet then
        local name = dfhack.translation.translateName(ent.name)
        if not name or name == '' then
            name = string.format('entity #%d', ent.id)
        end
        print(string.format('[fix-reaction-indices] %s: all %d reaction indices are clean', name, total_count))
    end

    return pruned_count, total_count
end

local PERSIST_KEY = 'fix-reaction-indices'

local function sanitize_all(opts)
    if not dfhack.isMapLoaded() then
        if not opts.quiet then
            dfhack.printerr('must be run in a loaded fortress mode game')
        end
        return
    end

    if not opts.force then
        local pdata = dfhack.persistent.getWorldData(PERSIST_KEY, nil)
        if pdata and pdata.applied then
            if not opts.quiet then
                print('[fix-reaction-indices] world reaction indices already sanitized; skipping (use --force to re-scan)')
            end
            return
        end
    end

    local total_pruned = 0
    local entities_checked = 0

    if opts.all and df.global.world and df.global.world.entities and df.global.world.entities.all then
        for _, ent in ipairs(df.global.world.entities.all) do
            if ent and ent.resources and ent.resources.reaction_idx and #ent.resources.reaction_idx > 0 then
                local pruned, _ = sanitize_entity(ent, opts.quiet)
                total_pruned = total_pruned + pruned
                entities_checked = entities_checked + 1
            end
        end
    else
        local checked_ids = {}
        local candidates = {
            df.global.plotinfo and df.global.plotinfo.group_id,
            df.global.plotinfo and df.global.plotinfo.civ_id,
        }
        for _, id in ipairs(candidates) do
            if id and id >= 0 and not checked_ids[id] then
                checked_ids[id] = true
                local ent = df.historical_entity.find(id)
                if ent then
                    local pruned, _ = sanitize_entity(ent, opts.quiet)
                    total_pruned = total_pruned + pruned
                    entities_checked = entities_checked + 1
                end
            end
        end
    end

    dfhack.persistent.saveWorldData(PERSIST_KEY, {
        applied = true,
        timestamp = os.time(),
        pruned = total_pruned,
        entities_checked = entities_checked,
    })

    if total_pruned > 0 then
        local msg = string.format('sanitized reaction indices: purged %d corrupted entries across %d entities', total_pruned, entities_checked)
        dfhack.gui.showAnnouncement(msg, COLOR_GREEN)
    elseif not opts.quiet then
        print(string.format('[fix-reaction-indices] checked %d entities: no corrupted reaction indices found', entities_checked))
    end
end

if not dfhack_flags.module then
    local quiet = false
    local check_all = false
    local force = false
    local help = false
    local positionals = argparse.processArgsGetopt({...}, {
        {'q', 'quiet', handler=function() quiet = true end},
        {'a', 'all', handler=function() check_all = true end},
        {'f', 'force', handler=function() force = true end},
        {'h', 'help', handler=function() help = true end},
    })

    if help or (positionals and positionals[1] == 'help') then
        print([[
usage: fix-reaction-indices [options]

sanitizes historical_entity.resources.reaction_idx to remove out-of-bounds or null
reaction pointers, preventing v50 item sheet SIGSEGV crashes on tile clicks.
fixes df bug 13552 (https://dwarffortressbugtracker.com/view.php?id=13552).

options:
  -q, --quiet    suppress output unless corrupted indices are found and pruned
  -a, --all      check all entities in the world, not just the fortress and civ
  -f, --force    force re-scan even if already sanitized in this world
  -h, --help     display this help message
]])
        return
    end

    sanitize_all({quiet = quiet, all = check_all, force = force})
end
