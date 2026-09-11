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

-- checks if an entity is an active necromancer coven / tower faction
local function is_tower_faction(ent)
    if not ent then return false end
    if ent.entity_raw then
        local code = tostring(ent.entity_raw.code or ""):upper()
        if code:find("TOWER") or code:find("NECRO") then
            return true
        end
    end
    -- towers are independent site governments or outcasts, never sovereign civilizations, guilds, or religions
    if ent.type ~= df.historical_entity_type.SiteGovernment and ent.type ~= df.historical_entity_type.Outcast then
        return false
    end
    -- check leadership assignments for necromancers with animate/undead secrets
    local assigns = safe_get(function() return ent.positions and ent.positions.assignments end)
    if assigns then
        for _, a in ipairs(assigns) do
            local hf = safe_get(function() return df.historical_figure.find(a.histfig) end)
            if hf and hf.died_year < 0 and hf.info and hf.info.curse and #hf.info.curse.can_do > 0 then
                for _, inter in ipairs(hf.info.curse.can_do) do
                    local iname = inter.name or ""
                    if iname:find("SECRET_ANIMATE") or iname:find("DEITY_NECRO") or iname:find("SECRET_GHOUL") or iname:find("SECRET_UNDEAD") then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- resolves any site government or sub-entity to its parent civilization if linked
local function get_effective_civ(ent)
    if not ent then return nil end
    if is_tower_faction(ent) then
        return ent
    end
    if ent.type == df.historical_entity_type.Civilization then
        return ent
    end
    local links = safe_get(function() return ent.entity_links end)
    if links then
        for _, link in ipairs(links) do
            if link.type == df.entity_entity_link_type.PARENT then
                local target = safe_get(function() return df.historical_entity.find(link.target) end)
                if target and target.type == df.historical_entity_type.Civilization then
                    return target
                end
            end
        end
    end
    return ent
end

-- formats entity race cleanly, detecting towers and necromancer factions
local function format_entity_race(ent)
    if not ent then return "unknown" end
    if is_tower_faction(ent) then
        return "tower"
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

-- checks if a site is a necromancer tower
local function is_tower_site(site)
    if not site then return false end
    local owner = get_site_active_occupant(site) or (site.cur_owner_id and site.cur_owner_id >= 0 and df.historical_entity.find(site.cur_owner_id)) or (site.civ_id and site.civ_id >= 0 and df.historical_entity.find(site.civ_id))
    if is_tower_faction(owner) then return true end
    return false
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
    elseif pop < 1000 then
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
    local seen_ep = {}
    if site.populace and site.populace.inhabitants then
        for i = 0, #site.populace.inhabitants - 1 do
            local entry = site.populace.inhabitants[i]
            local ps = entry.pop_spec
            if ps and ps.epid and ps.epid >= 0 and not seen_ep[ps.epid] then
                seen_ep[ps.epid] = true
                local ep = df.entity_population.find(ps.epid)
                if ep and ep.counts then
                    for _, c in ipairs(ep.counts) do
                        inh_total = inh_total + c
                    end
                end
            end
            if entry.count and entry.count > 0 then
                inh_total = inh_total + entry.count
            end
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
        base_pop = (inh_total > 0 and inh_total or nem_count)
    elseif t:find("town") or t:find("city") or t:find("mountainhall") or t:find("hamlet") or t:find("hillock") or t:find("retreat") then
        if inh_total > 0 then
            base_pop = math.max(base_pop, inh_total)
        else
            base_pop = math.max(nem_count, math.floor(infra * 0.5))
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

-- calculates site category priority (dungeons, monuments, fortresses take precedence over temporary camps)
local function get_site_category_priority(site)
    if not site then return 0 end
    local t = site.type
    if t == df.world_site_type.Monument then
        return 100 -- Ancient monuments / mysterious dungeons highlighted by DF UI
    elseif t == df.world_site_type.Vault then
        return 100
    elseif t == df.world_site_type.DarkFortress or t == df.world_site_type.Fortress or t == df.world_site_type.Castle or t == df.world_site_type.Tower then
        return 90
    elseif t == df.world_site_type.MountainHalls or t == df.world_site_type.Town then
        return 80
    elseif t == df.world_site_type.Retreat or t == df.world_site_type.Cave or t == df.world_site_type.LairShrine or t == df.world_site_type.Tomb then
        return 70
    elseif t == df.world_site_type.Hamlet or t == df.world_site_type.Hillock or t == df.world_site_type.DarkPits then
        return 50
    elseif t == df.world_site_type.Camp then
        return 20 -- Temporary camps are subordinate to prominent structures
    else
        return 40
    end
end

-- formats site type names cleanly in lowercase matching vanilla DF site classification
local function format_site_type(site)
    if not site then return "" end
    if is_tower_site(site) then
        return "tower"
    end
    local raw_t = safe_get(function() return df.world_site_type[site.type] or site.type end)
    if not raw_t then return "" end
    local t_str = tostring(raw_t):lower():gsub("_", " ")

    if site.type == df.world_site_type.Monument or t_str:find("monument") then
        return "dungeon"
    elseif site.type == df.world_site_type.Town or t_str:find("town") then
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

    -- 1. Active historical diplomacy states (TotalWar or Skirmishing)
    local function get_diplomacy_relation(source_ent, target_id)
        if not source_ent or not source_ent.relations or not source_ent.relations.diplomacy then
            return nil
        end
        local states = source_ent.relations.diplomacy.state
        if not states then return nil end
        for _, dip in ipairs(states) do
            if dip.group_id == target_id then
                return dip.relation
            end
        end
        return nil
    end

    local r1 = get_diplomacy_relation(e1, e2.id) or get_diplomacy_relation(e1, ent2.id)
    local r2 = get_diplomacy_relation(e2, e1.id) or get_diplomacy_relation(e2, ent1.id)
    local rel = r1 or r2
    if rel ~= nil then
        if rel == df.diplomacy_state_type.TotalWar or rel == df.diplomacy_state_type.Skirmishing then
            return true
        elseif rel == df.diplomacy_state_type.Peace or rel == df.diplomacy_state_type.TradeAgreement then
            return false
        end
    end

    -- Necromancer towers are universally hostile
    if is_tower_faction(e1) or is_tower_faction(e2) then
        return true
    end

    return false
end

-- authoritative diplomatic status calculator matching vanilla DF embark logic
local function get_diplomatic_status(ent, player_civ, def_state)
    if not ent then return "neutral", COLOR_WHITE end
    local eff_ent = get_effective_civ(ent) or ent

    -- 1. player's own civilization or subordinate government is always peaceful
    if player_civ and (ent.id == player_civ.id or eff_ent.id == player_civ.id) then
        return "peaceful", COLOR_LIGHTBLUE
    end

    -- 2. necromancer towers are universally hostile
    if is_tower_faction(ent) or is_tower_faction(eff_ent) then
        return "hostile", COLOR_LIGHTRED
    end

    -- 3. explicit historical diplomatic relations (war vs peace)
    local function get_dip_state(source_ent, target_id)
        if not source_ent or not source_ent.relations or not source_ent.relations.diplomacy then return nil end
        local states = source_ent.relations.diplomacy.state
        if not states then return nil end
        for _, dip in ipairs(states) do
            if dip.group_id == target_id then
                if dip.relation == df.diplomacy_state_type.TotalWar or dip.relation == df.diplomacy_state_type.Skirmishing then
                    return "hostile"
                elseif dip.relation == df.diplomacy_state_type.Peace or dip.relation == df.diplomacy_state_type.TradeAgreement then
                    return "peaceful"
                end
            end
        end
        return nil
    end

    if player_civ then
        local st1 = get_dip_state(player_civ, ent.id) or get_dip_state(player_civ, eff_ent.id)
        local st2 = get_dip_state(ent, player_civ.id) or get_dip_state(eff_ent, player_civ.id)
        if st1 == "hostile" or st2 == "hostile" then
            return "hostile", COLOR_LIGHTRED
        elseif st1 == "peaceful" or st2 == "peaceful" then
            return "peaceful", COLOR_LIGHTBLUE
        end
    end

    -- 4. native DF candidate state (WAR / HOSTILE / NORMAL / NO_COMM / NO_TRADE)
    if def_state ~= nil then
        local sname = tostring(df.embark_neighbor_state_type[def_state] or def_state):upper()
        if sname:find("WAR") or def_state == 0 then
            return "hostile", COLOR_LIGHTRED
        elseif sname:find("HOSTILE") or def_state == 1 then
            return "hostile", COLOR_LIGHTRED
        elseif sname:find("PEACEFUL") or sname:find("NORMAL") or def_state == 4 then
            return "peaceful", COLOR_LIGHTBLUE
        elseif def_state == 2 or def_state == 3 then
            return "neutral", COLOR_WHITE
        end
    end

    -- 5. civilized vs independent/nomad
    local is_civ = (ent.type == df.historical_entity_type.Civilization) or (eff_ent and eff_ent.type == df.historical_entity_type.Civilization)
    if is_civ then
        return "peaceful", COLOR_LIGHTBLUE
    end

    return "neutral", COLOR_WHITE
end

-- authoritative siege capability evaluator determining whether neighbor will siege player, site, or both
local function get_siege_status(ent, player_civ, site_owner_entity, is_tower, cand_state, raw_pop, est_pop)
    if not ent or not ent.entity_raw then return "-" end
    local eff_civ = get_effective_civ(ent) or ent

    -- player's own civilization never sieges player
    if player_civ and (ent.id == player_civ.id or eff_civ.id == player_civ.id) then
        return "-"
    end

    local raw = ent.entity_raw
    local is_sieger = (raw.flags and raw.flags.SIEGER) or is_tower
    local is_ambusher = (raw.flags and raw.flags.AMBUSHER)

    local war_with_player = false
    if is_tower then
        war_with_player = true
    elseif cand_state ~= nil then
        war_with_player = (cand_state == df.embark_neighbor_state_type.WAR or cand_state == 0)
    elseif player_civ then
        war_with_player = check_entities_at_war(player_civ, eff_civ)
    end

    local war_with_site = false
    if is_tower then
        war_with_site = true
    elseif site_owner_entity and site_owner_entity.id ~= eff_civ.id then
        war_with_site = check_entities_at_war(site_owner_entity, eff_civ)
    end

    if not war_with_player and not war_with_site then
        return "-"
    end

    -- entity is at war: verify whether they can siege vs ambush
    if not is_sieger then
        if is_ambusher then
            return "ambush only"
        end
        return "-"
    end

    -- verify living population: empty ruins or dead civilizations cannot mount invasions
    local hf_count = eff_civ.hist_figures and #eff_civ.hist_figures or 0
    if hf_count > 0 and hf_count < 5 and (not raw_pop or raw_pop == 0) then
        return "no pop"
    end
    if hf_count == 0 and (not raw_pop or raw_pop == 0) and (not est_pop or est_pop == '0' or est_pop == '~0') then
        return "extinct"
    end

    local pop_siege = raw.progress_trigger and raw.progress_trigger.pop_siege or 0
    local is_hermit_pop_limited = (pop_siege > 0)

    if war_with_player and war_with_site then
        if is_hermit_pop_limited then
            return string.format("both (pop %d+)", pop_siege)
        end
        return "both"
    elseif war_with_player then
        if is_hermit_pop_limited then
            return string.format("you (pop %d+)", pop_siege)
        end
        return "you"
    elseif war_with_site then
        return "site"
    end

    return "-"
end

-- extracts high-signal urban architecture, fortifications, and subterranean summary
local function get_site_urban_summary(s)
    if not s then return nil end
    local r = s.realization
    local stype = (df.world_site_type[s.type] or 'site'):lower()

    local castles, towers, walls, trenches = 0, 0, 0, 0
    local taverns, temples, libraries, guildhalls, counting_houses, wells, markets, warehouses = 0, 0, 0, 0, 0, 0, 0, 0
    local houses, shops, courtyards, pastures, cottages = 0, 0, 0, 0, 0
    local necro_spires, barrows, shrines, tombs, vaults = 0, 0, 0, 0, 0
    local mythical_lairs, mythical_palaces, mythical_dungeons = 0, 0, 0
    local dormitories, dining_halls, entrances = 0, 0, 0
    local tree_houses, hillock_houses, mead_halls = 0, 0, 0
    local underground_layers = 0

    if r then
        if r.site_underground_layer and #r.site_underground_layer > 0 then
            underground_layers = #r.site_underground_layer
        end
        if r.buildings then
            for i = 0, #r.buildings - 1 do
                local b = r.buildings[i]
                local bt = df.site_realization_building_type[b.type]
                if bt == 'castle_wall' then walls = walls + 1
                elseif bt == 'castle_tower' or bt == 'great_tower' or bt == 'city_tower' then towers = towers + 1
                elseif bt == 'necromancer_tower' then necro_spires = necro_spires + 1
                elseif bt == 'barrow' then barrows = barrows + 1
                elseif bt == 'mythical_lair' then mythical_lairs = mythical_lairs + 1
                elseif bt == 'mythical_palace' then mythical_palaces = mythical_palaces + 1
                elseif bt == 'mythical_dungeon' then mythical_dungeons = mythical_dungeons + 1
                elseif bt == 'fortress_entrance' then entrances = entrances + 1
                elseif bt == 'dormitory' then dormitories = dormitories + 1
                elseif bt == 'dininghall' then dining_halls = dining_halls + 1
                elseif bt == 'shrine' then shrines = shrines + 1
                elseif bt == 'tomb' then tombs = tombs + 1
                elseif bt == 'vault' then vaults = vaults + 1
                elseif bt == 'tree_house' then tree_houses = tree_houses + 1
                elseif bt == 'hillock_house' then hillock_houses = hillock_houses + 1
                elseif bt == 'mead_hall' then mead_halls = mead_halls + 1
                elseif bt == 'cottage_plot' then cottages = cottages + 1
                elseif bt == 'trenches' then trenches = trenches + 1
                elseif bt == 'tavern' then taverns = taverns + 1
                elseif bt == 'temple' then temples = temples + 1
                elseif bt == 'library' then libraries = libraries + 1
                elseif bt == 'guildhall' or bt == 'guild_hall' then guildhalls = guildhalls + 1
                elseif bt == 'counting_house' then counting_houses = counting_houses + 1
                elseif bt == 'well' then wells = wells + 1
                elseif bt == 'market_square' then markets = markets + 1
                elseif bt == 'warehouse' then warehouses = warehouses + 1
                elseif bt == 'shop_house' then shops = shops + 1
                elseif bt == 'house' then houses = houses + 1
                elseif bt == 'courtyard' or bt == 'castle_courtyard' then courtyards = courtyards + 1
                elseif bt == 'pasture' then pastures = pastures + 1
                end
            end
        end
    end

    if s.buildings and #s.buildings > 0 then
        for i = 0, #s.buildings - 1 do
            local b = s.buildings[i]
            local bt = df.abstract_building_type[b:getType()] or ''
            if bt == 'INN_TAVERN' and taverns == 0 then taverns = taverns + 1
            elseif bt == 'TEMPLE' and temples == 0 then temples = temples + 1
            elseif bt == 'LIBRARY' and libraries == 0 then libraries = libraries + 1
            elseif bt == 'GUILDHALL' and guildhalls == 0 then guildhalls = guildhalls + 1
            elseif bt == 'COUNTING_HOUSE' and counting_houses == 0 then counting_houses = counting_houses + 1
            elseif bt == 'MARKET' and markets == 0 then markets = markets + 1
            elseif bt == 'TOMB' and tombs == 0 then tombs = tombs + 1
            elseif bt == 'DARK_TOWER' and towers == 0 then towers = towers + 1
            elseif bt == 'MEAD_HALL' and mead_halls == 0 then mead_halls = mead_halls + 1
            end
        end
    end

    local feat = {}
    if necro_spires > 0 then
        table.insert(feat, necro_spires == 1 and 'necromancer spire' or (necro_spires .. ' necromancer spires'))
    end
    if barrows > 0 then
        table.insert(feat, barrows == 1 and 'barrow crypt' or (barrows .. ' barrow crypts'))
    end
    if mythical_lairs > 0 then
        table.insert(feat, mythical_lairs == 1 and 'mythical beast lair' or (mythical_lairs .. ' mythical beast lairs'))
    end
    if mythical_palaces > 0 then
        table.insert(feat, mythical_palaces == 1 and 'mythical palace' or (mythical_palaces .. ' mythical palaces'))
    end
    if mythical_dungeons > 0 then
        table.insert(feat, mythical_dungeons == 1 and 'mythical dungeon labyrinth' or (mythical_dungeons .. ' mythical dungeon labyrinths'))
    end
    if entrances > 0 then
        table.insert(feat, entrances == 1 and 'grand fortress entrance' or (entrances .. ' fortress gates'))
    end
    if towers > 0 or walls > 0 then
        table.insert(feat, string.format('castle keep (%d towers, %d walls)', towers, walls))
    end
    if trenches > 0 then
        table.insert(feat, trenches == 1 and 'defensive trench' or (trenches .. ' defensive trenches'))
    end
    if taverns > 0 then table.insert(feat, taverns == 1 and 'tavern' or (taverns .. ' taverns')) end
    if temples > 0 then table.insert(feat, temples == 1 and 'temple' or (temples .. ' temples')) end
    if shrines > 0 then table.insert(feat, shrines == 1 and 'shrine' or (shrines .. ' shrines')) end
    if libraries > 0 then table.insert(feat, libraries == 1 and 'library' or (libraries .. ' libraries')) end
    if guildhalls > 0 then table.insert(feat, guildhalls == 1 and 'guildhall' or (guildhalls .. ' guildhalls')) end
    if counting_houses > 0 then table.insert(feat, 'counting house') end
    if markets > 0 then table.insert(feat, markets == 1 and 'market' or (markets .. ' market stalls')) end
    if shops > 0 then table.insert(feat, shops .. ' artisan shops') end
    if dormitories > 0 then table.insert(feat, dormitories == 1 and 'dormitory' or (dormitories .. ' dormitories')) end
    if dining_halls > 0 then table.insert(feat, dining_halls == 1 and 'great dining hall' or (dining_halls .. ' dining halls')) end
    if mead_halls > 0 then table.insert(feat, 'mead hall') end
    if houses > 0 then table.insert(feat, houses .. ' houses') end
    if cottages > 0 then table.insert(feat, cottages == 1 and 'cottage plot' or (cottages .. ' cottage plots')) end
    if tree_houses > 0 then table.insert(feat, tree_houses == 1 and 'canopy tree dwelling' or (tree_houses .. ' canopy tree dwellings')) end
    if hillock_houses > 0 then table.insert(feat, hillock_houses == 1 and 'hillock burrow' or (hillock_houses .. ' hillock burrows')) end
    if wells > 0 then table.insert(feat, wells == 1 and 'public well' or (wells .. ' wells')) end
    if warehouses > 0 then table.insert(feat, 'warehouse') end
    if tombs > 0 then table.insert(feat, tombs == 1 and 'tomb chamber' or (tombs .. ' tomb chambers')) end
    if vaults > 0 then table.insert(feat, 'sealed divine vault') end

    if underground_layers > 0 then
        table.insert(feat, string.format('%d subterranean layers', underground_layers))
    end

    local summary = ''
    if #feat > 0 then
        summary = table.concat(feat, ', ')
        if r and r.num_buildings and r.num_buildings > 0 then
            summary = summary .. string.format(' [%d %s total]', r.num_buildings, r.num_buildings == 1 and 'plot' or 'plots')
        end
    else
        -- check subtype_info if realization has no specific building records
        local sub = s.subtype_info
        if sub and sub.fortress_type and sub.fortress_type >= 0 then
            local ft = df.fortress_type[sub.fortress_type]
            if ft == 'TOWER' then
                if is_tower_site(s) or s.type == df.world_site_type.Tower then
                    summary = 'necromancer tower spire & defensive perimeter'
                else
                    summary = 'fortified tower spire & defensive perimeter'
                end
            elseif ft == 'MONASTERY' then
                summary = 'monastic retreat & temple sanctuaries'
            elseif ft == 'FORT' then
                summary = 'military fort & defensive ramparts'
            elseif ft == 'CASTLE' then
                summary = 'fortified castle bastions'
            end
        elseif sub and sub.monument_type and sub.monument_type >= 0 then
            local mt = df.monument_type[sub.monument_type]
            if mt == 'MYTHICAL' then
                summary = 'ancient mythical ruins / labyrinth'
            elseif mt == 'TOMB' then
                summary = 'ancient monumental tomb complex'
            elseif mt == 'VAULT' then
                summary = 'sealed divine vault'
            end
        elseif sub and sub.lair_type and sub.lair_type >= 0 then
            local lt = df.lair_type[sub.lair_type]
            if lt == 'LABYRINTH' then
                summary = 'ancient subterranean labyrinth'
            elseif lt == 'SHRINE' then
                summary = 'consecrated beast shrine'
            else
                summary = 'natural beast lair / cavern burrow'
            end
        end

        if #summary == 0 then
            if s.type == df.world_site_type.Monument then
                summary = 'ancient stone monument / subterranean dungeon'
            elseif s.type == df.world_site_type.Vault then
                summary = 'sealed divine vault & ancient labyrinth'
            elseif s.type == df.world_site_type.Camp then
                summary = 'temporary nomadic campsite with tents & perimeter posts'
            elseif s.type == df.world_site_type.Cave or s.type == df.world_site_type.LairShrine then
                summary = 'natural cavern network / beast lair'
            elseif s.type == df.world_site_type.MountainHalls or s.type == df.world_site_type.Fortress or s.type == df.world_site_type.DarkFortress then
                local infra = s.infrastructure_pop_level or 0
                if infra > 100 then
                    summary = string.format('deep subterranean fortress halls & bastions [infra level %d]', infra)
                else
                    summary = 'subterranean fortress halls & defensive bastions'
                end
            elseif s.type == df.world_site_type.ForestRetreat then
                summary = 'arboreal forest retreat with living canopy structures'
            else
                local infra = s.infrastructure_pop_level or 0
                if infra > 100 then
                    summary = string.format('developed settlement [infrastructure level %d]', infra)
                elseif infra > 20 then
                    summary = string.format('small settlement [infrastructure level %d]', infra)
                else
                    summary = 'primitive settlement / farmsteads'
                end
            end
        end
    end
    return summary
end

-- splits text into wrapped lines if exceeding max_len
local function split_text_wrap(str, max_len)
    max_len = max_len or 120
    if not str or #str == 0 then return {} end
    if #str <= max_len then
        return {str}
    end
    local lines = {}
    local line = ''
    for word in tostring(str):gmatch('%S+') do
        if #line == 0 then
            line = word
        elseif #line + 1 + #word <= max_len then
            line = line .. ' ' .. word
        else
            table.insert(lines, line)
            line = word
        end
    end
    if #line > 0 then
        table.insert(lines, line)
    end
    return lines
end

-- core data collector
function scan_neighbors(override_x, override_y)
    local scr = dfhack.gui.getDFViewscreen(true)
    local is_world = df.viewscreen_worldst:is_instance(scr)
    local is_fort = df.viewscreen_dwarfmodest:is_instance(scr) and dfhack.isMapLoaded()
    local is_embark = df.viewscreen_choose_start_sitest:is_instance(scr)
    if not is_world and not is_fort and not is_embark then
        return nil, 'must be on the embark site selection screen, world map screen, or in fortress mode'
    end

    -- 1. identify currently selected player civilization
    local player_civ = nil
    local cid = df.global.plotinfo and df.global.plotinfo.civ_id
    if cid and cid >= 0 then
        player_civ = df.historical_entity.find(cid)
    end
    if not player_civ and is_embark then
        local start_civs = safe_get(function() return scr.start_civ end)
        local sel_idx = safe_get(function() return scr.selected_civ end) or 0
        if start_civs and #start_civs > 0 then
            player_civ = (sel_idx >= 0 and start_civs[sel_idx]) or start_civs[0]
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

    if override_x and override_y then
        world_x = override_x
        world_y = override_y
    elseif is_world then
        if scr.focus_ax and scr.focus_ay and scr.focus_ax >= 0 and scr.focus_ay >= 0 then
            world_x = scr.focus_ax
            world_y = scr.focus_ay
        elseif df.global.plotinfo and df.global.plotinfo.main and df.global.plotinfo.main.fortress_site then
            world_x = df.global.plotinfo.main.fortress_site.pos.x
            world_y = df.global.plotinfo.main.fortress_site.pos.y
        end
    elseif is_fort then
        if df.global.plotinfo and df.global.plotinfo.main and df.global.plotinfo.main.fortress_site then
            world_x = df.global.plotinfo.main.fortress_site.pos.x
            world_y = df.global.plotinfo.main.fortress_site.pos.y
        end
    else
        local hover_x = safe_get(function() return scr.neighbor_hover_ax end)
        local hover_y = safe_get(function() return scr.neighbor_hover_ay end)
        local reg_x = safe_get(function() return scr.location.region_pos.x end)
        local reg_y = safe_get(function() return scr.location.region_pos.y end)

        if hover_x and hover_y and hover_x >= 0 and hover_y >= 0 then
            world_x = hover_x
            world_y = hover_y
        elseif reg_x and reg_y and reg_x >= 0 and reg_y >= 0 then
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

    local is_embark_on_cursor = false
    if emb_min_x and emb_min_y and emb_max_x and emb_max_y and emb_min_x >= 0 and emb_min_y >= 0 then
        local emb_reg_x = math.floor(emb_min_x / 16)
        local emb_reg_y = math.floor(emb_min_y / 16)
        if emb_reg_x == world_x and emb_reg_y == world_y then
            is_embark_on_cursor = true
        end
    end

    local hover_mm_sx = safe_get(function() return scr.neighbor_hover_mm_sx end)
    local hover_mm_sy = safe_get(function() return scr.neighbor_hover_mm_sy end)
    local hover_mm_ex = safe_get(function() return scr.neighbor_hover_mm_ex end)
    local hover_mm_ey = safe_get(function() return scr.neighbor_hover_mm_ey end)
    local has_hover_box = false
    local hx1, hy1, hx2, hy2 = 0, 0, 0, 0
    if hover_mm_sx and hover_mm_sy and hover_mm_ex and hover_mm_ey and hover_mm_sx >= 0 and hover_mm_sy >= 0 and hover_mm_ex >= hover_mm_sx and hover_mm_ey >= hover_mm_sy then
        has_hover_box = true
        hx1, hy1, hx2, hy2 = hover_mm_sx, hover_mm_sy, hover_mm_ex, hover_mm_ey
    end

    for _, site in ipairs(sites) do
        local overlap_area = 0
        if is_embark_on_cursor then
            local ox1 = math.max(emb_min_x, site.global_min_x)
            local ox2 = math.min(emb_max_x, site.global_max_x)
            local oy1 = math.max(emb_min_y, site.global_min_y)
            local oy2 = math.min(emb_max_y, site.global_max_y)
            if ox2 >= ox1 and oy2 >= oy1 then
                overlap_area = (ox2 - ox1 + 1) * (oy2 - oy1 + 1)
            end
        elseif has_hover_box then
            local ox1 = math.max(hx1, site.global_min_x)
            local ox2 = math.min(hx2, site.global_max_x)
            local oy1 = math.max(hy1, site.global_min_y)
            local oy2 = math.min(hy2, site.global_max_y)
            if ox2 >= ox1 and oy2 >= oy1 then
                overlap_area = (ox2 - ox1 + 1) * (oy2 - oy1 + 1)
            end
        end

        local tx1 = math.max(t_min_x, site.global_min_x)
        local tx2 = math.min(t_max_x, site.global_max_x)
        local ty1 = math.max(t_min_y, site.global_min_y)
        local ty2 = math.min(t_max_y, site.global_max_y)
        local tile_overlap_area = (tx2 >= tx1 and ty2 >= ty1) and ((tx2 - tx1 + 1) * (ty2 - ty1 + 1)) or 0

        local in_pos = (site.pos.x == world_x and site.pos.y == world_y)
        local is_candidate = (overlap_area > 0) or (tile_overlap_area > 0) or in_pos

        if is_candidate then
            local prio = get_site_category_priority(site)
            local is_at_cursor = (overlap_area > 0) or in_pos or (tile_overlap_area > 0)
            local cand_dist = is_at_cursor and 0 or math.sqrt((site.pos.x - world_x)^2 + (site.pos.y - world_y)^2)
            table.insert(candidate_sites, {
                site = site,
                prio = prio,
                overlap_area = overlap_area,
                tile_overlap_area = tile_overlap_area,
                in_pos = in_pos,
                dist = cand_dist,
            })
        end
    end

    if #candidate_sites > 0 then
        table.sort(candidate_sites, function(a, b)
            if a.overlap_area ~= b.overlap_area then return a.overlap_area > b.overlap_area end
            if a.tile_overlap_area ~= b.tile_overlap_area then return a.tile_overlap_area > b.tile_overlap_area end
            if a.prio ~= b.prio then return a.prio > b.prio end
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
    if is_embark then
        local edx = safe_get(function() return scr.embark_dx end)
        local edy = safe_get(function() return scr.embark_dy end)
        if edx and edx >= 1 and edx <= 16 then emb_w = edx end
        if edy and edy >= 1 and edy <= 16 then emb_h = edy end
        local min_x = safe_get(function() return scr.location.embark_pos_min.x end)
        local max_x = safe_get(function() return scr.location.embark_pos_max.x end)
        local min_y = safe_get(function() return scr.location.embark_pos_min.y end)
        local max_y = safe_get(function() return scr.location.embark_pos_max.y end)
        if min_x and max_x and min_y and max_y and min_x >= 0 and max_x >= min_x and min_y >= 0 and max_y >= min_y then
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

        if is_world or is_fort then
            pop_fmt = format_est_pop(total_site_pop)
            pop_info_str = string.format("%s (living population: ~%d)", format_population(total_site_pop), total_site_pop)
        else
            local site_w = (best_site.global_max_x and best_site.global_min_x) and (best_site.global_max_x - best_site.global_min_x + 1) or 1
            local site_h = (best_site.global_max_y and best_site.global_min_y) and (best_site.global_max_y - best_site.global_min_y + 1) or 1
            local total_site_area = math.max(1, site_w * site_h)

            local emb_slice_pop = total_site_pop
            local hit_cap = false
            local max_engine_spawn = math.floor((150 * (emb_area / 9) + 5) / 10) * 10
            if total_site_area > emb_area then
                local area_ratio = emb_area / total_site_area
                local effective_ratio = (area_ratio + math.sqrt(area_ratio)) / 3.0
                local nem_count = (best_site.populace and best_site.populace.nemesis) and #best_site.populace.nemesis or 0
                local raw_slice = math.floor(total_site_pop * effective_ratio)

                local bld_count = (best_site.realization and best_site.realization.buildings) and #best_site.realization.buildings or 0
                if bld_count > 0 then
                    local bld_slice = math.floor(bld_count * (emb_area / total_site_area) * 8)
                    raw_slice = math.max(raw_slice, bld_slice)
                end

                raw_slice = math.max(nem_count, raw_slice)

                if raw_slice >= (max_engine_spawn + nem_count) then
                    emb_slice_pop = max_engine_spawn + nem_count
                    hit_cap = true
                else
                    emb_slice_pop = math.min(total_site_pop, raw_slice)
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
    end

    local urban_info_str = nil
    if best_site then
        urban_info_str = get_site_urban_summary(best_site)
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
                local is_tower = is_tower_site(site) or is_tower_faction(civ)
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
                    local siege_str = get_siege_status(eff_civ, player_civ, site_owner_entity, is_tower, state, raw_pop, est_pop)

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
                        siege_str = siege_str,
                        direction = dir,
                        status = status_str,
                        status_pen = status_pen,
                        war_with_site = war_with_site,
                        is_primary_site = false,
                    })
                end
            end
        end
    end

    -- B. Always represent all local candidate sites matching cursor tile
    for _, cand in ipairs(candidate_sites) do
        local site = cand.site
        local site_owner = get_site_active_occupant(site) or df.historical_entity.find(site.cur_owner_id) or df.historical_entity.find(site.civ_id)
        if site and site_owner then
            local eff_civ = get_effective_civ(site_owner) or site_owner
            local sname = dfhack.translation.translateName(site.name, true)
            local is_tower = is_tower_site(site) or is_tower_faction(site_owner)
            local oname = is_tower and (site_owner and dfhack.translation.translateName(site_owner.name, true) or "Tower") or dfhack.translation.translateName(eff_civ.name, true)
            local orace = is_tower and "tower" or format_entity_race(eff_civ)
            local status_str, status_pen = get_diplomatic_status(eff_civ, player_civ, nil)
            if is_tower then
                status_str = "hostile"
                status_pen = COLOR_LIGHTRED
            end
            local stype = format_site_type(site)
            local site_live_pop = get_site_actual_live_pop(site, stype) or 0
            local hist_pop = format_population(site_live_pop)
            if hist_pop == "" then hist_pop = "few" end

            local is_primary = (best_site and site.id == best_site.id)
            local cand_pop_fmt = format_est_pop(site_live_pop)
            if is_primary then
                cand_pop_fmt = pop_fmt
            end

            local dist_val = 0
            local t_str = "here"
            if not is_primary and cand.dist and cand.dist > 0.05 then
                dist_val = math.max(1, math.floor(cand.dist + 0.5))
                local dir = calculate_direction(world_x, world_y, site.pos.x, site.pos.y)
                t_str = format_travel_time(dist_val, dir)
                if t_str == "" then t_str = "here" end
            end

            local found_entry = nil
            for _, ent in ipairs(entries) do
                if ent.sname == sname and ent.rname == orace then
                    found_entry = ent
                    break
                end
            end

            if found_entry then
                found_entry.sname = sname
                found_entry.stype = stype
                found_entry.est_pop = cand_pop_fmt
                if is_primary then
                    found_entry.dist = 0
                    found_entry.travel_str = "here"
                    found_entry.is_primary_site = true
                end
            else
                local siege_str = get_siege_status(eff_civ, player_civ, site_owner_entity, false, nil, nil, cand_pop_fmt)
                table.insert(entries, {
                    civ = eff_civ,
                    rname = orace,
                    cname = oname,
                    sname = sname,
                    stype = stype,
                    dist = dist_val,
                    travel_str = t_str,
                    history_pop = hist_pop,
                    est_pop = cand_pop_fmt,
                    siege_str = siege_str,
                    direction = is_primary and "here" or calculate_direction(world_x, world_y, site.pos.x, site.pos.y),
                    status = status_str,
                    status_pen = status_pen,
                    war_with_site = false,
                    is_primary_site = is_primary,
                })
            end
        end
    end

    -- C. Dynamically collect reachable nearby sites (fortresses, towers, independent governments, local settlements)
    local nearby_sites = {}
    for _, s in ipairs(sites) do
        local dx = s.pos.x - world_x
        local dy = s.pos.y - world_y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist <= 7.0 and dist > 0.05 and is_land_connected(world_x, world_y, s.pos.x, s.pos.y) then
            table.insert(nearby_sites, {
                site = s,
                dist = dist,
            })
        end
    end
    table.sort(nearby_sites, function(a, b) return a.dist < b.dist end)

    for _, cand in ipairs(nearby_sites) do
        local site = cand.site
        local site_owner = get_site_active_occupant(site) or (site.cur_owner_id and site.cur_owner_id >= 0 and df.historical_entity.find(site.cur_owner_id)) or (site.civ_id and site.civ_id >= 0 and df.historical_entity.find(site.civ_id))
        local is_tower = is_tower_site(site) or is_tower_faction(site_owner)
        local eff_civ = is_tower and (site_owner or site) or (site_owner and (get_effective_civ(site_owner) or site_owner) or nil)
        local eff_key = is_tower and ("tower_" .. site.id) or (eff_civ and tostring(eff_civ.id) or ("site_" .. site.id))

        if not seen_site_ids[site.id] and (is_tower or not seen_entities[eff_key]) then
            seen_site_ids[site.id] = true
            seen_entities[eff_key] = true

            local oname = is_tower and (site_owner and dfhack.translation.translateName(site_owner.name, true) or "Tower") or (eff_civ and dfhack.translation.translateName(eff_civ.name, true) or "unclaimed")
            local orace = is_tower and "tower" or (eff_civ and format_entity_race(eff_civ) or "wilderness")

            if orace ~= "wilderness" and orace ~= "unknown" then
                local sname = dfhack.translation.translateName(site.name, true)
                local status_str, status_pen = get_diplomatic_status(eff_civ, player_civ, nil)
                if is_tower then
                    status_str = "hostile"
                    status_pen = COLOR_LIGHTRED
                end
                local stype = format_site_type(site)
                local site_live_pop = get_site_actual_live_pop(site, stype) or 0
                local hist_pop = format_population(site_live_pop)
                if hist_pop == "" then hist_pop = "few" end

                local cand_pop_fmt = format_est_pop(site_live_pop)

                local dist_val = math.max(1, math.floor(cand.dist + 0.5))
                local dir = calculate_direction(world_x, world_y, site.pos.x, site.pos.y)
                local t_str = format_travel_time(dist_val, dir)

                local war_with_site = false
                if site_owner_entity and eff_civ and check_entities_at_war(site_owner_entity, eff_civ) then
                    war_with_site = true
                end
                if is_tower then
                    war_with_site = true
                end

                local siege_str = get_siege_status(eff_civ, player_civ, site_owner_entity, is_tower, nil, site_live_pop, cand_pop_fmt)

                table.insert(entries, {
                    civ = eff_civ,
                    rname = orace,
                    cname = oname,
                    sname = sname,
                    stype = stype,
                    dist = dist_val,
                    travel_str = t_str,
                    history_pop = hist_pop,
                    est_pop = cand_pop_fmt,
                    siege_str = siege_str,
                    direction = dir,
                    status = status_str,
                    status_pen = status_pen,
                    war_with_site = war_with_site,
                    is_primary_site = false,
                })
            end
        end
    end

    -- D. Deduplicate entries: ensure no duplicate site/civ rows
    local unique_entries = {}
    local seen_keys = {}

    for _, ent in ipairs(entries) do
        local key = string.format("%s|%s|%s|%s", ent.sname or "", ent.stype or "", ent.rname or "", ent.travel_str or "")
        if not seen_keys[key] then
            seen_keys[key] = true
            table.insert(unique_entries, ent)
        end
    end
    entries = unique_entries

    table.sort(entries, function(a, b)
        local a_prim = (a.is_primary_site == true)
        local b_prim = (b.is_primary_site == true)
        if a_prim ~= b_prim then
            return a_prim
        end
        local a_here = (a.travel_str == "here" or a.dist == 0)
        local b_here = (b.travel_str == "here" or b.dist == 0)
        if a_here ~= b_here then
            return a_here
        end
        if a.dist ~= b.dist then
            return a.dist < b.dist
        end
        if a.sname and b.sname and a.sname ~= b.sname then
            return a.sname < b.sname
        end
        return (a.rname or "") < (b.rname or "")
    end)

    return {
        entries = entries,
        world_x = world_x,
        world_y = world_y,
        player_race = player_race,
        player_civ_name = player_civ_name,
        site_owner_entity = site_owner_entity,
        site_info_str = site_info_str,
        pop_info_str = pop_info_str,
        urban_info_str = urban_info_str,
    }
end

-- Draggable GUI window component
EmbarkNeighbors = defclass(EmbarkNeighbors, widgets.Window)
EmbarkNeighbors.ATTRS {
    frame={w=136, h=27, l=2, t=2},
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
        local line = string.format('%-16.16s | %-20.20s | %-12.12s | %-8.8s | %-16.16s | %-14.14s | %s',
            n.travel_str, n.rname, n.history_pop, n.est_pop, n.siege_str or '-', n.stype, n.sname)
        table.insert(choices, {
            text={
                {text=line, pen=n.status_pen}
            },
            search_key=n.rname,
        })
    end

    local site_lines = split_text_wrap(data.site_info_str, 120)
    local site_tokens = {
        {text='site:   ', pen=COLOR_GREY},
        {text=site_lines[1] or '', pen=COLOR_WHITE},
    }
    for i = 2, #site_lines do
        table.insert(site_tokens, NEWLINE)
        table.insert(site_tokens, {text='        ' .. site_lines[i], pen=COLOR_WHITE})
    end

    local urban_lines = {}
    if data.urban_info_str and #data.urban_info_str > 0 then
        urban_lines = split_text_wrap(data.urban_info_str, 120)
    end

    local top_y = #site_lines
    local pop_y = top_y
    top_y = top_y + 1

    local urban_y = nil
    local urban_h = 0
    if #urban_lines > 0 then
        urban_y = top_y
        urban_h = #urban_lines
        top_y = top_y + urban_h
    end

    local player_y = top_y
    local legend_y = top_y + 1
    local header_y = top_y + 3
    local total_header_h = top_y + 4

    local subviews = {
        widgets.Label{
            frame={t=0, l=0, r=0, h=#site_lines},
            text=site_tokens,
        },
        widgets.Label{
            frame={t=pop_y, l=0},
            text={
                {text='pop:    ', pen=COLOR_GREY},
                {text=data.pop_info_str or '0', pen=COLOR_WHITE},
            }
        },
    }

    if urban_y and #urban_lines > 0 then
        local urban_tokens = {
            {text='urban:  ', pen=COLOR_GREY},
            {text=urban_lines[1], pen=COLOR_WHITE},
        }
        for u = 2, #urban_lines do
            table.insert(urban_tokens, NEWLINE)
            table.insert(urban_tokens, {text='        ' .. urban_lines[u], pen=COLOR_WHITE})
        end
        table.insert(subviews, widgets.Label{
            frame={t=urban_y, l=0, r=0, h=urban_h},
            text=urban_tokens,
        })
    end

    table.insert(subviews, widgets.Label{
        frame={t=player_y, l=0},
        text={
            {text='player: ', pen=COLOR_GREY},
            {text='[' .. data.player_race .. '] ' .. data.player_civ_name, pen=COLOR_WHITE},
        }
    })
    table.insert(subviews, widgets.Label{
        frame={t=legend_y, l=0},
        text={
            {text='legend: ', pen=COLOR_GREY},
            {text='hostile', pen=COLOR_LIGHTRED},
            {text=' | ', pen=COLOR_DARKGREY},
            {text='peaceful', pen=COLOR_LIGHTBLUE},
            {text=' | ', pen=COLOR_DARKGREY},
            {text='neutral', pen=COLOR_WHITE},
        }
    })
    table.insert(subviews, widgets.Label{
        frame={t=header_y, l=0},
        text={
            {text=string.format('%-16.16s | %-20.20s | %-12.12s | %-8.8s | %-16.16s | %-14.14s | %s',
                'travel', 'civ race', 'hist. pop', 'est. pop', 'sieges', 'site type', 'site name'), pen=COLOR_YELLOW},
        }
    })

    self:addviews{
        widgets.Panel{
            frame={t=0, l=0, r=0, h=total_header_h},
            subviews=subviews,
        },
        widgets.List{
            view_id='list',
            frame={t=total_header_h, b=0, l=0, r=0},
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
    local is_world = df.viewscreen_worldst:is_instance(scr)
    local is_fort = df.viewscreen_dwarfmodest:is_instance(scr) and dfhack.isMapLoaded()
    local is_embark = df.viewscreen_choose_start_sitest:is_instance(scr)
    if not is_world and not is_fort and not is_embark then
        qerror('must be on the embark site selection screen, world map screen, or in fortress mode')
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

    print(string.format('%-16.16s | %-20.20s | %-12.12s | %-8.8s | %-16.16s | %-14.14s | %s',
        'travel', 'civ race', 'hist. pop', 'est. pop', 'sieges', 'site type', 'site name'))
    print(string.rep('-', 120))

    for _, n in ipairs(data.entries) do
        print(string.format('%-16.16s | %-20.20s | %-12.12s | %-8.8s | %-16.16s | %-14.14s | %s',
            n.travel_str, n.rname, n.history_pop or '', n.est_pop or '', n.siege_str or '-', n.stype, n.sname))
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
