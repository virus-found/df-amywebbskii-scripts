--[====[

embark-neighbors
================

A live viewport embark neighbor scanner that dynamically displays nearest sites, civilizations, and nomadic groups around the cursor on the embark map.

Inspired by and modeled after the algorithm of Steam mod 3334773931 ("Embark Neighbors Extended" by Zeallot).

Features
--------
- Draggable and movable GUI window anywhere on screen with mouse.
- Multi-line site ownership header for long faction and government names.
- Ocean & landmass reachability awareness (ignores sites separated by oceans).
- Unified, consistent diplomatic stance evaluation matching native DF logic.
- Compact lowercase travel time distance ("1/2 day sw", "1 day ne", "2 days w", "here", "short trip nw", "5 days se").
- 5-column structured layout: Distance & Dir | Race | Population (war vs site) | Settlement Type | Settlement Name.
- Lowercase population estimates matching native DF magnitudes ("few", "scores", "over a hundred", "hundreds", "thousands", "tens of thousands").
- Color-coded rows by diplomatic stance with a top legend (Red = Hostile to Player, Blue = Peaceful, White = Neutral).
- Explicit detection of active war between neighbors and the occupied site owner ("(war vs site)").

Usage
-----
    embark-neighbors         (opens the interactive draggable GUI window)
    embark-neighbors --cli   (prints output to console)
    neighbors                (alias)

]====]

--@module = true

local gui = require('gui')
local widgets = require('gui.widgets')

local function safe_get(fn)
    local ok, res = pcall(fn)
    if ok and res ~= nil then return res end
    return nil
end

-- checks if two world positions are connected by land without crossing ocean (elevation < 100)
local function is_land_connected(x1, y1, x2, y2)
    local ok, res = pcall(function()
        local world = df.global.world and df.global.world.world_data
        if not world or not world.region_map then return true end
        local dx = x2 - x1
        local dy = y2 - y1
        local steps = math.max(math.abs(dx), math.abs(dy)) * 2
        if steps <= 0 then return true end

        local max_w = world.world_width or 256
        local max_h = world.world_height or 256

        for step = 0, steps do
            local t = step / steps
            local ix = math.floor(x1 + dx * t + 0.5)
            local iy = math.floor(y1 + dy * t + 0.5)
            if ix >= 0 and ix < max_w and iy >= 0 and iy < max_h then
                local row = world.region_map[ix]
                if row then
                    local entry = row:_displace(iy)
                    if entry and entry.elevation and entry.elevation < 100 then
                        return false
                    end
                end
            end
        end
        return true
    end)
    if ok then return res end
    return true
end

-- resolves any site government or sub-entity to its parent civilization if linked
local function get_effective_civ(ent)
    if not ent then return nil end
    if ent.type == df.historical_entity_type.Civilization then
        return ent
    end
    if ent.type == df.historical_entity_type.Tower or (ent.entity_raw and ent.entity_raw.code:find("TOWER")) then
        return ent
    end
    local links = safe_get(function() return ent.entity_links end)
    if links then
        for _, link in ipairs(links) do
            local target = safe_get(function() return df.historical_entity.find(link.target) end)
            if target and target.type == df.historical_entity_type.Civilization then
                return target
            end
        end
    end
    return ent
end

-- formats entity race cleanly, detecting towers and necromancer factions
local function format_entity_race(ent)
    if not ent then return "unknown" end
    if ent.type == df.historical_entity_type.Tower or (ent.entity_raw and ent.entity_raw.code:find("TOWER")) then
        return "tower"
    end
    local links = safe_get(function() return ent.entity_links end)
    if links then
        for _, el in ipairs(links) do
            local parent = safe_get(function() return df.historical_entity.find(el.target) end)
            if parent and (parent.type == df.historical_entity_type.Tower or (parent.entity_raw and parent.entity_raw.code:find("TOWER"))) then
                return "tower"
            end
        end
    end
    if ent.race >= 0 and df.creature_raw.find(ent.race) then
        return df.creature_raw.find(ent.race).name[1]:lower()
    elseif ent.entity_raw then
        local code = ent.entity_raw.code:lower()
        if code:find("tower") or code:find("necro") then
            return "tower"
        end
        return code
    end
    return "unknown"
end

-- resolves the authoritative active occupant/ruler of a site, checking active site_links if cur_owner_id is unset
local function get_site_active_occupant(site)
    if not site then return nil end
    if site.cur_owner_id and site.cur_owner_id >= 0 then
        local ent = df.historical_entity.find(site.cur_owner_id)
        if ent then return ent end
    end
    local resident_gov = nil
    local reclaimer_civ = nil
    local holder_civ = nil
    for _, ent in ipairs(df.global.world.entities.all) do
        if ent.site_links then
            for _, sl in ipairs(ent.site_links) do
                if sl.target == site.id then
                    if sl.flags.reclaim then
                        reclaimer_civ = ent
                    elseif sl.flags.residence and ent.type == df.historical_entity_type.SiteGovernment then
                        resident_gov = ent
                    elseif sl.flags.land_holder_residence and not holder_civ then
                        holder_civ = ent
                    end
                end
            end
        end
    end
    if resident_gov then return resident_gov end
    if reclaimer_civ then return reclaimer_civ end
    if holder_civ then return holder_civ end
    if site.civ_id and site.civ_id >= 0 then
        return df.historical_entity.find(site.civ_id)
    end
    return nil
end

-- calculates compact lowercase cardinal direction abbreviation matching vanilla DF
local function calculate_direction(cur_x, cur_y, site_x, site_y)
    local dx = site_x - cur_x
    local dy = site_y - cur_y

    if math.abs(dx) < 0.2 and math.abs(dy) < 0.2 then
        return "here"
    end

    if math.abs(dx) > 2 * math.abs(dy) then
        return dx > 0 and "east" or "west"
    elseif math.abs(dy) > 2 * math.abs(dx) then
        return dy > 0 and "south" or "north"
    else
        local v = dy > 0 and "s" or "n"
        local h = dx > 0 and "e" or "w"
        return v .. h
    end
end

-- formats raw embark distance units into compact travel strings matching game UI (all lowercase)
local function format_travel_time(raw_dist, dir)
    if raw_dist == 0 then
        return "here"
    end
    if not raw_dist or raw_dist < 0 or raw_dist >= 9000 then
        return ""
    end

    local prefix = ""
    if raw_dist <= 2 then
        prefix = "short trip"
    elseif raw_dist <= 7 then
        prefix = "1/2 day"
    elseif raw_dist <= 17 then
        prefix = "1 day"
    elseif raw_dist <= 26 then
        prefix = "2 days"
    elseif raw_dist <= 35 then
        prefix = "3 days"
    else
        local days = math.floor((raw_dist + 4) / 10)
        if days <= 3 then days = 4 end
        prefix = string.format("%d days", days)
    end

    if dir == "here" or dir == "" then
        return prefix
    end
    return string.format("%s %s", prefix, dir:lower())
end

-- formats population magnitudes matching vanilla df embark display (all lowercase)
local function format_population(pop)
    if type(pop) ~= 'number' then return "" end
    if pop < 10 then
        return "few"
    elseif pop < 50 then
        return "dozens"
    elseif pop < 200 then
        return "a hundred"
    elseif pop < 500 then
        return "hundreds"
    elseif pop < 2000 then
        return "a thousand"
    elseif pop < 10000 then
        return "thousands"
    else
        return "tens of thousands"
    end
end

local function format_est_pop(val)
    if val == nil or type(val) ~= 'number' then return "" end
    if val <= 0 then
        return "0"
    elseif val <= 10 then
        return "~10"
    else
        local rounded = math.floor((val + 5) / 10) * 10
        return string.format("~%d", rounded)
    end
end

local function get_site_actual_live_pop(site, stype_str)
    if not site then return nil end
    local inh_total = 0
    if site.populace and site.populace.inhabitants then
        for i = 0, #site.populace.inhabitants - 1 do
            inh_total = inh_total + (site.populace.inhabitants[i].count or 0)
        end
    end
    local nem_count = (site.populace and site.populace.nemesis) and #site.populace.nemesis or 0
    local infra = site.infrastructure_pop_level or 0
    local t = (stype_str or (df.world_site_type[site.type] or "")):lower()

    local base_pop = inh_total + nem_count

    if t:find("fortress") or t:find("darkfortress") or t:find("castle") or t:find("tower") or t:find("pit") or t:find("vault") then
        local garrison = math.max(infra * 2, nem_count * 20, 50)
        base_pop = math.max(base_pop, garrison + nem_count)
    elseif t:find("camp") then
        local garrison = math.max(infra, nem_count * 10, 20)
        base_pop = math.max(base_pop, garrison + nem_count)
    elseif t:find("cave") or t:find("lair") or t:find("shrine") or t:find("tomb") or t:find("monument") then
        base_pop = nem_count
    elseif t:find("town") or t:find("city") or t:find("mountainhall") or t:find("hamlet") or t:find("hillock") or t:find("retreat") then
        if inh_total > 0 then
            base_pop = math.max(base_pop, inh_total + math.floor(infra * 0.5) + nem_count)
        else
            base_pop = nem_count
        end
    end

    return base_pop
end

local function estimate_spawn_population(stype, raw_pop, history_pop, site)
    local live = get_site_actual_live_pop(site, stype)
    if live ~= nil then
        return format_est_pop(live)
    end

    local t = (stype or ""):lower()
    local p = (history_pop or ""):lower()

    local scale = 1
    if p:find("thousand") or (type(raw_pop) == 'number' and raw_pop >= 1000) then
        scale = 4
    elseif p:find("hundreds") or (type(raw_pop) == 'number' and raw_pop >= 200) then
        scale = 3
    elseif p:find("hundred") or (type(raw_pop) == 'number' and raw_pop >= 50) then
        scale = 2
    else
        scale = 1
    end

    local est = 10
    if t:find("hamlet") or t:find("hillock") or t:find("camp") or t:find("retreat") then
        if scale == 1 then est = 10
        elseif scale == 2 then est = 20
        elseif scale == 3 then est = 30
        else est = 40 end
    elseif t:find("fort") or t:find("castle") or t:find("tower") or t:find("pit") then
        if scale == 1 then est = 50
        elseif scale == 2 then est = 80
        elseif scale == 3 then est = 120
        else est = 200 end
    elseif t:find("town") or t:find("city") or t:find("mountainhall") then
        if scale == 1 then est = 20
        elseif scale == 2 then est = 60
        elseif scale == 3 then est = 120
        else est = 300 end
    elseif t:find("cave") or t:find("lair") or t:find("shrine") or t:find("vault") or t:find("tomb") or t:find("monument") then
        if scale == 1 then est = 10
        elseif scale == 2 then est = 20
        elseif scale == 3 then est = 30
        else est = 50 end
    else
        if scale == 1 then est = 10
        elseif scale == 2 then est = 20
        elseif scale == 3 then est = 40
        else est = 80 end
    end

    return format_est_pop(est)
end

-- calculates site category priority (civilized towns/fortresses take precedence over monuments)
local function get_site_category_priority(site)
    if not site then return 0 end
    local t = site.type
    if t == df.world_site_type.Town or t == df.world_site_type.DarkFortress or t == df.world_site_type.MountainHalls or t == df.world_site_type.Fortress or t == df.world_site_type.Castle or t == df.world_site_type.Retreat then
        return 50
    elseif t == df.world_site_type.Hamlet or t == df.world_site_type.Hillock or t == df.world_site_type.Camp or t == df.world_site_type.DarkPits then
        return 40
    elseif t == df.world_site_type.Cave or t == df.world_site_type.LairShrine or t == df.world_site_type.Vault then
        return 20
    elseif t == df.world_site_type.Monument or t == df.world_site_type.Tomb then
        return 10
    else
        return 30
    end
end

-- formats site type names cleanly in lowercase matching vanilla DF site classification
local function format_site_type(site)
    if not site then return "" end
    local raw_t = safe_get(function() return df.world_site_type[site.type] or site.type end)
    if not raw_t then return "" end
    local t_str = tostring(raw_t):lower():gsub("_", " ")

    if site.type == df.world_site_type.Town or t_str:find("town") then
        local b_cnt = site.buildings and #site.buildings or 0
        if b_cnt <= 1 then
            return "hamlet"
        else
            return "town"
        end
    end
    return t_str
end

-- check if two entities are at active war
local function check_entities_at_war(ent1, ent2)
    if not ent1 or not ent2 then return false end
    local e1 = get_effective_civ(ent1) or ent1
    local e2 = get_effective_civ(ent2) or ent2
    if e1.id == e2.id then return false end

    -- Check inherent hostility tags
    if e1.entity_raw and (e1.entity_raw.code:find("EVIL") or e1.entity_raw.code:find("SKULKING")) then
        if e2.entity_raw and not (e2.entity_raw.code:find("EVIL") or e2.entity_raw.code:find("SKULKING")) then
            return true
        end
    end
    if e2.entity_raw and (e2.entity_raw.code:find("EVIL") or e2.entity_raw.code:find("SKULKING")) then
        if e1.entity_raw and not (e1.entity_raw.code:find("EVIL") or e1.entity_raw.code:find("SKULKING")) then
            return true
        end
    end

    if e1.relations and e1.relations.diplomacy then
        for _, dip in ipairs(e1.relations.diplomacy) do
            if dip.target == e2.id or dip.target == ent2.id then
                local r = tostring(df.diplomatic_relation_type[dip.relation] or dip.relation)
                if r:find("War") or r:find("Enemy") or r:find("Hostile") then
                    return true
                end
            end
        end
    end

    if e2.relations and e2.relations.diplomacy then
        for _, dip in ipairs(e2.relations.diplomacy) do
            if dip.target == e1.id or dip.target == ent1.id then
                local r = tostring(df.diplomatic_relation_type[dip.relation] or dip.relation)
                if r:find("War") or r:find("Enemy") or r:find("Hostile") then
                    return true
                end
            end
        end
    end

    return false
end

-- authoritative diplomatic status calculator matching vanilla DF embark logic
local function get_diplomatic_status(ent, player_civ, def_state)
    if not ent then return "neutral", COLOR_WHITE end
    local eff_ent = get_effective_civ(ent) or ent

    -- 1. Player's own civilization or subordinate government is always peaceful
    if player_civ and (ent.id == player_civ.id or eff_ent.id == player_civ.id) then
        return "peaceful", COLOR_LIGHTBLUE
    end

    -- 2. Authoritative native DF candidate state (if provided directly from def_candidate)
    if def_state ~= nil then
        local sname = tostring(df.embark_neighbor_state_type[def_state] or def_state):upper()
        if sname:find("HOSTILE") or sname:find("WAR") or sname:find("NO_COMM") or def_state == 0 or def_state == 1 or def_state == 2 then
            return "hostile", COLOR_LIGHTRED
        elseif sname:find("PEACEFUL") or sname:find("NORMAL") or def_state == 4 then
            return "peaceful", COLOR_LIGHTBLUE
        end
    end

    -- 2. Explicit diplomatic relations from player civilization
    if player_civ and player_civ.relations and player_civ.relations.diplomacy then
        for _, dip in ipairs(player_civ.relations.diplomacy) do
            if dip.target == ent.id or dip.target == eff_ent.id then
                local r = tostring(df.diplomatic_relation_type[dip.relation] or dip.relation):upper()
                if r:find("WAR") or r:find("ENEMY") or r:find("HOSTILE") then
                    return "hostile", COLOR_LIGHTRED
                elseif r:find("PEACE") or r:find("TRADE") then
                    return "peaceful", COLOR_LIGHTBLUE
                end
            end
        end
    end

    -- 4. Explicit diplomatic relations from target entity towards player
    if ent.relations and ent.relations.diplomacy and player_civ then
        for _, dip in ipairs(ent.relations.diplomacy) do
            if dip.target == player_civ.id then
                local r = tostring(df.diplomatic_relation_type[dip.relation] or dip.relation):upper()
                if r:find("WAR") or r:find("ENEMY") or r:find("HOSTILE") then
                    return "hostile", COLOR_LIGHTRED
                elseif r:find("PEACE") or r:find("TRADE") then
                    return "peaceful", COLOR_LIGHTBLUE
                end
            end
        end
    end
    if eff_ent and eff_ent.id ~= ent.id and eff_ent.relations and eff_ent.relations.diplomacy and player_civ then
        for _, dip in ipairs(eff_ent.relations.diplomacy) do
            if dip.target == player_civ.id then
                local r = tostring(df.diplomatic_relation_type[dip.relation] or dip.relation):upper()
                if r:find("WAR") or r:find("ENEMY") or r:find("HOSTILE") then
                    return "hostile", COLOR_LIGHTRED
                elseif r:find("PEACE") or r:find("TRADE") then
                    return "peaceful", COLOR_LIGHTBLUE
                end
            end
        end
    end

    -- 5. Inherent evil / goblin tags ONLY if actually hostile by entity raw code (e.g. EVIL civ vs GOOD civ)
    local function is_inherently_hostile(e)
        if not e or not e.entity_raw then return false end
        local code = tostring(e.entity_raw.code or ""):upper()
        if code:find("GOBLIN") or code:find("EVIL") or code:find("KOBOLD") then
            if player_civ and player_civ.entity_raw then
                local pcode = tostring(player_civ.entity_raw.code or ""):upper()
                if not (pcode:find("GOBLIN") or pcode:find("EVIL") or pcode:find("KOBOLD")) then
                    return true
                end
            else
                return true
            end
        end
        return false
    end

    if is_inherently_hostile(ent) or is_inherently_hostile(eff_ent) then
        return "hostile", COLOR_LIGHTRED
    end

    -- 6. Civilized vs Independent/Nomad
    local is_civ = (ent.type == df.historical_entity_type.Civilization) or (eff_ent and eff_ent.type == df.historical_entity_type.Civilization)
    if is_civ then
        return "peaceful", COLOR_LIGHTBLUE
    end

    return "neutral", COLOR_WHITE
end

-- splits site string into 2 clean lines if exceeding limit
local function split_site_info(str, max_len)
    if #str <= max_len then
        return {str}
    end
    local split_idx = max_len
    for i = max_len, max_len - 35, -1 do
        local c = str:sub(i, i)
        if c == '[' or c == '|' or c == ' ' then
            split_idx = i - 1
            break
        end
    end
    local line1 = str:sub(1, split_idx):gsub("%s+$", "")
    local line2 = "        " .. str:sub(split_idx + 1):gsub("^%s+", "")
    return {line1, line2}
end

-- core data collector
function scan_neighbors()
    local scr = dfhack.gui.getDFViewscreen(true)
    if not df.viewscreen_choose_start_sitest:is_instance(scr) then
        return nil, 'must be on the embark site selection screen'
    end

    -- 1. identify currently selected player civilization
    local player_civ = nil
    local cid = df.global.plotinfo and df.global.plotinfo.civ_id
    if cid and cid >= 0 then
        player_civ = df.historical_entity.find(cid)
    end
    if not player_civ then
        local start_civs = safe_get(function() return scr.start_civ end)
        if start_civs and #start_civs > 0 then
            player_civ = start_civs[0]
        end
    end

    local player_race = "unknown"
    local player_civ_name = "unknown"

    if player_civ then
        player_civ_name = dfhack.translation.translateName(player_civ.name, true)
        if player_civ.race >= 0 and df.creature_raw.find(player_civ.race) then
            player_race = df.creature_raw.find(player_civ.race).name[1]:lower()
        elseif player_civ.entity_raw then
            player_race = player_civ.entity_raw.code:lower()
        end
    end

    -- 2. authoritative cursor coordinates
    local world_x = 0
    local world_y = 0

    local hover_x = safe_get(function() return scr.neighbor_hover_ax end)
    local hover_y = safe_get(function() return scr.neighbor_hover_ay end)

    if hover_x and hover_y and hover_x >= 0 and hover_y >= 0 then
        world_x = hover_x
        world_y = hover_y
    else
        local reg_x = safe_get(function() return scr.location.region_pos.x end)
        local reg_y = safe_get(function() return scr.location.region_pos.y end)
        if reg_x and reg_y and reg_x >= 0 and reg_y >= 0 then
            world_x = reg_x
            world_y = reg_y
        else
            local loc_x = safe_get(function() return scr.location.x end)
            local loc_y = safe_get(function() return scr.location.y end)
            if loc_x and loc_y then
                world_x = loc_x
                world_y = loc_y
            end
        end
    end

    -- 3. detect local site & occupying faction at cursor
    local site_info_str = "wilderness / uncolonized"
    local site_owner_entity = nil
    local best_site = nil

    local sites = safe_get(function() return df.global.world.world_data.sites end) or {}

    -- Prioritized candidate site collection matching world_x/world_y
    local emb_min_x = safe_get(function() return scr.location.embark_pos_min.x end)
    local emb_min_y = safe_get(function() return scr.location.embark_pos_min.y end)
    local emb_max_x = safe_get(function() return scr.location.embark_pos_max.x end)
    local emb_max_y = safe_get(function() return scr.location.embark_pos_max.y end)

    local candidate_sites = {}
    local t_min_x = world_x * 16
    local t_min_y = world_y * 16
    local t_max_x = t_min_x + 15
    local t_max_y = t_min_y + 15

    for _, site in ipairs(sites) do
        local overlap_area = 0
        if emb_min_x and emb_min_y and emb_max_x and emb_max_y and emb_min_x >= 0 and emb_min_y >= 0 then
            local emb_reg_x = math.floor(emb_min_x / 16)
            local emb_reg_y = math.floor(emb_min_y / 16)
            if emb_reg_x == world_x and emb_reg_y == world_y then
                local ox1 = math.max(emb_min_x, site.global_min_x)
                local ox2 = math.min(emb_max_x, site.global_max_x)
                local oy1 = math.max(emb_min_y, site.global_min_y)
                local oy2 = math.min(emb_max_y, site.global_max_y)
                if ox2 >= ox1 and oy2 >= oy1 then
                    overlap_area = (ox2 - ox1 + 1) * (oy2 - oy1 + 1)
                end
            end
        end

        local in_rect = not (t_max_x < site.global_min_x or t_min_x > site.global_max_x or
                             t_max_y < site.global_min_y or t_min_y > site.global_max_y)
        local in_pos = (site.pos.x == world_x and site.pos.y == world_y)
        local dist = math.sqrt((site.pos.x - world_x)^2 + (site.pos.y - world_y)^2)

        if overlap_area > 0 or in_rect or in_pos or dist <= 0.75 then
            local prio = get_site_category_priority(site)
            table.insert(candidate_sites, {
                site = site,
                prio = prio,
                overlap_area = overlap_area,
                in_rect = in_rect,
                in_pos = in_pos,
                dist = dist
            })
        end
    end

    if #candidate_sites > 0 then
        table.sort(candidate_sites, function(a, b)
            if a.prio ~= b.prio then return a.prio > b.prio end
            if a.overlap_area ~= b.overlap_area then return a.overlap_area > b.overlap_area end
            if a.in_rect ~= b.in_rect then return a.in_rect end
            if a.in_pos ~= b.in_pos then return a.in_pos end
            return a.dist < b.dist
        end)
        best_site = candidate_sites[1].site
    end

    if best_site then
        local sname = dfhack.translation.translateName(best_site.name, true)
        local stype = format_site_type(best_site)

        local primary_entity = get_site_active_occupant(best_site) or df.historical_entity.find(best_site.cur_owner_id) or df.historical_entity.find(best_site.civ_id)

        if primary_entity then
            site_owner_entity = primary_entity
            local cur_name = dfhack.translation.translateName(primary_entity.name, true)
            local cur_race = format_entity_race(primary_entity)

            local status_tag, _ = get_diplomatic_status(primary_entity, player_civ, nil)
            local status_note = ""
            if status_tag == "hostile" then
                status_note = " [hostile]"
            end
            site_info_str = string.format("%s (%s) | [%s] %s%s", sname, stype, cur_race, cur_name, status_note)
        else
            site_info_str = string.format("%s (%s) | ruins", sname, stype)
        end
    end

    local emb_w = 4
    local emb_h = 4
    if scr.embark_dx and scr.embark_dx >= 1 and scr.embark_dx <= 16 then
        emb_w = scr.embark_dx
    end
    if scr.embark_dy and scr.embark_dy >= 1 and scr.embark_dy <= 16 then
        emb_h = scr.embark_dy
    end
    if scr.location and scr.location.embark_pos_min and scr.location.embark_pos_max then
        local min_x = scr.location.embark_pos_min.x
        local max_x = scr.location.embark_pos_max.x
        local min_y = scr.location.embark_pos_min.y
        local max_y = scr.location.embark_pos_max.y
        if min_x >= 0 and max_x >= min_x and min_y >= 0 and max_y >= min_y then
            local calc_w = max_x - min_x + 1
            local calc_h = max_y - min_y + 1
            if calc_w >= 1 and calc_w <= 16 and calc_h >= 1 and calc_h <= 16 then
                emb_w = calc_w
                emb_h = calc_h
            end
        end
    end
    local emb_area = emb_w * emb_h

    local pop_info_str = "0"
    local pop_fmt = "0"
    local total_site_pop = 0
    if best_site then
        local stype_str = format_site_type(best_site)
        total_site_pop = get_site_actual_live_pop(best_site, stype_str) or 0
        local site_w = (best_site.global_max_x and best_site.global_min_x) and (best_site.global_max_x - best_site.global_min_x + 1) or 1
        local site_h = (best_site.global_max_y and best_site.global_min_y) and (best_site.global_max_y - best_site.global_min_y + 1) or 1
        local total_site_area = math.max(1, site_w * site_h)

        local emb_slice_pop = total_site_pop
        local hit_cap = false
        local max_engine_spawn = math.floor((300 * (emb_area / 9) + 5) / 10) * 10
        if total_site_area > emb_area then
            local ratio = math.min(1.0, emb_area / total_site_area)
            local nem_count = (best_site.populace and best_site.populace.nemesis) and #best_site.populace.nemesis or 0
            local raw_slice = math.max(nem_count + 10, math.floor(total_site_pop * math.sqrt(ratio)))
            if raw_slice >= (max_engine_spawn + nem_count) then
                emb_slice_pop = max_engine_spawn + nem_count
                hit_cap = true
            else
                emb_slice_pop = raw_slice
            end
        elseif emb_slice_pop >= max_engine_spawn then
            hit_cap = true
        end

        pop_fmt = format_est_pop(emb_slice_pop)
        if hit_cap then
            pop_info_str = string.format("%s (estimated population for %dx%d embark, %d engine cap)", pop_fmt, emb_w, emb_h, max_engine_spawn)
        else
            pop_info_str = string.format("%s (estimated population for %dx%d embark)", pop_fmt, emb_w, emb_h)
        end
    end

    -- 4. collect all civilizations and nearby factions
    local entries = {}
    local seen_entities = {}
    local seen_site_ids = {}

    -- A. Sovereign parent civilizations (Authoritative list from native DF pathfinding)
    local def_candidate = safe_get(function() return scr.def_candidate end)
    local def_cand_st = safe_get(function() return scr.def_candidate_near_st end)
    local def_cand_mindist = safe_get(function() return scr.def_candidate_mindist end)
    local def_cand_pop = safe_get(function() return scr.def_candidate_pop end)
    local def_cand_state = safe_get(function() return scr.def_candidate_state end)

    if def_candidate and def_cand_mindist then
        for i = 0, #def_candidate - 1 do
            local civ = def_candidate[i]
            local site = def_cand_st and def_cand_st[i]
            local dist = def_cand_mindist[i] or -1
            local raw_pop = def_cand_pop and def_cand_pop[i] or 0
            local state = def_cand_state and def_cand_state[i]

            if civ and dist >= 0 then
                local is_tower = (civ.type == df.historical_entity_type.Tower) or
                                 (civ.entity_raw and civ.entity_raw.code:find("TOWER")) or
                                 (site and (site.type == df.world_site_type.Tower or site.type == df.world_site_type.Vault)) or
                                 (state == 2 or state == df.embark_neighbor_state_type.NO_COMM)
                local eff_civ = is_tower and civ or (get_effective_civ(civ) or civ)
                local eff_key = is_tower and (site and ("tower_" .. site.id) or ("tower_" .. civ.id)) or tostring(eff_civ.id)

                if not seen_entities[eff_key] then
                    seen_entities[eff_key] = true
                    if site then seen_site_ids[site.id] = true end

                    local cname = is_tower and "Tower" or dfhack.translation.translateName(eff_civ.name, true)
                    local rname = is_tower and "tower" or format_entity_race(eff_civ)
                    local sname = site and dfhack.translation.translateName(site.name, true) or (is_tower and "Tower" or "")
                    local stype = site and format_site_type(site) or (is_tower and "tower" or "")

                    local dir = site and calculate_direction(world_x, world_y, site.pos.x, site.pos.y) or "here"
                    local travel_str = format_travel_time(dist, dir)

                    local status_str, status_pen = get_diplomatic_status(eff_civ, player_civ, state)
                    if is_tower then
                        status_str = "hostile"
                        status_pen = COLOR_LIGHTRED
                    end

                    local war_with_site = false
                    if site_owner_entity and check_entities_at_war(site_owner_entity, eff_civ) then
                        war_with_site = true
                    end
                    if is_tower then
                        war_with_site = true
                    end

                    local history_pop = format_population(raw_pop)
                    local est_pop = estimate_spawn_population(stype, raw_pop, history_pop, site)
                    local war_str = war_with_site and "war vs site" or ""

                    table.insert(entries, {
                        civ = eff_civ,
                        rname = rname,
                        cname = cname,
                        sname = sname,
                        stype = stype,
                        dist = dist,
                        travel_str = travel_str,
                        history_pop = history_pop,
                        est_pop = est_pop,
                        war_str = war_str,
                        direction = dir,
                        status = status_str,
                        status_pen = status_pen,
                        war_with_site = war_with_site,
                    })
                end
            end
        end
    end

    -- B. Always represent local site under cursor at dist = 0 ("here")
    if best_site and site_owner_entity then
        local eff_cursor_civ = get_effective_civ(site_owner_entity) or site_owner_entity
        local best_site_name = dfhack.translation.translateName(best_site.name, true)
        local cur_is_tower = (site_owner_entity.type == df.historical_entity_type.Tower) or
                             (site_owner_entity.entity_raw and site_owner_entity.entity_raw.code:find("TOWER")) or
                             (best_site.type == df.world_site_type.Tower or best_site.type == df.world_site_type.Vault)
        local oname = cur_is_tower and "Tower" or dfhack.translation.translateName(eff_cursor_civ.name, true)
        local orace = cur_is_tower and "tower" or format_entity_race(eff_cursor_civ)
        local status_str, status_pen = get_diplomatic_status(eff_cursor_civ, player_civ, nil)
        if cur_is_tower then
            status_str = "hostile"
            status_pen = COLOR_LIGHTRED
        end
        local stype = format_site_type(best_site)
        local hist_pop = format_population(total_site_pop or 0)
        if hist_pop == "" then hist_pop = "few" end

        local found_entry = nil
        for _, ent in ipairs(entries) do
            if (ent.sname and ent.sname == best_site_name) or (ent.travel_str == "here" or ent.dist == 0) then
                found_entry = ent
                break
            end
        end

        if found_entry then
            found_entry.sname = best_site_name
            found_entry.stype = stype
            found_entry.est_pop = pop_fmt
            if found_entry.dist == 0 then
                found_entry.travel_str = "here"
            end
        else
            table.insert(entries, {
                civ = eff_cursor_civ,
                rname = orace,
                cname = oname,
                sname = best_site_name,
                stype = stype,
                dist = 0,
                travel_str = "here",
                history_pop = hist_pop,
                est_pop = pop_fmt,
                war_str = "",
                direction = "here",
                status = status_str,
                status_pen = status_pen,
                war_with_site = false,
            })
        end
    end

    -- D. Deduplicate entries: ensure only one "here" entry and no duplicate site/civ rows
    local unique_entries = {}
    local seen_keys = {}
    local seen_here = false

    for _, ent in ipairs(entries) do
        local is_here = (ent.travel_str == "here" or ent.dist == 0)
        local key = string.format("%s|%s|%s", ent.sname or "", ent.rname or "", ent.travel_str or "")
        if is_here then
            if not seen_here then
                seen_here = true
                table.insert(unique_entries, ent)
            end
        elseif not seen_keys[key] then
            seen_keys[key] = true
            table.insert(unique_entries, ent)
        end
    end
    entries = unique_entries

    table.sort(entries, function(a, b)
        local a_here = (a.travel_str == "here" or a.dist == 0)
        local b_here = (b.travel_str == "here" or b.dist == 0)
        if a_here and not b_here then return true end
        if b_here and not a_here then return false end
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.sname < b.sname
    end)

    return {
        entries = entries,
        world_x = world_x,
        world_y = world_y,
        player_race = player_race,
        player_civ_name = player_civ_name,
        site_info_str = site_info_str,
        pop_info_str = pop_info_str,
    }
end

-- Draggable GUI window component
EmbarkNeighbors = defclass(EmbarkNeighbors, widgets.Window)
EmbarkNeighbors.ATTRS {
    frame={w=132, h=26, l=2, t=2},
    draggable=true,
    drag_anchors={title=true, frame=true, body=false},
}

function EmbarkNeighbors:init()
    local data, err = scan_neighbors()
    if not data then
        self:addviews{ widgets.Label{ text_to_wrap = err or 'error scanning neighbors' } }
        return
    end

    self.frame_title = string.format('neighbors [%.1f, %.1f] (drag to move)', data.world_x, data.world_y)

    local choices = {}
    for _, n in ipairs(data.entries) do
        local line = string.format('%-16.16s | %-20.20s | %-12.12s | %-8.8s | %-14.14s | %-14.14s | %s',
            n.travel_str, n.rname, n.history_pop, n.est_pop, n.war_str, n.stype, n.sname)
        table.insert(choices, {
            text={
                {text=line, pen=n.status_pen}
            },
            search_key=n.rname,
        })
    end

    local site_lines = split_site_info(data.site_info_str, 120)
    local site_tokens = {
        {text='site:   ', pen=COLOR_GREY},
        {text=site_lines[1], pen=COLOR_WHITE},
    }
    if site_lines[2] then
        table.insert(site_tokens, NEWLINE)
        table.insert(site_tokens, {text=site_lines[2], pen=COLOR_WHITE})
    end

    self:addviews{
        widgets.Panel{
            frame={t=0, l=0, r=0, h=#site_lines + 5},
            subviews={
                widgets.Label{
                    frame={t=0, l=0, r=0, h=#site_lines},
                    text=site_tokens,
                },
                widgets.Label{
                    frame={t=#site_lines, l=0},
                    text={
                        {text='pop:    ', pen=COLOR_GREY},
                        {text=data.pop_info_str or '0', pen=COLOR_WHITE},
                    }
                },
                widgets.Label{
                    frame={t=#site_lines + 1, l=0},
                    text={
                        {text='player: ', pen=COLOR_GREY},
                        {text='[' .. data.player_race .. '] ' .. data.player_civ_name, pen=COLOR_WHITE},
                    }
                },
                widgets.Label{
                    frame={t=#site_lines + 2, l=0},
                    text={
                        {text='legend: ', pen=COLOR_GREY},
                        {text='hostile', pen=COLOR_LIGHTRED},
                        {text=' | ', pen=COLOR_DARKGREY},
                        {text='peaceful', pen=COLOR_LIGHTBLUE},
                        {text=' | ', pen=COLOR_DARKGREY},
                        {text='neutral', pen=COLOR_WHITE},
                    }
                },
                widgets.Label{
                    frame={t=#site_lines + 4, l=0},
                    text={
                        {text=string.format('%-16.16s | %-20.20s | %-12.12s | %-8.8s | %-14.14s | %-14.14s | %s',
                            'travel', 'civ race', 'hist. pop', 'est. pop', 'conflict', 'site type', 'site name'), pen=COLOR_YELLOW},
                    }
                },
            }
        },
        widgets.List{
            view_id='list',
            frame={t=#site_lines + 5, b=0, l=0, r=0},
            choices=choices,
        },
    }
end

local active_screen = nil

EmbarkNeighborsScreen = defclass(EmbarkNeighborsScreen, gui.ZScreen)
EmbarkNeighborsScreen.ATTRS {
    focus_path='embark-neighbors',
    pass_movement_keys=true,
}

function EmbarkNeighborsScreen:init()
    self:addviews{
        EmbarkNeighbors{view_id='main'},
    }
end

function EmbarkNeighborsScreen:onDismiss()
    active_screen = nil
end

function show_gui()
    local scr = dfhack.gui.getDFViewscreen(true)
    if not df.viewscreen_choose_start_sitest:is_instance(scr) then
        qerror('must be on the embark site selection screen')
    end
    if active_screen and active_screen:isShown() then
        active_screen:dismiss()
        active_screen = nil
    end
    local screen = EmbarkNeighborsScreen{}
    active_screen = screen
    screen:show()
end

function print_cli()
    local data, err = scan_neighbors()
    if not data then
        qerror(err or 'error scanning neighbors')
    end

    print('\n' .. string.rep('-', 120))
    print(string.format('  neighbors at cursor: world [%.1f, %.1f]', data.world_x, data.world_y))
    print(string.format('  playing as: [%s] %s', data.player_race, data.player_civ_name))
    print(string.format('  site:   %s', data.site_info_str))
    print(string.rep('-', 120))

    for _, n in ipairs(data.entries) do
        print(string.format('%-16.16s | %-20.20s | %-24.24s | %-16.16s | %s',
            n.travel_str, n.rname, n.pop_str, n.stype, n.sname))
    end

    print(string.rep('-', 120) .. '\n')
end

function main(...)
    local args = {...}
    if #args > 0 and (args[1] == '--cli' or args[1] == '-c') then
        print_cli()
    else
        show_gui()
    end
end

if not dfhack_flags.module then
    main(...)
end
