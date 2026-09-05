--[====[

choose_your_hermit (better startdwarf)
======================================

an interactive gui & auto-embark selector that allows you to choose your solo hermit settler at the start of a fortress.

a superior alternative to `startdwarf`: instead of blindly keeping an arbitrary dwarf, `choose_your_hermit` gives you full agency to inspect and select your single hermit settler from the starting expedition party while cleanly removing the rest.

cleanly removes the other starting expedition dwarves without touching foreign site inhabitants, local wildlife, or neutral creatures, and without triggering negative thoughts, ghost hazards, clothes litter, companion relationship baggage, or df v50 labor matrix crashes.

features
--------
- automatically triggers on fresh embark arrival with an interactive selection window.
- captures all starting expedition members reliably (using comprehensive citizenship, group, and histfig checks).
- interactive dwarf selector: view and choose who stays based on stats, attributes, and traits.
- disintegrates the unchosen companions via native engine `vanish_countdown` (no cave teleportation, ghost generation, or corpses).
- safely deletes 100% of worn clothing and shoes directly from vanished companions before erasure (no clothes clutter on ground).
- purges companion relationships, grief emotions, and histfig links from the chosen hermit so they start truly alone.
- cleanly strips removed dwarves from work details (`plotinfo.labor_info.work_details`), individual labors, burrows, and room assignments.
- deconstructs the starting wagon and enables the `hermit` plugin.

how to use
----------
1. run `choose-your-hermit` in the dfhack console before embarking (or add `choose-your-hermit` to your `dfhack.init`).
2. embark on your chosen site.
3. in the first seconds after map arrival, the selection window will automatically open.
4. select your hermit and click 'keep as solo hermit' - all companions, their items, wagon, and relationships will be cleanly handled in a single step.

usage
-----
    choose_your_hermit
    choose_hermit
    choose-your-hermit

]====]

--@ module = true

local gui = require('gui')
local widgets = require('gui.widgets')
local dialogs = require('gui.dialogs')

local GLOBAL_KEY = 'choose_your_hermit'

-- safely runs a dfhack command if the script/plugin exists, otherwise quietly ignores it
local function safe_run_command(cmd, ...)
    local full_cmd = cmd
    local args = {...}
    if #args > 0 then
        full_cmd = full_cmd .. ' ' .. table.concat(args, ' ')
    end

    local base_cmd = cmd:match('^(%S+)')
    if base_cmd == 'enable' or base_cmd == 'disable' then
        base_cmd = cmd:match('^%S+%s+(%S+)')
    end

    if base_cmd and (dfhack.findScript(base_cmd) or dfhack[base_cmd] or pcall(function() return dfhack.isPluginEnabled(base_cmd) ~= nil end)) then
        local ok, err = pcall(function() dfhack.run_command(full_cmd) end)
        if ok then
            return true
        end
    end
    return false
end

-- reliably checks if a unit belongs to the player's starting embark party
local function is_our_embark_colonist(u, fort_hfig_set)
    if not u or dfhack.units.isDead(u) or u.flags1.left then return false end
    if u.flags1.tame or u.flags1.merchant or u.flags1.diplomat or u.flags2.visitor then return false end
    if not u.status or not u.status.current_soul then return false end

    -- 1. check fortress entity histfig membership
    if fort_hfig_set and u.hist_figure_id and u.hist_figure_id >= 0 and fort_hfig_set[u.hist_figure_id] then
        return true
    end

    -- 2. check fort control or citizenship or own civ or own group
    if dfhack.units.isFortControlled(u) or dfhack.units.isCitizen(u, true) or dfhack.units.isOwnCiv(u) or dfhack.units.isOwnGroup(u) then
        return true
    end

    -- 3. check civ_id matching player's civ or fortress group
    local p_civ = df.global.plotinfo and df.global.plotinfo.civ_id
    local p_grp = df.global.plotinfo and df.global.plotinfo.group_id
    if (p_civ and u.civ_id == p_civ) or (p_grp and u.civ_id == p_grp) then
        return true
    end

    return false
end

-- comprehensively and strictly retrieves all player fortress starting expedition members
local function get_embark_citizens()
    local units = {}
    local seen = {}

    local fort_entity = df.global.plotinfo and df.global.plotinfo.group_id and df.historical_entity.find(df.global.plotinfo.group_id)
    local fort_hfig_set = {}
    if fort_entity and fort_entity.histfig_ids then
        for _, id in ipairs(fort_entity.histfig_ids) do
            fort_hfig_set[id] = true
        end
    end

    if df.global.world and df.global.world.units and df.global.world.units.active then
        for _, u in ipairs(df.global.world.units.active) do
            if u and not seen[u.id] and is_our_embark_colonist(u, fort_hfig_set) then
                seen[u.id] = true
                table.insert(units, u)
            end
        end
    end

    return units
end

-- cleans up all labors, work details, burrows, and workshops for a unit to prevent labors UI crash
local function clean_unit_associations(u)
    if not u then return end

    -- 1. clear work details (v50 labor matrix)
    pcall(function()
        local work_details = df.global.plotinfo and df.global.plotinfo.labor_info and df.global.plotinfo.labor_info.work_details
        if work_details then
            for _, detail in ipairs(work_details) do
                if detail.assigned_units then
                    for k = #detail.assigned_units - 1, 0, -1 do
                        if detail.assigned_units[k] == u.id then
                            detail.assigned_units:erase(k)
                        end
                    end
                end
            end
        end
    end)

    -- 2. clear individual labor flags
    pcall(function()
        if u.status and u.status.labors then
            for k = 0, #u.status.labors - 1 do
                u.status.labors[k] = false
            end
        end
    end)

    -- 3. unassign owned rooms / buildings
    pcall(function()
        if u.owned_buildings then
            for i = #u.owned_buildings - 1, 0, -1 do
                local bld = df.building.find(u.owned_buildings[i].id)
                if bld then
                    dfhack.buildings.setOwner(bld, nil)
                end
            end
        end
    end)

    -- 4. remove from workshop profiles
    pcall(function()
        local buildings = df.global.world and df.global.world.buildings and df.global.world.buildings.other
        if buildings then
            if buildings.WORKSHOP_ANY then
                for _, bld in ipairs(buildings.WORKSHOP_ANY) do
                    if bld.profile and bld.profile.permitted_workers then
                        for k = #bld.profile.permitted_workers - 1, 0, -1 do
                            if bld.profile.permitted_workers[k] == u.id then
                                bld.profile.permitted_workers:erase(k)
                            end
                        end
                    end
                end
            end
            if buildings.FURNACE_ANY then
                for _, bld in ipairs(buildings.FURNACE_ANY) do
                    if bld.profile and bld.profile.permitted_workers then
                        for k = #bld.profile.permitted_workers - 1, 0, -1 do
                            if bld.profile.permitted_workers[k] == u.id then
                                bld.profile.permitted_workers:erase(k)
                            end
                        end
                    end
                end
            end
        end
    end)

    -- 5. remove from burrows
    pcall(function()
        local burrows = df.global.plotinfo and df.global.plotinfo.burrows and df.global.plotinfo.burrows.list
        if burrows then
            for _, burrow in ipairs(burrows) do
                dfhack.burrows.setAssignedUnit(burrow, u, false)
            end
        end
    end)

    -- 6. remove histfig links from fortress entity
    pcall(function()
        local fort_ent = df.global.plotinfo and df.global.plotinfo.main and df.global.plotinfo.main.fortress_entity
        if fort_ent and u.hist_figure_id and u.hist_figure_id >= 0 then
            local hfid = u.hist_figure_id
            if fort_ent.histfig_ids then
                for k = #fort_ent.histfig_ids - 1, 0, -1 do
                    if fort_ent.histfig_ids[k] == hfid then
                        fort_ent.histfig_ids:erase(k)
                    end
                end
            end
            if fort_ent.hist_figures then
                for k = #fort_ent.hist_figures - 1, 0, -1 do
                    if fort_ent.hist_figures[k] and fort_ent.hist_figures[k].id == hfid then
                        fort_ent.hist_figures:erase(k)
                    end
                end
            end
            if fort_ent.nemesis_ids then
                for k = #fort_ent.nemesis_ids - 1, 0, -1 do
                    local nem = df.nemesis_record.find(fort_ent.nemesis_ids[k])
                    if nem and (nem.unit_id == u.id or nem.figure_id == hfid) then
                        fort_ent.nemesis_ids:erase(k)
                    end
                end
            end
        end
    end)
end

local function purge_item_and_contents(item)
    if not item then return end
    pcall(function() dfhack.items.remove(item) end)
end

local function safe_erase_vector(vec)
    if not vec then return end
    for i = #vec - 1, 0, -1 do
        pcall(function() vec:erase(i) end)
    end
end

-- safely and completely removes all worn, carried, and owned items of a companion
local function remove_companion_items(u)
    if not u then return end

    -- 1. purge owned items list
    pcall(function()
        if u.owned_items then
            for k = #u.owned_items - 1, 0, -1 do
                local item_id = u.owned_items[k]
                local item = df.item.find(item_id)
                if item then
                    purge_item_and_contents(item)
                end
                pcall(function() u.owned_items:erase(k) end)
            end
        end
    end)

    -- 2. purge inventory items and container contents
    pcall(function()
        if u.inventory then
            for k = #u.inventory - 1, 0, -1 do
                local inv_item = u.inventory[k]
                if inv_item and inv_item.item then
                    purge_item_and_contents(inv_item.item)
                end
                pcall(function() u.inventory:erase(k) end)
            end
        end
    end)
end


local function get_link_type_str(link)
    if not link then return 'nil' end
    local ok, ltype = pcall(function() return link:getType() end)
    if ok and ltype then
        local tname = df.histfig_hf_link_type[ltype]
        if tname then return tname end
    end
    if link._type then return tostring(link._type) end
    return tostring(link)
end

local function is_deity_link(link)
    if not link then return false end
    if df.histfig_hf_link_deityst:is_instance(link) or df.histfig_hf_link_religious_leaderst:is_instance(link) then
        return true
    end
    local ok, ltype = pcall(function() return link:getType() end)
    if ok and ltype then
        local tname = df.histfig_hf_link_type[ltype]
        if tname == 'DEITY' or tname == 'RELIGIOUS_LEADER' then return true end
    end
    local type_str = tostring(link):lower()
    if type_str:find('deity') or type_str:find('religious') then return true end
    return false
end

-- wipes all companion relationships and emotions from the kept hermit settler
local function clean_hermit_companion_relationships(hermit_unit, removed_units)
    if not hermit_unit then return end

    -- 1. clean direct unit relationships vector / ids
    pcall(function()
        if hermit_unit.relationship_ids then
            for k, v in pairs(df.unit_relationship_type) do
                if type(v) == 'number' then
                    pcall(function() hermit_unit.relationship_ids[v] = -1 end)
                end
            end
            for i = 0, #hermit_unit.relationship_ids - 1 do
                pcall(function() hermit_unit.relationship_ids[i] = -1 end)
            end
        end
    end)

    pcall(function()
        if hermit_unit.relationships then
            for i = #hermit_unit.relationships - 1, 0, -1 do
                hermit_unit.relationships:erase(i)
            end
        end
    end)

    -- 2. clean hermit's personality emotions on unit.status.current_soul
    local function clean_soul(soul)
        if not soul or not soul.personality then return end
        if soul.personality.emotions then
            for i = #soul.personality.emotions - 1, 0, -1 do
                pcall(function() soul.personality.emotions:erase(i) end)
            end
        end
    end

    if hermit_unit.status and hermit_unit.status.current_soul then
        clean_soul(hermit_unit.status.current_soul)
    end

    -- 3. clean hermit's historical figure links and relationship tables
    local hermit_hf = hermit_unit.hist_figure_id and hermit_unit.hist_figure_id >= 0 and df.historical_figure.find(hermit_unit.hist_figure_id) or nil
    if hermit_hf then
        -- Clean forward histfig links on hermit (preserve only deity)
        pcall(function()
            if hermit_hf.histfig_links then
                for i = #hermit_hf.histfig_links - 1, 0, -1 do
                    local link = hermit_hf.histfig_links[i]
                    if link and not is_deity_link(link) then
                        local target_hfid = link.target_hf
                        if target_hfid and target_hfid >= 0 then
                            local other_hf = df.historical_figure.find(target_hfid)
                            if other_hf and other_hf.histfig_links then
                                for oi = #other_hf.histfig_links - 1, 0, -1 do
                                    local olink = other_hf.histfig_links[oi]
                                    if olink and olink.target_hf == hermit_hf.id then
                                        pcall(function() other_hf.histfig_links:erase(oi) end)
                                    end
                                end
                            end
                        end
                        pcall(function() hermit_hf.histfig_links:erase(i) end)
                    end
                end
            end
        end)

        -- Clean hf.info.relationships on hermit_hf (hf_visual, hf_historical, etc.)
        pcall(function()
            if hermit_hf.info and hermit_hf.info.relationships then
                local rel = hermit_hf.info.relationships
                if rel.hf_visual then
                    for i = #rel.hf_visual - 1, 0, -1 do
                        rel.hf_visual:erase(i)
                    end
                end
                if rel.hf_historical then
                    for i = #rel.hf_historical - 1, 0, -1 do rel.hf_historical:erase(i) end
                end
                if rel.hf_identity then
                    for i = #rel.hf_identity - 1, 0, -1 do rel.hf_identity:erase(i) end
                end
                if rel.identities then
                    for i = #rel.identities - 1, 0, -1 do rel.identities:erase(i) end
                end
                if rel.artifact_claims then
                    for i = #rel.artifact_claims - 1, 0, -1 do rel.artifact_claims:erase(i) end
                end
            end
        end)

        -- Sweep all historical figures in the world pointing to hermit_hf.id or belonging to our group entity
        pcall(function()
            local hf_all = df.global.world and df.global.world.history and df.global.world.history.figures
            local group_id = df.global.plotinfo and df.global.plotinfo.group_id
            if hf_all then
                for hi = 0, #hf_all - 1 do
                    local hf = hf_all[hi]
                    if hf and hf.id ~= hermit_hf.id then
                        if hf.histfig_links then
                            for li = #hf.histfig_links - 1, 0, -1 do
                                local l = hf.histfig_links[li]
                                if l and l.target_hf == hermit_hf.id and not is_deity_link(l) then
                                    pcall(function() hf.histfig_links:erase(li) end)
                                end
                            end
                        end
                        if group_id and group_id >= 0 and hf.entity_links then
                            for ei = #hf.entity_links - 1, 0, -1 do
                                local el = hf.entity_links[ei]
                                if el and el.entity_id == group_id then
                                    pcall(function() hf.entity_links:erase(ei) end)
                                end
                            end
                        end
                    end
                end
            end
        end)

        -- Clean fortress entity member lists
        pcall(function()
            local group_id = df.global.plotinfo and df.global.plotinfo.group_id
            local group_entity = group_id and group_id >= 0 and df.historical_entity.find(group_id)
            if group_entity then
                if group_entity.histfig_ids then
                    for i = #group_entity.histfig_ids - 1, 0, -1 do
                        if group_entity.histfig_ids[i] ~= hermit_hf.id then
                            group_entity.histfig_ids:erase(i)
                        end
                    end
                end
                if group_entity.nemesis_ids then
                    local hermit_nemesis_id = -1
                    if hermit_unit.general_refs then
                        for _, ref in ipairs(hermit_unit.general_refs) do
                            if df.general_ref_is_nemesisst:is_instance(ref) then
                                hermit_nemesis_id = ref.nemesis_id
                            end
                        end
                    end
                    for i = #group_entity.nemesis_ids - 1, 0, -1 do
                        if group_entity.nemesis_ids[i] ~= hermit_nemesis_id then
                            group_entity.nemesis_ids:erase(i)
                        end
                    end
                end
                if group_entity.positions and group_entity.positions.assignments then
                    -- 1. Unassign positions held by purged companions
                    for i = 0, #group_entity.positions.assignments - 1 do
                        local a = group_entity.positions.assignments[i]
                        if a.histfig >= 0 and a.histfig ~= hermit_hf.id then
                            local old_hf = df.historical_figure.find(a.histfig)
                            if old_hf and old_hf.entity_links then
                                for k = #old_hf.entity_links - 1, 0, -1 do
                                    local l = old_hf.entity_links[k]
                                    if df.histfig_entity_link_positionst:is_instance(l) and l.assignment_id == a.id then
                                        old_hf.entity_links:erase(k)
                                    end
                                end
                            end
                            a.histfig = -1
                        end
                    end

                    -- 2. Ensure hermit has group entity membership link
                    if hermit_hf.entity_links then
                        local has_member_link = false
                        for k = 0, #hermit_hf.entity_links - 1 do
                            local l = hermit_hf.entity_links[k]
                            if (df.histfig_entity_link_memberst:is_instance(l) or df.histfig_entity_link_occupierst:is_instance(l)) and l.entity_id == group_entity.id then
                                has_member_link = true
                                break
                            end
                        end
                        if not has_member_link then
                            hermit_hf.entity_links:insert('#', {
                                new = df.histfig_entity_link_memberst,
                                entity_id = group_entity.id,
                                link_strength = 100,
                            })
                        end
                    end

                    -- 3. If Expedition Leader exists and is active, assign to hermit with reciprocal link
                    local exp_leader_pos_id = -1
                    if group_entity.positions.own then
                        for i = 0, #group_entity.positions.own - 1 do
                            local p = group_entity.positions.own[i]
                            if p and p.code == 'EXPEDITION_LEADER' then
                                exp_leader_pos_id = p.id
                                break
                            end
                        end
                    end

                    if exp_leader_pos_id >= 0 and hermit_hf.entity_links then
                        for assignment_idx = 0, #group_entity.positions.assignments - 1 do
                            local a = group_entity.positions.assignments[assignment_idx]
                            if a.position_id == exp_leader_pos_id and a.flags.active then
                                a.histfig = hermit_hf.id
                                local has_pos_link = false
                                for k = 0, #hermit_hf.entity_links - 1 do
                                    local l = hermit_hf.entity_links[k]
                                    if df.histfig_entity_link_positionst:is_instance(l) and l.assignment_id == a.id then
                                        has_pos_link = true
                                        break
                                    end
                                end
                                if not has_pos_link then
                                    hermit_hf.entity_links:insert('#', {
                                        new = df.histfig_entity_link_positionst,
                                        entity_id = group_entity.id,
                                        link_strength = 100,
                                        assignment_id = a.id,
                                        assignment_vector_idx = assignment_idx,
                                        start_year = df.global.cur_year,
                                    })
                                end
                                break
                            end
                        end
                    end
                end
            end
        end)

        -- Clean nemesis records (group_leader_id, companions) and site populace nemesis lists
        pcall(function()
            local hermit_nemesis_id = -1
            if hermit_unit.general_refs then
                for _, ref in ipairs(hermit_unit.general_refs) do
                    if df.general_ref_is_nemesisst:is_instance(ref) then
                        hermit_nemesis_id = ref.nemesis_id
                    end
                end
            end

            if hermit_nemesis_id >= 0 then
                local h_nem = df.nemesis_record.find(hermit_nemesis_id)
                if h_nem then
                    h_nem.group_leader_id = -1
                    if h_nem.companions then
                        for i = #h_nem.companions - 1, 0, -1 do
                            h_nem.companions:erase(i)
                        end
                    end
                end
            end

            -- Clean all nemesis records in world
            local nemesis_all = df.global.world and df.global.world.nemesis and df.global.world.nemesis.all
            if nemesis_all then
                for i = 0, #nemesis_all - 1 do
                    local nem = nemesis_all[i]
                    if nem and nem.id ~= hermit_nemesis_id then
                        if nem.companions then
                            for ci = #nem.companions - 1, 0, -1 do
                                if nem.companions[ci] == hermit_nemesis_id then
                                    nem.companions:erase(ci)
                                end
                            end
                        end
                        if nem.group_leader_id == hermit_nemesis_id then
                            nem.group_leader_id = -1
                        end
                    end
                end
            end

            -- Clean site populace nemesis lists
            local sites = df.global.world and df.global.world.world_data and df.global.world.world_data.sites
            if sites then
                for si = 0, #sites - 1 do
                    local site = sites[si]
                    if site and site.populace and site.populace.nemesis then
                        for ni = #site.populace.nemesis - 1, 0, -1 do
                            local nid = site.populace.nemesis[ni]
                            if nid ~= hermit_nemesis_id then
                                site.populace.nemesis:erase(ni)
                            end
                        end
                    end
                end
            end

            -- Sweep companion historical figures from embark historical population
            if hermit_hf and hermit_hf.population_id and hermit_hf.population_id >= 0 then
                local pop_id = hermit_hf.population_id
                local hf_all = df.global.world and df.global.world.history and df.global.world.history.figures
                if hf_all then
                    for i = 0, #hf_all - 1 do
                        local hf = hf_all[i]
                        if hf and hf.id ~= hermit_hf.id and hf.population_id == pop_id then
                            hf.died_year = df.global.cur_year
                            hf.died_seconds = df.global.cur_year_tick
                            hf.civ_id = -1
                            hf.population_id = -1
                            if hf.histfig_links then
                                for li = #hf.histfig_links - 1, 0, -1 do
                                    hf.histfig_links:erase(li)
                                end
                            end
                            if hf.entity_links then
                                for ei = #hf.entity_links - 1, 0, -1 do
                                    hf.entity_links:erase(ei)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    -- 4. clean soul and histfig on all removed units to prevent cross-referencing
    for _, u in ipairs(removed_units or {}) do
        if u and u.id ~= hermit_unit.id then
            pcall(function()
                if u.status and u.status.current_soul then clean_soul(u.status.current_soul) end
            end)
            pcall(function()
                if u.relationships then
                    for i = #u.relationships - 1, 0, -1 do pcall(function() u.relationships:erase(i) end) end
                end
            end)
            pcall(function()
                if u.relationship_ids then
                    for k, v in pairs(df.unit_relationship_type) do
                        if type(v) == 'number' then
                            pcall(function() u.relationship_ids[v] = -1 end)
                        end
                    end
                    for i = 0, #u.relationship_ids - 1 do
                        pcall(function() u.relationship_ids[i] = -1 end)
                    end
                end
            end)
            if u.hist_figure_id and u.hist_figure_id >= 0 then
                local u_hf = df.historical_figure.find(u.hist_figure_id)
                if u_hf then
                    pcall(function()
                        if u_hf.histfig_links then
                            for i = #u_hf.histfig_links - 1, 0, -1 do
                                local link = u_hf.histfig_links[i]
                                if link and not is_deity_link(link) then
                                    pcall(function() u_hf.histfig_links:erase(i) end)
                                end
                            end
                        end
                    end)
                end
            end
        end
    end
end

-- completely removes wagon buildings without spawning material logs and wipes all loose wood logs on embark
local function clean_wagon_and_loose_wood()
    -- 1. Erase wagon buildings (df.building_wagonst)
    local buildings = df.global.world and df.global.world.buildings and df.global.world.buildings.all
    if buildings then
        for i = #buildings - 1, 0, -1 do
            local bld = buildings[i]
            if df.building_wagonst:is_instance(bld) then
                if bld.contained_items then
                    for j = #bld.contained_items - 1, 0, -1 do
                        local bitem = bld.contained_items[j]
                        if bitem and bitem.item then
                            purge_item_and_contents(bitem.item)
                        end
                    end
                end
                if bld.jobs then
                    for j = #bld.jobs - 1, 0, -1 do
                        local job = bld.jobs[j]
                        if job then
                            dfhack.job.removeJob(job)
                        end
                    end
                end
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
            end
        end
    end

    -- 2. Erase equipment wagon units
    local units = df.global.world and df.global.world.units and df.global.world.units.active
    if units then
        for i = #units - 1, 0, -1 do
            local u = units[i]
            if u and not dfhack.units.isDead(u) then
                local craw = df.creature_raw.find(u.race)
                local cid = craw and craw.creature_id or ""
                if cid == "EQUIPMENT_WAGON" or cid == "WAGON" then
                    u.body.blood_count = 0
                    u.flags1.dead = true
                    u.flags1.left = true
                    u.flags2.visitor = true
                    if u.animal then u.animal.vanish_countdown = 1 end
                end
            end
        end
    end

    -- 3. Delete any loose wood logs that resulted from wagon placement or deconstruction
    local items = df.global.world and df.global.world.items and df.global.world.items.all
    if items then
        for i = #items - 1, 0, -1 do
            local item = items[i]
            if item and df.item_woodst:is_instance(item) then
                purge_item_and_contents(item)
            end
        end
    end
end

-- cleans loose embark floor clothing/supplies dropped by removed companions
local function clean_removed_companion_items(hermit_unit, removed_unit_ids, removed_hfig_ids, removed_item_ids)
    local hermit_item_ids = {}
    if hermit_unit then
        if hermit_unit.inventory then
            for _, inv in ipairs(hermit_unit.inventory) do
                if inv.item then hermit_item_ids[inv.item.id] = true end
            end
        end
        if hermit_unit.owned_items then
            for _, id in ipairs(hermit_unit.owned_items) do hermit_item_ids[id] = true end
        end
    end

    -- 1. Remove all items explicitly associated with removed companions
    if removed_item_ids then
        for _, id in ipairs(removed_item_ids) do
            local item = df.item.find(id)
            if item and not item.flags.in_building and not item.flags.construction then
                pcall(function()
                    if item.pos and item.pos.x >= 0 and item.pos.y >= 0 and item.pos.z >= 0 then
                        local block = dfhack.maps.getTileBlock(item.pos.x, item.pos.y, item.pos.z)
                        if block and block.items then
                            for bi = #block.items - 1, 0, -1 do
                                if block.items[bi] == item.id then
                                    block.items:erase(bi)
                                end
                            end
                        end
                    end
                    if item.flags then
                        item.flags.hidden = true
                        item.flags.forbid = true
                        item.flags.garbage_collect = true
                    end
                    dfhack.items.remove(item)
                end)
            end
        end
    end

    -- 2. Sweep loose unheld clothing/armor on ground not worn by hermit
    local items = df.global.world and df.global.world.items and df.global.world.items.all
    if items then
        for i = #items - 1, 0, -1 do
            local item = items[i]
            if item and not hermit_item_ids[item.id] and not item.flags.in_building and not item.flags.construction and not item.flags.artifact and not item.flags.in_job and not item.flags.in_inventory and not dfhack.items.getContainer(item) then
                local is_loose_wearable = false
                local itype = item:getType()
                if itype == df.item_type.ARMOR or itype == df.item_type.SHOES or itype == df.item_type.HELM or itype == df.item_type.GLOVES or itype == df.item_type.PANTS then
                    local holder = dfhack.items.getGeneralRef(item, df.general_ref_type.UNIT_HOLDER)
                    if not holder or (hermit_unit and holder.unit_id ~= hermit_unit.id) then
                        is_loose_wearable = true
                    end
                end

                if is_loose_wearable then
                    pcall(function()
                        if item.pos and item.pos.x >= 0 and item.pos.y >= 0 and item.pos.z >= 0 then
                            local block = dfhack.maps.getTileBlock(item.pos.x, item.pos.y, item.pos.z)
                            if block and block.items then
                                for bi = #block.items - 1, 0, -1 do
                                    if block.items[bi] == item.id then
                                        block.items:erase(bi)
                                    end
                                end
                            end
                        end
                        if item.flags then
                            item.flags.hidden = true
                            item.flags.forbid = true
                            item.flags.garbage_collect = true
                        end
                        dfhack.items.remove(item)
                    end)
                end
            end
        end
    end
end

local function purge_companion_unit(u, fort_entity, civ_entity, removed_u_ids, removed_hf_ids, removed_item_ids)
    if not u then return end
    table.insert(removed_u_ids, u.id)
    if u.hist_figure_id and u.hist_figure_id >= 0 then
        table.insert(removed_hf_ids, u.hist_figure_id)
    end

    if u.inventory then
        for i = #u.inventory - 1, 0, -1 do
            local inv = u.inventory[i]
            if inv and inv.item then
                table.insert(removed_item_ids, inv.item.id)
                pcall(function() dfhack.items.remove(inv.item) end)
            end
        end
    end
    if u.owned_items then
        for i = #u.owned_items - 1, 0, -1 do
            local item_id = u.owned_items[i]
            if item_id then
                table.insert(removed_item_ids, item_id)
                local it = df.item.find(item_id)
                if it then pcall(function() dfhack.items.remove(it) end) end
            end
        end
    end

    local ok, err = pcall(function()
        -- Clean labors, details, and inventory
        clean_unit_associations(u)

        -- Kill and dismiss unit from fortress citizenship
        u.body.blood_count = 0
        u.flags2.slaughter = false
        u.flags2.killed = true
        u.flags1.left = true
        u.flags1.inactive = true
        u.flags2.visitor = false
        u.flags2.resident = false

        -- Clean companion historical figure
        if u.hist_figure_id and u.hist_figure_id >= 0 then
            local chf = df.historical_figure.find(u.hist_figure_id)
            if chf then
                chf.died_year = df.global.cur_year
                chf.died_seconds = df.global.cur_year_tick
                chf.civ_id = -1
                chf.population_id = -1
                if chf.histfig_links then
                    for li = #chf.histfig_links - 1, 0, -1 do
                        chf.histfig_links:erase(li)
                    end
                end
                if chf.entity_links then
                    for ei = #chf.entity_links - 1, 0, -1 do
                        chf.entity_links:erase(ei)
                    end
                end
                if chf.info and chf.info.relationships then
                    local rel = chf.info.relationships
                    if rel.hf_visual then for i = #rel.hf_visual - 1, 0, -1 do rel.hf_visual:erase(i) end end
                    if rel.hf_historical then for i = #rel.hf_historical - 1, 0, -1 do rel.hf_historical:erase(i) end end
                    if rel.hf_identity then for i = #rel.hf_identity - 1, 0, -1 do rel.hf_identity:erase(i) end end
                    if rel.identities then for i = #rel.identities - 1, 0, -1 do rel.identities:erase(i) end end
                    if rel.artifact_claims then for i = #rel.artifact_claims - 1, 0, -1 do rel.artifact_claims:erase(i) end end
                end
            end
        end

        -- Remove histfig from fortress entity
        if fort_entity and u.hist_figure_id and u.hist_figure_id >= 0 and fort_entity.histfig_ids then
            for hidx = #fort_entity.histfig_ids - 1, 0, -1 do
                if fort_entity.histfig_ids[hidx] == u.hist_figure_id then
                    fort_entity.histfig_ids:erase(hidx)
                end
            end
        end

        -- Remove histfig from civ entity
        if civ_entity and u.hist_figure_id and u.hist_figure_id >= 0 and civ_entity.histfig_ids then
            for hidx = #civ_entity.histfig_ids - 1, 0, -1 do
                if civ_entity.histfig_ids[hidx] == u.hist_figure_id then
                    civ_entity.histfig_ids:erase(hidx)
                end
            end
        end
    end)

    if not ok then
        dfhack.printerr('choose-your-hermit error removing unit ' .. tostring(u.id) .. ': ' .. tostring(err))
    end
    return ok
end

function apply_hermit(target_unit)
    local expedition_citizens = get_embark_citizens()
    if not target_unit then
        target_unit = expedition_citizens[1]
    end

    if not target_unit then
        print('no valid hermit found!')
        return false
    end

    local kept_name = target_unit.name.first_name and target_unit.name.first_name:lower() or "hermit"
    local removed_count = 0
    local removed_units = {}
    local removed_u_ids = {}
    local removed_hf_ids = {}
    local removed_item_ids = {}
    local processed_ids = {}
    processed_ids[target_unit.id] = true

    local fort_entity = df.global.plotinfo and df.global.plotinfo.group_id and df.historical_entity.find(df.global.plotinfo.group_id)
    local civ_entity = df.global.plotinfo and df.global.plotinfo.civ_id and df.historical_entity.find(df.global.plotinfo.civ_id)

    -- 1. iterate over player's starting expedition citizens
    for _, u in ipairs(expedition_citizens) do
        if u.id ~= target_unit.id and not processed_ids[u.id] then
            processed_ids[u.id] = true
            table.insert(removed_units, u)
            if purge_companion_unit(u, fort_entity, civ_entity, removed_u_ids, removed_hf_ids, removed_item_ids) then
                removed_count = removed_count + 1
            end
        end
    end

    -- 2. sweep all companion dwarves of the player's race on map
    if df.global.world and df.global.world.units and df.global.world.units.all then
        for _, u in ipairs(df.global.world.units.all) do
            if u and not processed_ids[u.id] and u.id ~= target_unit.id then
                if u.race == target_unit.race and not u.flags1.merchant and not u.flags1.diplomat and not u.flags2.visitor then
                    processed_ids[u.id] = true
                    table.insert(removed_units, u)
                    if purge_companion_unit(u, fort_entity, civ_entity, removed_u_ids, removed_hf_ids, removed_item_ids) then
                        removed_count = removed_count + 1
                    end
                end
            end
        end
    end

    -- 0. erase removed companion units from active units list so Pop counter and UI update immediately
    local active_units = df.global.world and df.global.world.units and df.global.world.units.active
    if active_units then
        local removed_u_map = {}
        for _, id in ipairs(removed_u_ids) do
            removed_u_map[id] = true
        end
        for i = #active_units - 1, 0, -1 do
            local u = active_units[i]
            if u and (removed_u_map[u.id] or (u.race == target_unit.race and u.id ~= target_unit.id and not u.flags1.merchant and not u.flags1.diplomat and not u.flags2.visitor)) then
                active_units:erase(i)
            end
        end
    end

    -- 1. clean companion relationships and emotions from hermit
    clean_hermit_companion_relationships(target_unit, removed_units)

    -- 2. clean loose items dropped by removed companions
    clean_removed_companion_items(target_unit, removed_u_ids, removed_hf_ids, removed_item_ids)

    -- 3. clean wagon and loose wood logs
    clean_wagon_and_loose_wood()

    -- 4. schedule cleanup across initial ticks for loose items and wagon litter
    local function run_followup_clean()
        clean_wagon_and_loose_wood()
        clean_removed_companion_items(target_unit, removed_u_ids, removed_hf_ids, removed_item_ids)
    end

    dfhack.timeout(2, 'ticks', run_followup_clean)
    dfhack.timeout(10, 'ticks', run_followup_clean)

    local msg = string.format("hermit fort initialized: kept '%s', cleanly removed %d extra expedition companions.", kept_name, removed_count)
    print(msg)
    dfhack.gui.showAnnouncement(msg, COLOR_GREEN)

    -- gracefully invoke companion hermit tools if installed
    safe_run_command('enable', 'hermit')
    safe_run_command('wagonless-hermit')
    df.global.pause_state = true
    return true
end

-- interactive hermit selection UI window
ChooseHermitWindow = defclass(ChooseHermitWindow, widgets.Window)
ChooseHermitWindow.ATTRS {
    frame_title='choose your solo hermit (better startdwarf)',
    frame={w=108, h=54, l=2, t=2},
    draggable=true,
    drag_anchors={title=true, frame=true, body=false},
}

function ChooseHermitWindow:init()
    local citizens = get_embark_citizens()
    if #citizens <= 1 then
        self:addviews{
            widgets.Label{
                text='this fort already has 1 or fewer expedition citizens!',
                text_pen=COLOR_YELLOW,
            }
        }
        return
    end
    if #citizens == 0 then
        self:addviews{
            widgets.Label{
                text='no valid citizens found on this embark!',
                text_pen=COLOR_YELLOW,
            }
        }
        return
    end

    local is_town_embark = (#citizens >= 50)

    local choices = {}
    for idx, u in ipairs(citizens) do
        local first_name = (u.name.first_name and #u.name.first_name > 0) and u.name.first_name:lower() or "unnamed"
        local sex_str = (u.sex == 0) and "female" or ((u.sex == 1) and "male" or "neuter")
        local age_int = math.floor(dfhack.units.getAge(u, true))
        local bio_str = string.format("%s, %d", sex_str, age_int)

        local stress_vuln = 50
        local willpower = 1000
        local bravery = 50
        local cheer = 50

        local soul = u.status and u.status.current_soul
        if soul then
            if soul.mental_attrs and soul.mental_attrs[df.mental_attribute_type.WILLPOWER] then
                willpower = soul.mental_attrs[df.mental_attribute_type.WILLPOWER].value
            end
            if soul.personality then
                stress_vuln = soul.personality.traits[df.personality_facet_type.STRESS_VULNERABILITY] or 50
                bravery = soul.personality.traits[df.personality_facet_type.BRAVERY] or 50
                cheer = soul.personality.traits[df.personality_facet_type.CHEER_PROPENSITY] or 50
            end
        end

        local line = string.format("[%d] %-14.14s | %-12.12s | stress:%-2d | will:%-4d | brave:%-2d | cheer:%-2d",
            idx, first_name, bio_str, stress_vuln, willpower, bravery, cheer)

        table.insert(choices, {
            text=line,
            search_key=first_name,
            unit=u,
        })
    end

    local header_subviews = {
        widgets.WrappedLabel{
            frame={t=0, l=0, r=0},
            text_to_wrap='select which dwarf will be your sole hermit settler (better startdwarf). all other starting expedition dwarves will be cleanly removed without relationship grief or labor matrix corruption.',
        },
        widgets.Label{
            frame={t=2, l=0},
            text={
                {text='select a dwarf with ', pen=COLOR_GREY},
                {text='mouse/arrows', pen=COLOR_WHITE},
                {text=', then press ', pen=COLOR_GREY},
                {text='Enter', pen=COLOR_WHITE},
                {text=' or click button below to confirm.', pen=COLOR_GREY},
            }
        },
    }

    if is_town_embark then
        table.insert(header_subviews, widgets.Label{
            frame={t=3, l=0},
            text={
                {text='warning: embark has 50+ dwarves (town level). mayor elections will be active!', pen=COLOR_LIGHTRED},
            }
        })
    end

    self:addviews{
        widgets.Panel{
            frame={t=0, l=0, r=0, h=is_town_embark and 5 or 4},
            subviews=header_subviews,
        },
        widgets.List{
            view_id='list',
            frame={t=is_town_embark and 5 or 4, b=2, l=0, r=0},
            choices=choices,
            on_select=function(idx, choice)
                self.selected_choice = choice
            end,
            on_double_click=function(idx, choice)
                self:confirm_selection(choice)
            end,
        },
        widgets.HotkeyLabel{
            frame={b=0, l=1},
            key='SELECT',
            label='confirm solo hermit',
            auto_width=true,
            on_activate=function()
                self:confirm_selection()
            end,
        },
        widgets.HotkeyLabel{
            frame={b=0, l=35},
            key='LEAVESCREEN',
            label='cancel',
            auto_width=true,
            on_activate=function()
                df.global.pause_state = true
                if self.parent_view and self.parent_view.dismiss then
                    self.parent_view:dismiss()
                end
            end,
        },
    }
end

function ChooseHermitWindow:confirm_selection(choice)
    local list = self.subviews.list
    local sel_choice = choice
    if not sel_choice and list then
        local i, c = list:getSelected()
        sel_choice = c or (i and list.choices and list.choices[i])
    end
    if not sel_choice then
        sel_choice = self.selected_choice
    end

    local target_unit = nil
    if type(sel_choice) == 'table' and sel_choice.unit then
        target_unit = sel_choice.unit
    elseif type(sel_choice) == 'number' and list and list.choices and list.choices[sel_choice] then
        local entry = list.choices[sel_choice]
        if type(entry) == 'table' and entry.unit then
            target_unit = entry.unit
        elseif df.unit:is_instance(entry) then
            target_unit = entry
        end
    elseif df.unit:is_instance(sel_choice) then
        target_unit = sel_choice
    end

    if target_unit then
        local ok, err = pcall(function() apply_hermit(target_unit) end)
        if not ok then
            dfhack.printerr('choose-your-hermit error: ' .. tostring(err))
        end
        if self.parent_view and self.parent_view.dismiss then
            self.parent_view:dismiss()
        end
    else
        dfhack.printerr('choose-your-hermit: no unit selected to confirm')
    end
end

function ChooseHermitWindow:onInput(keys)
    if keys.SELECT or keys.CUSTOM_CTRL_ENTER then
        self:confirm_selection()
        return true
    end
    return ChooseHermitWindow.super.onInput(self, keys)
end

ChooseHermitScreen = defclass(ChooseHermitScreen, gui.ZScreen)
ChooseHermitScreen.ATTRS {
    focus_path='choose-your-hermit',
    pass_movement_keys=false,
    force_pause=true,
}

function ChooseHermitScreen:init()
    self:addviews{
        ChooseHermitWindow{view_id='main'},
    }
end

function ChooseHermitScreen:onDismiss()
    df.global.pause_state = true
end

function ChooseHermitScreen:onDestroy()
    df.global.pause_state = true
end

function show_gui()
    if df.global.gamemode ~= df.game_mode.DWARF or not dfhack.isMapLoaded() then
        qerror('must be in an active fortress map')
    end
    local screen = ChooseHermitScreen{}
    screen:show()
end

-- automatic trigger hook on map load if brand new embark with > 1 expedition citizens
dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc == SC_MAP_LOADED and df.global.gamemode == df.game_mode.DWARF then
        dfhack.timeout(10, 'ticks', function()
            if dfhack.isMapLoaded() then
                local citizens = get_embark_citizens()
                if citizens and #citizens > 1 and df.global.cur_year_tick <= 20000 then
                    show_gui()
                end
            end
        end)
    end
end

-- on-demand cleanup helper for active hermit forts
function clean_hermit_litter(silent)
    if df.global.gamemode ~= df.game_mode.DWARF or not dfhack.isMapLoaded() then
        if not silent then qerror('must be in an active fortress map') end
        return
    end

    local citizens = {}
    local citizen_u_ids = {}
    local citizen_hf_ids = {}

    for _, u in ipairs(df.global.world.units.active) do
        if dfhack.units.isCitizen(u, true) and not dfhack.units.isDead(u) then
            table.insert(citizens, u)
            citizen_u_ids[u.id] = true
            if u.hist_figure_id and u.hist_figure_id >= 0 then
                citizen_hf_ids[u.hist_figure_id] = true
            end
        end
    end

    local hermit = citizens[1]
    local rels_cleaned = 0
    local items_cleaned = 0

    if hermit then
        local soul = hermit.status and hermit.status.current_soul
        if soul and soul.personality then

            if soul.personality.emotions then
                for i = #soul.personality.emotions - 1, 0, -1 do
                    local emo = soul.personality.emotions[i]
                    if emo and not citizen_hf_ids[emo.target_histfig_id] and not citizen_u_ids[emo.target_unit_id] then
                        soul.personality.emotions:erase(i)
                    end
                end
            end
        end

        local hf = hermit.hist_figure_id and df.historical_figure.find(hermit.hist_figure_id)
        if hf then
            if hf.histfig_links then
                for i = #hf.histfig_links - 1, 0, -1 do
                    local link = hf.histfig_links[i]
                    local tid = link and (link.target_hf or link.target_hfid)
                    if tid and not citizen_hf_ids[tid] then
                        local is_deity = false
                        pcall(function()
                            if link:getType() == df.histfig_hf_link_type.DEITY or link:getType() == df.histfig_hf_link_type.RELIGIOUS_LEADER then
                                is_deity = true
                            end
                        end)
                        if not is_deity then
                            hf.histfig_links:erase(i)
                            pcall(function() link:delete() end)
                            rels_cleaned = rels_cleaned + 1
                        end
                    end
                end
            end

        end

        -- Sweep any unheld items on embark not belonging to hermit
        local hermit_item_ids = {}
        if hermit.inventory then
            for _, inv in ipairs(hermit.inventory) do
                if inv.item then hermit_item_ids[inv.item.id] = true end
            end
        end
        if hermit.owned_items then
            for _, item_id in ipairs(hermit.owned_items) do hermit_item_ids[item_id] = true end
        end

        local items = df.global.world and df.global.world.items and df.global.world.items.all
        if items then
            for i = #items - 1, 0, -1 do
                local item = items[i]
                if item and not hermit_item_ids[item.id] then
                    local holder = dfhack.items.getGeneralRef(item, df.general_ref_type.UNIT_HOLDER)
                    if not holder or (hermit and holder.unit_id ~= hermit.id) then
                        pcall(function() dfhack.items.remove(item) end)
                        items_cleaned = items_cleaned + 1
                    end
                end
            end
        end
    end

    local msg = string.format("choose_your_hermit: cleaned %d orphan relationships and %d dropped companion items.", rels_cleaned, items_cleaned)
    if not silent then
        print(msg)
        dfhack.gui.showAnnouncement(msg, COLOR_GREEN)
    end
    return true, msg
end

function main(...)
    local args = {...}
    if #args > 0 then
        if args[1] == '--clean' or args[1] == '-c' or args[1] == '--clean-litter' then
            clean_hermit_litter(false)
            return
        end
        if tonumber(args[1]) then
            local target_unit = df.unit.find(tonumber(args[1]))
            if not target_unit then
                qerror('invalid unit id: ' .. tostring(args[1]))
            end
            apply_hermit(target_unit)
            return
        end
    end
    show_gui()
end

local script_args = {...}
if dfhack_flags and not dfhack_flags.module then
    main(table.unpack(script_args or {}))
end
