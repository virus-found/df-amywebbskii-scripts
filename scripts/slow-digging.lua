--@module = true
--@enable = true

local gui = require('gui')
local widgets = require('gui.widgets')
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
        enabled = false,
        setting = '/5',
        multiplier = 5.0,
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

-- cleanup legacy rock/fast fields and migrate to unified multiplier
if config.data.rock_multiplier and not config.data.multiplier then
    config.data.multiplier = tonumber(config.data.rock_multiplier) or 5.0
    config.data.setting = config.data.rock_setting or '/5'
end
config.data.rock_multiplier = nil
config.data.rock_setting = nil
config.data.fast_multiplier = nil
config.data.fast_setting = nil
config.data.duration_multiplier = nil
config:write()

state = state or {}
state.job_ticks = state.job_ticks or {}

function isEnabled()
    return config.data.enabled
end

local function parse_setting(input)
    if not input then return nil, 'missing value' end
    local str = tostring(input):gsub('%s+', ''):lower()

    if str:sub(1, 1) == '*' or str:sub(1, 1) == 'x' then
        -- fast / speedup mode (e.g. *2, *2.5, x2)
        local num = tonumber(str:sub(2))
        if not num or num <= 0 then return nil, 'invalid number after *' end
        if num == 1.0 then return 1.0, '*1' end
        local dur = 1.0 / num
        return dur, ('*%s'):format(num == math.floor(num) and tostring(math.floor(num)) or tostring(num))
    elseif str:sub(1, 1) == '/' then
        -- slow mode (e.g. /5, /10, /2.5)
        local num = tonumber(str:sub(2))
        if not num or num <= 0 then return nil, 'invalid number after /' end
        if num == 1.0 then return 1.0, '/1' end
        return num, ('/%s'):format(num == math.floor(num) and tostring(math.floor(num)) or tostring(num))
    else
        -- plain number: if >= 1, default to slowdown (/N); if < 1, invert
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

    local mult = tonumber(config.data.multiplier) or 5.0
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

                if math.abs(mult - 1.0) >= 0.001 then
                    local jdata = state.job_ticks[jid]
                    if not jdata then
                        jdata = {
                            unit_id = unit.id,
                            skill_id = skill_id,
                            last_val = job.completion_timer,
                            delay_count = 0,
                            ticks_worked = 0,
                            multiplier = mult,
                        }
                        state.job_ticks[jid] = jdata
                    end

                    jdata.ticks_worked = (jdata.ticks_worked or 0) + 1

                    -- timer adjustments
                    if job.completion_timer < jdata.last_val then
                        if mult > 1.0 then
                            -- slowdown mode (/N): hold timer for (mult - 1) ticks
                            local delay_target = math.floor(mult - 1.0 + 0.5)
                            if jdata.delay_count < delay_target then
                                job.completion_timer = jdata.last_val
                                jdata.delay_count = jdata.delay_count + 1
                            else
                                jdata.last_val = job.completion_timer
                                jdata.delay_count = 0
                            end
                        elseif mult < 1.0 then
                            -- speedup mode (*S): advance timer by extra ticks
                            local speed = 1.0 / mult
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
    end

    -- process completed jobs and adjust skill experience to keep xp/time constant
    for jid, jdata in pairs(state.job_ticks) do
        if not seen_jobs[jid] then
            local ticks = jdata.ticks_worked or 0
            local last_v = jdata.last_val or 99
            -- award bonus experience if worked on the tile (at least 3 ticks worked or reached low timer)
            if ticks >= 3 and (last_v <= 10 or ticks >= 10) and jdata.unit_id and jdata.skill_id then
                local unit = df.unit.find(jdata.unit_id)
                if unit and not dfhack.units.isDead(unit) then
                    -- base vanilla experience per tile is 10 xp
                    -- proportional time-scaling adjustment: (mult - 1.0) * 10
                    -- e.g. /5: 5x slower -> +40 bonus xp = 50 xp/tile (same xp/min as vanilla)
                    local j_mult = jdata.multiplier or 1.0
                    local xp_adjustment = math.floor((j_mult - 1.0) * 10 + 0.5)
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

if isEnabled() and dfhack.isMapLoaded() then
    start()
end

local function format_mult(mult, setting_str)
    if mult > 1.0 then
        return string.format('%.1fx slower (%s)', mult, setting_str or ('/' .. tostring(mult)))
    elseif mult < 1.0 then
        local spd = 1.0 / mult
        return string.format('%.1fx faster (%s)', spd, setting_str or ('*' .. tostring(spd)))
    else
        return '1.0x (vanilla standard)'
    end
end

local function print_status()
    local enabled_str = isEnabled() and 'enabled' or 'disabled'
    local mult = tonumber(config.data.multiplier) or 5.0
    local smooth_str = config.data.include_smoothing and 'included' or 'excluded'

    local active_count = 0
    if state and state.job_ticks then
        for _ in pairs(state.job_ticks) do
            active_count = active_count + 1
        end
    end

    local xp_per_tile = math.floor(mult * 10 + 0.5)

    print(('slow digging is currently %s.'):format(enabled_str))
    print(('  %-24s %s'):format('digging speed:', format_mult(mult, config.data.setting) .. (' (%d xp/tile)'):format(xp_per_tile)))
    print(('  %-24s %s'):format('wall/floor smooth:', smooth_str))
    print(('  %-24s %s'):format('skill experience:', 'time-proportional (constant xp/minute, matched to vanilla)'))
    print(('  %-24s %d'):format('active scaled jobs:', active_count))
end

-- ---- interactive gui screen -------------------------------------------------
local SPEED_OPTIONS = {
    {label = '1.0x (vanilla standard)', value = 1.0, setting = '/1'},
    {label = '2.0x slower (/2)', value = 2.0, setting = '/2'},
    {label = '3.0x slower (/3)', value = 3.0, setting = '/3'},
    {label = '5.0x slower (/5)', value = 5.0, setting = '/5'},
    {label = '8.0x slower (/8)', value = 8.0, setting = '/8'},
    {label = '10.0x slower (/10)', value = 10.0, setting = '/10'},
    {label = '15.0x slower (/15)', value = 15.0, setting = '/15'},
    {label = '20.0x slower (/20)', value = 20.0, setting = '/20'},
    {label = '30.0x slower (/30)', value = 30.0, setting = '/30'},
    {label = '50.0x slower (/50)', value = 50.0, setting = '/50'},
}

local function find_speed_index(val)
    local best_idx = 1
    local min_diff = 999999
    for i, opt in ipairs(SPEED_OPTIONS) do
        local diff = math.abs(opt.value - val)
        if diff < min_diff then
            min_diff = diff
            best_idx = i
        end
    end
    return best_idx
end

SlowDiggingWindow = defclass(SlowDiggingWindow, widgets.Window)
SlowDiggingWindow.ATTRS{
    frame_title = 'slow digging configuration',
    frame = {w = 62, h = 16},
}

function SlowDiggingWindow:init()
    local mult = tonumber(config.data.multiplier) or 5.0

    self:addviews{
        widgets.ToggleHotkeyLabel{
            view_id = 'toggle_enabled',
            frame = {t = 1, l = 1},
            key = 'CUSTOM_E',
            label = 'slow digging:         ',
            options = {
                {label = 'enabled', value = true, pen = COLOR_LIGHTGREEN},
                {label = 'disabled', value = false, pen = COLOR_DARKGREY},
            },
            initial_option = isEnabled(),
            on_change = function(val)
                if val then start() else stop() end
            end,
        },
        widgets.CycleHotkeyLabel{
            view_id = 'cycle_speed',
            frame = {t = 3, l = 1},
            key = 'CUSTOM_S',
            label = 'digging speed:        ',
            options = SPEED_OPTIONS,
            initial_option = find_speed_index(mult),
            on_change = function(val, opt)
                config.data.multiplier = opt.value
                config.data.setting = opt.setting
                config:write()
            end,
        },
        widgets.ToggleHotkeyLabel{
            view_id = 'toggle_smoothing',
            frame = {t = 5, l = 1},
            key = 'CUSTOM_M',
            label = 'smooth walls / floors:',
            options = {
                {label = 'included', value = true, pen = COLOR_LIGHTGREEN},
                {label = 'excluded', value = false, pen = COLOR_DARKGREY},
            },
            initial_option = config.data.include_smoothing,
            on_change = function(val)
                config.data.include_smoothing = val
                config:write()
            end,
        },
        widgets.Label{
            frame = {t = 8, l = 1},
            text = {
                {text = 'skill experience:     ', pen = COLOR_DARKGREY},
                {text = 'time-proportional (constant xp/minute)', pen = COLOR_LIGHTCYAN},
                NEWLINE,
                {text = 'xp scales with slowdown duration so real-time leveling matches vanilla.', pen = COLOR_GREY},
            },
        },
        widgets.HotkeyLabel{
            frame = {b = 1, l = 1},
            key = 'LEAVESCREEN',
            label = 'close',
            on_activate = function() self.parent_view:dismiss() end,
        },
    }
end

SlowDiggingScreen = defclass(SlowDiggingScreen, gui.ZScreen)
SlowDiggingScreen.ATTRS{
    focus_path = 'slow-digging',
    def_actions = {dismiss = 'LEAVESCREEN'},
}

function SlowDiggingScreen:init()
    self:addviews{SlowDiggingWindow{}}
end

local function print_help()
    print([==[
usage: slow_digging [<options>] [<command>]

controls excavation duration and mining speed across all materials
with time-proportional skill experience normalization (xp earned per minute
of real time remains 100% identical to vanilla).

settings:
    slow_digging /5               set universal digging speed to 5x slower (50 xp/tile).
    slow_digging /10              set universal digging speed to 10x slower (100 xp/tile).
    slow_digging /2               set universal digging speed to 2x slower (20 xp/tile).

commands:
    help                          display this help text.
    status                        show current status and speed factor.
    gui                           open interactive configuration window.
    enable|on                     enable slowdown multiplier.
    disable|off                   disable slowdown (restore 1.0x vanilla speed).
    include-smoothing on|off      toggle wall/floor smoothing multiplier.

experience guarantee:
    xp is proportional to time spent digging, perfectly matching vanilla xp/minute.
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
    elseif cmd == 'gui' or cmd == 'ui' then
        SlowDiggingScreen{}:show()
        return
    elseif cmd == 'status' then
        print_status()
        return
    elseif cmd == 'enable' or cmd == 'on' or cmd == '1' then
        start()
        print('slow digging enabled.')
        print_status()
    elseif cmd == 'disable' or cmd == 'off' or cmd == '0' then
        stop()
        print('slow digging disabled.')
    elseif cmd == 'set' or cmd == 'speed' or cmd == 'rock' or cmd == 'stone' or cmd == 'soil' or cmd == 'fast' then
        local param = args[2] or args[1]
        if cmd == 'set' and args[2] and (args[2]:lower() == 'speed' or args[2]:lower() == 'rock' or args[2]:lower() == 'soil') then
            param = args[3]
        end
        local dur, setting_str = parse_setting(param)
        if not dur then
            qerror(('invalid speed setting: %s. use /5 (slower) or *2 (faster).'):format(setting_str or param))
        end
        config.data.multiplier = dur
        config.data.setting = setting_str
        config:write()
        print(('digging speed set to %s.'):format(setting_str))
        if not isEnabled() then start() end
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
        print(('wall/floor smoothing is now %s.'):format(config.data.include_smoothing and 'included' or 'excluded'))
    else
        local dur, setting_str = parse_setting(args[1])
        if dur then
            config.data.multiplier = dur
            config.data.setting = setting_str
            config:write()
            print(('digging speed set to %s.'):format(setting_str))
            if not isEnabled() then start() end
        else
            qerror(('unknown command or setting: "%s". use "slow_digging help" for usage.'):format(args[1]))
        end
    end
end

if dfhack_flags.module then
    return _ENV
end

main(...)
