--@module = true
--@enable = true

local argparse = require('argparse')
local json = require('json')
local repeat_util = require('repeat-util')
local utils = require('utils')

local GLOBAL_KEY = 'slow_digging'
local CONFIG_FILE = 'dfhack-config/slow_digging.json'

local DIGGING_JOB_TYPES = {
    [df.job_type.Dig] = true,
    [df.job_type.CarveUpwardStaircase] = true,
    [df.job_type.CarveDownwardStaircase] = true,
    [df.job_type.CarveUpDownStaircase] = true,
    [df.job_type.CarveRamp] = true,
    [df.job_type.DigChannel] = true,
    [df.job_type.CarveFortification] = true,
    [df.job_type.CarveTrack] = true,
    [df.job_type.RemoveStairs] = true,
    [df.job_type.RemoveConstruction] = true,
}

local function get_default_config()
    return {
        enabled = true,
        setting = '/5',
        duration_multiplier = 5.0,
        include_smoothing = false,
    }
end

local config = json.open(CONFIG_FILE)
if not config.data or next(config.data) == nil then
    config.data = get_default_config()
    config:write()
end

for k, v in pairs(get_default_config()) do
    if config.data[k] == nil then
        config.data[k] = v
    end
end

-- Migration from old multiplier field if needed
if config.data.multiplier and not config.data.duration_multiplier then
    config.data.duration_multiplier = tonumber(config.data.multiplier) or 5.0
    config.data.setting = '/' .. tostring(config.data.duration_multiplier)
    config:write()
end

state = state or {}
state.job_ticks = state.job_ticks or {}

function isEnabled()
    return config.data.enabled
end

local function parse_setting(input)
    if not input then return nil, 'missing value' end
    local str = tostring(input):gsub('%s+', ''):lower()
    
    if str:sub(1, 1) == '*' or str:sub(1, 1) == 'x' then
        -- Fast / Speedup mode (e.g. *2, *2.5, x2)
        local num = tonumber(str:sub(2))
        if not num or num <= 0 then return nil, 'invalid number after *' end
        if num == 1.0 then return 1.0, '*1' end
        local dur = 1.0 / num
        return dur, ('*%s'):format(num == math.floor(num) and tostring(math.floor(num)) or tostring(num))
    elseif str:sub(1, 1) == '/' then
        -- Slow mode (e.g. /5, /10, /2.5)
        local num = tonumber(str:sub(2))
        if not num or num <= 0 then return nil, 'invalid number after /' end
        if num == 1.0 then return 1.0, '/1' end
        return num, ('/%s'):format(num == math.floor(num) and tostring(math.floor(num)) or tostring(num))
    else
        -- Plain number: if >= 1, default to slowdown (/N); if < 1, invert
        local num = tonumber(str)
        if not num or num <= 0 then return nil, 'must be a positive number, e.g. /5 (slower) or *2 (faster)' end
        if num == 1.0 then
            return 1.0, '/1'
        elseif num > 1.0 then
            return num, ('/%s'):format(num == math.floor(num) and tostring(math.floor(num)) or tostring(num))
        else
            local speed = 1.0 / num
            return num, ('*%s'):format(speed == math.floor(speed) and tostring(math.floor(speed)) or tostring(speed))
        end
    end
end

local function add_skill_exp(unit, skill_id, amount)
    if not unit or not unit.status or not unit.status.current_soul or amount == 0 then
        return
    end

    local soul = unit.status.current_soul
    local skill = nil
    for _, sk in ipairs(soul.skills) do
        if sk.id == skill_id then
            skill = sk
            break
        end
    end

    if not skill then
        skill = df.unit_skill:new()
        skill.id = skill_id
        skill.rating = 0
        skill.experience = 0
        soul.skills:insert('#', skill)
    end

    if amount > 0 then
        skill.experience = skill.experience + amount
        while true do
            local needed = 500 + (100 * skill.rating)
            if skill.experience >= needed then
                skill.experience = skill.experience - needed
                skill.rating = skill.rating + 1
            else
                break
            end
        end
    else
        -- In case of speedup where we adjust down the per-tile XP
        local deduct = math.abs(amount)
        if skill.experience >= deduct then
            skill.experience = skill.experience - deduct
        else
            skill.experience = 0
        end
    end
end

local function on_tick()
    if not isEnabled() or not dfhack.isMapLoaded() then
        return
    end

    local dur_mult = tonumber(config.data.duration_multiplier) or 5.0
    if math.abs(dur_mult - 1.0) < 0.001 then
        return
    end

    state.job_ticks = state.job_ticks or {}
    local seen_jobs = {}

    for _, unit in ipairs(df.global.world.units.active) do
        if dfhack.units.isCitizen(unit) and unit.job and unit.job.current_job then
            local job = unit.job.current_job
            local is_target = DIGGING_JOB_TYPES[job.job_type]
            local skill_id = df.job_skill.MINING

            if not is_target and config.data.include_smoothing then
                if job.job_type == df.job_type.DetailWall or job.job_type == df.job_type.DetailFloor then
                    is_target = true
                    skill_id = df.job_skill.ENGRAVING
                end
            end

            if is_target and job.completion_timer > 0 then
                local jid = job.id
                seen_jobs[jid] = true

                local jdata = state.job_ticks[jid]
                if not jdata then
                    jdata = {
                        unit_id = unit.id,
                        skill_id = skill_id,
                        last_val = job.completion_timer,
                        delay_count = 0,
                        ticks_worked = 0,
                    }
                    state.job_ticks[jid] = jdata
                end

                jdata.ticks_worked = (jdata.ticks_worked or 0) + 1

                -- Timer adjustments
                if job.completion_timer < jdata.last_val then
                    if dur_mult > 1.0 then
                        -- SLOWDOWN MODE (/N): Hold timer for (dur_mult - 1) ticks
                        local delay_target = math.floor(dur_mult - 1.0 + 0.5)
                        if jdata.delay_count < delay_target then
                            job.completion_timer = jdata.last_val
                            jdata.delay_count = jdata.delay_count + 1
                        else
                            jdata.last_val = job.completion_timer
                            jdata.delay_count = 0
                        end
                    elseif dur_mult < 1.0 then
                        -- SPEEDUP MODE (*S): Advance timer by extra ticks
                        local speed = 1.0 / dur_mult
                        local extra_skip = math.max(1, math.floor(speed - 1.0 + 0.5))
                        job.completion_timer = math.max(0, job.completion_timer - extra_skip)
                        jdata.last_val = job.completion_timer
                    end
                else
                    jdata.last_val = job.completion_timer
                end
            end
        end
    end

    -- Process finished jobs and adjust skill experience to keep XP/time constant
    for jid, jdata in pairs(state.job_ticks) do
        if not seen_jobs[jid] then
            local ticks = jdata.ticks_worked or 0
            local last_v = jdata.last_val or 99
            if ticks >= 2 and last_v <= 2 and jdata.unit_id and jdata.skill_id then
                local unit = df.unit.find(jdata.unit_id)
                if unit and not dfhack.units.isDead(unit) then
                    -- Base vanilla experience per tile is 10 XP
                    -- Proportional adjustment: (dur_mult - 1.0) * 10
                    local xp_adjustment = math.floor((dur_mult - 1.0) * 10 + 0.5)
                    if xp_adjustment ~= 0 then
                        add_skill_exp(unit, jdata.skill_id, xp_adjustment)
                    end
                end
            end
            state.job_ticks[jid] = nil
        end
    end
end

function start()
    repeat_util.scheduleEvery(GLOBAL_KEY, 1, 'ticks', on_tick)
    config.data.enabled = true
    config:write()
end

function stop()
    repeat_util.cancel(GLOBAL_KEY)
    config.data.enabled = false
    config:write()
    state.job_ticks = {}
end

dfhack.onStateChange[GLOBAL_KEY] = function(code)
    if code == SC_WORLD_LOADED then
        if isEnabled() then
            start()
        end
    elseif code == SC_WORLD_UNLOADED then
        repeat_util.cancel(GLOBAL_KEY)
        state.job_ticks = {}
    end
end

-- If script is loaded into an already loaded world/map, activate immediately
if isEnabled() and dfhack.isMapLoaded() then
    start()
end

local function print_status()
    local enabled_str = isEnabled() and 'enabled' or 'disabled'
    local dur = tonumber(config.data.duration_multiplier) or 5.0
    local setting_str = config.data.setting or (dur >= 1.0 and ('/' .. tostring(dur)) or ('*' .. tostring(1.0 / dur)))
    local smooth_str = config.data.include_smoothing and 'included' or 'excluded'
    
    local speed_desc = ""
    if dur > 1.0 then
        speed_desc = string.format("%.1fx slower (%s)", dur, setting_str)
    elseif dur < 1.0 then
        local spd = 1.0 / dur
        speed_desc = string.format("%.1fx faster (%s)", spd, setting_str)
    else
        speed_desc = "1.0x (vanilla normal)"
    end

    local active_count = 0
    if state and state.job_ticks then
        for _ in pairs(state.job_ticks) do
            active_count = active_count + 1
        end
    end

    print(('Slow Digging is currently %s.'):format(enabled_str))
    print(('  %-20s %s'):format('Speed setting:', speed_desc))
    print(('  %-20s %s'):format('Wall/floor smooth:', smooth_str))
    print(('  %-20s %d'):format('Active scaled jobs:', active_count))
end

local function print_help()
    print([==[
Usage: slow_digging [<options>] [<command>]

Controls excavation duration and mining speed for all excavation jobs
(digging, channeling, staircases, ramps, fortifications, tracks) with
automatic skill experience normalization (XP/time stays 100% identical to vanilla).

Speed Settings:
    slow_digging /5          Set digging to 5x slower (default ascetic pace).
    slow_digging /10         Set digging to 10x slower.
    slow_digging *2          Set digging to 2x faster (speedup mode).
    slow_digging *5          Set digging to 5x faster.
    slow_digging 1           Restore standard vanilla 1.0x speed.

Commands:
    help                     Display this help text.
    status                   Show current status, speed factor, and XP scaling.
    enable|on                Enable speed multiplier.
    disable|off              Disable speed multiplier (restore 1x vanilla speed).
    set <setting>            Set speed (e.g. /5, *2, /10, *1.5).
    include-smoothing on|off Toggle wall/floor smoothing multiplier (default: off).

Examples:
    slow_digging /5          5x slower excavation + 50 XP/tile (same XP/min).
    slow_digging *2          2x faster excavation + 5 XP/tile (same XP/min).
    slow_digging disable     Temporarily disable.
]==])
end

local function main(...)
    local args = {...}
    if #args == 0 then
        print_status()
        return
    end

    local cmd = tostring(args[1]):lower()

    if cmd == 'help' or cmd == '-h' or cmd == '--help' then
        print_help()
        return
    elseif cmd == 'status' then
        print_status()
        return
    elseif cmd == 'enable' or cmd == 'on' or cmd == '1' then
        start()
        print('Slow Digging enabled.')
        print_status()
    elseif cmd == 'disable' or cmd == 'off' or cmd == '0' then
        stop()
        print('Slow Digging disabled.')
    elseif cmd == 'set' then
        local dur, setting_str = parse_setting(args[2])
        if not dur then
            qerror(('Invalid setting: %s. Use /5 (slower) or *2 (faster).'):format(setting_str))
        end
        config.data.duration_multiplier = dur
        config.data.multiplier = dur
        config.data.setting = setting_str
        config:write()
        print(('Slow Digging speed set to %s.'):format(setting_str))
        if not isEnabled() then
            start()
        end
    elseif cmd == 'include-smoothing' then
        local sub = tostring(args[2] or ''):lower()
        if sub == 'on' or sub == '1' or sub == 'true' then
            config.data.include_smoothing = true
        elseif sub == 'off' or sub == '0' or sub == 'false' then
            config.data.include_smoothing = false
        else
            config.data.include_smoothing = not config.data.include_smoothing
        end
        config:write()
        print(('Wall/Floor smoothing is now %s.'):format(config.data.include_smoothing and 'included' or 'excluded'))
    else
        local dur, setting_str = parse_setting(args[1])
        if dur then
            config.data.duration_multiplier = dur
            config.data.multiplier = dur
            config.data.setting = setting_str
            config:write()
            print(('Slow Digging speed set to %s.'):format(setting_str))
            if not isEnabled() then
                start()
            end
        else
            qerror(('Unknown command or setting: "%s". Use "slow_digging help" for usage.'):format(args[1]))
        end
    end
end

if dfhack_flags.module then
    return _ENV
end

main(...)
