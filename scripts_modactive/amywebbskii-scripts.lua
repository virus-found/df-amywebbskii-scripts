-- amywebbskii-scripts: interactive switchboard, auto-run manager, and QoL utilities for Dwarf Fortress
--@module = true

local gui = require('gui')
local widgets = require('gui.widgets')
local json = require('json')

local CONFIG_PATH = 'dfhack-config/amywebbskii-scripts.json'
local INIT_PATH = dfhack.getDFPath() .. '/dfhack-config/init/onMapLoad.init'

local TOOLS = {
    {
        key = 'embark-neighbors',
        name = 'embark neighbors',
        cmd = 'neighbors',
        category = 'embark',
        desc = 'interactive gui table on the embark screen showing accurate population slice estimations, civ races, site types, conflict status, and travel distances.',
        enable = function()
            pcall(dfhack.run_command, 'keybinding', 'add', 'N@choose_start_site', 'neighbors')
        end,
        disable = function()
            pcall(dfhack.run_command, 'keybinding', 'clear', 'N@choose_start_site')
        end,
        run = function()
            dfhack.run_command('neighbors')
        end,
    },
    {
        key = 'choose-your-hermit',
        name = 'choose your hermit',
        cmd = 'choose_hermit',
        category = 'fort',
        desc = 'select a specific dwarf from your starting seven to embark as a lone hermit, dismissing the others.',
        enable = function()
            if not dfhack.isMapLoaded() then return end
            pcall(dfhack.run_command, 'enable', 'hermit')
        end,
        disable = function()
            pcall(dfhack.run_command, 'disable', 'hermit')
        end,
        run = function()
            dfhack.run_command('choose_hermit')
        end,
    },
    {
        key = 'wagonless-hermit',
        name = 'wagonless hermit',
        cmd = 'hermit-no-wagon',
        category = 'fort',
        desc = 'suppresses the embark wagon and excess draft animals for a true wilderness hermit survival experience.',
        enable = function()
            if not dfhack.isMapLoaded() then return end
            pcall(dfhack.run_command, 'hermit-no-wagon')
        end,
        disable = function()
            -- wagonless is a one-time start cleanup
        end,
        run = function()
            dfhack.run_command('hermit-no-wagon')
        end,
    },
    {
        key = 'claim-foreign-items',
        name = 'claim foreign items',
        cmd = 'claim_foreign_items',
        category = 'fort',
        desc = 'automatically or manually reclaims external items dropped by visiting caravans, merchants, and siegers.',
        enable = function()
            if not dfhack.isMapLoaded() then return end
            pcall(dfhack.run_command, 'claim_foreign_items', '--auto')
        end,
        disable = function()
            pcall(dfhack.run_command, 'claim_foreign_items', '--stop')
        end,
        run = function()
            dfhack.run_command('claim_foreign_items', '--force')
        end,
    },
    {
        key = 'slow-digging',
        name = 'slow digging',
        cmd = 'slow_digging',
        category = 'fort',
        desc = 'slows down raw mining speed by a configurable multiplier to give fortress expansion weight and deliberate pacing.',
        enable = function()
            if not dfhack.isMapLoaded() then return end
            pcall(dfhack.run_command, 'enable', 'slow-digging')
        end,
        disable = function()
            pcall(dfhack.run_command, 'disable', 'slow-digging')
        end,
        run = function()
            dfhack.run_command('slow_digging')
        end,
    },
}

-- ---- configuration & persistence --------------------------------------------
local function load_config()
    local cfg = json.open(CONFIG_PATH)
    if not cfg.data or type(cfg.data) ~= 'table' then
        cfg.data = {}
    end
    -- default all tools to enabled (true) if unconfigured
    for _, t in ipairs(TOOLS) do
        if cfg.data[t.key] == nil then
            cfg.data[t.key] = true
        end
    end
    return cfg
end

local function is_on(key)
    local cfg = load_config()
    return cfg.data[key] == true
end

local function set_on(key, enabled)
    local cfg = load_config()
    cfg.data[key] = enabled and true or false
    cfg:write()
end

local function set_autostart(arm)
    local lines = {}
    local f = io.open(INIT_PATH, 'r')
    if f then
        for line in f:lines() do
            if not line:match('^%s*amywebbskii%-scripts') then
                lines[#lines + 1] = line
            end
        end
        f:close()
    end
    if arm then
        lines[#lines + 1] = 'amywebbskii-scripts apply'
    end
    local w = io.open(INIT_PATH, 'w')
    if not w then return false end
    w:write(table.concat(lines, '\n'))
    if #lines > 0 then w:write('\n') end
    w:close()
    return true
end

local function mode_active(m)
    if m == 'any' or m == 'embark' then return true end
    if m == 'fort' then return dfhack.world.isFortressMode() and dfhack.isMapLoaded() end
    return true
end

local function apply_tool(tool)
    if not mode_active(tool.category) then return end
    if is_on(tool.key) then
        if tool.enable then
            local ok, err = pcall(tool.enable)
            if not ok then print(('amywebbskii-scripts: enable error on %s: %s'):format(tool.name, tostring(err))) end
        end
    else
        if tool.disable then
            local ok, err = pcall(tool.disable)
            if not ok then print(('amywebbskii-scripts: disable error on %s: %s'):format(tool.name, tostring(err))) end
        end
    end
end

local function apply_all()
    print('amywebbskii-scripts: applying autorun selection...')
    for _, tool in ipairs(TOOLS) do
        apply_tool(tool)
    end
end

local function wrap_text(text, width)
    width = width or 40
    local lines = {}
    for paragraph in tostring(text):gmatch('[^\r\n]+') do
        local line = ''
        for word in paragraph:gmatch('%S+') do
            if #line == 0 then
                line = word
            elseif #line + 1 + #word <= width then
                line = line .. ' ' .. word
            else
                table.insert(lines, line)
                line = word
            end
        end
        if #line > 0 then
            table.insert(lines, line)
        end
    end
    return table.concat(lines, '\n')
end

-- ---- GUI --------------------------------------------------------------------
AmyWindow = defclass(AmyWindow, widgets.Window)
AmyWindow.ATTRS{
    frame_title = 'amywebbskii-scripts',
    frame = {w = 80, h = 26},
    resizable = true,
    resize_min = {w = 64, h = 20},
}

function AmyWindow:init()
    self:addviews{
        widgets.Label{
            frame = {l = 0, t = 0},
            text = {
                {text = 'amywebbskii scripts suite', pen = COLOR_LIGHTCYAN},
                {text = '  (dfhack qol & fortress utilities)', pen = COLOR_GREY},
            },
        },
        widgets.List{
            view_id = 'tool_list',
            frame = {l = 0, t = 2, w = 32, b = 2},
            on_select = function(_, choice) self:show_tool(choice.item) end,
        },
        widgets.Panel{
            frame = {l = 34, t = 2, r = 0, b = 2},
            subviews = {
                widgets.Label{
                    view_id = 'tool_title',
                    frame = {l = 0, t = 0},
                    text = '',
                },
                widgets.Label{
                    view_id = 'tool_cmd',
                    frame = {l = 0, t = 2},
                    text = '',
                },
                widgets.Label{
                    view_id = 'tool_desc',
                    frame = {l = 0, t = 4, r = 0},
                    auto_height = true,
                    text = '',
                },
            },
        },
        widgets.HotkeyLabel{
            frame = {l = 0, b = 0},
            key = 'CUSTOM_T',
            label = 'toggle autorun',
            on_activate = function()
                local _, choice = self.subviews.tool_list:getSelected()
                if choice and choice.item then self:toggle_tool(choice.item) end
            end,
        },
        widgets.HotkeyLabel{
            frame = {l = 22, b = 0},
            key = 'CUSTOM_R',
            label = 'run manually now',
            on_activate = function()
                local _, choice = self.subviews.tool_list:getSelected()
                if choice and choice.item then self:run_tool(choice.item) end
            end,
        },
    }
    self:refresh()
end

function AmyWindow:onInput(keys)
    if keys.SELECT or keys.CUSTOM_SPACE or keys.CUSTOM_T then
        local _, choice = self.subviews.tool_list:getSelected()
        if choice and choice.item then
            self:toggle_tool(choice.item)
            return true
        end
    end
    if keys.CUSTOM_R then
        local _, choice = self.subviews.tool_list:getSelected()
        if choice and choice.item then
            self:run_tool(choice.item)
            return true
        end
    end
    return AmyWindow.super.onInput(self, keys)
end

function AmyWindow:refresh()
    local list = self.subviews.tool_list
    local choices = {}
    for _, tool in ipairs(TOOLS) do
        local on = is_on(tool.key)
        table.insert(choices, {
            text = {
                {text = on and '[x] ' or '[ ] ', pen = on and COLOR_LIGHTGREEN or COLOR_DARKGREY},
                {text = tool.name, pen = on and COLOR_WHITE or COLOR_GREY},
            },
            item = tool,
        })
    end
    local prev_idx = list.selected or 1
    list:setChoices(choices, prev_idx)
    local _, cur = list:getSelected()
    if cur and cur.item then
        self:show_tool(cur.item)
    elseif #TOOLS > 0 then
        self:show_tool(TOOLS[1])
    end
end

function AmyWindow:toggle_tool(tool)
    if not tool then return end
    local new_state = not is_on(tool.key)
    set_on(tool.key, new_state)
    apply_tool(tool)
    self:refresh()
end

function AmyWindow:show_tool(tool)
    if not tool then return end
    self.subviews.tool_title:setText({
        {text = tool.name, pen = COLOR_WHITE},
        {text = ('  [%s]'):format(tool.category:upper()), pen = COLOR_LIGHTCYAN},
    })
    self.subviews.tool_cmd:setText({
        {text = 'command: ', pen = COLOR_DARKGREY},
        {text = tool.cmd, pen = COLOR_LIGHTYELLOW},
    })
    local desc_w = math.max(36, self.frame.w - 38)
    self.subviews.tool_desc:setText(wrap_text(tool.desc, desc_w))
end

function AmyWindow:run_tool(tool)
    if not tool then return end
    print(('amywebbskii-scripts: manually executing `%s`...'):format(tool.cmd))
    if tool.run then
        tool.run()
    else
        dfhack.run_command(tool.cmd)
    end
end

AmyScreen = defclass(AmyScreen, gui.ZScreen)
AmyScreen.ATTRS{focus_path = 'amywebbskii-scripts', def_actions = {dismiss = 'LEAVESCREEN'}}

function AmyScreen:init()
    self:addviews{AmyWindow{}}
end

function AmyScreen:onDismiss()
    view = nil
end

-- ---- entry point ------------------------------------------------------------
local args = {...}
local cmd_arg = args[1]

if cmd_arg == 'apply' then
    apply_all()
    set_autostart(true)
    return
elseif cmd_arg == 'status' then
    print('amywebbskii-scripts configuration status:')
    for _, t in ipairs(TOOLS) do
        local on = is_on(t.key)
        print(string.format('  [%s] %-22s (%s) - cmd: %s', on and 'x' or ' ', t.name, t.category, t.cmd))
    end
    return
elseif cmd_arg == 'enable' and args[2] then
    set_on(args[2], true)
    print(('amywebbskii-scripts: enabled %s'):format(args[2]))
    set_autostart(true)
    return
elseif cmd_arg == 'disable' and args[2] then
    set_on(args[2], false)
    print(('amywebbskii-scripts: disabled %s'):format(args[2]))
    return
elseif cmd_arg == 'help' or cmd_arg == '-h' or cmd_arg == '--help' then
    print('usage: amywebbskii-scripts [apply|status|enable <key>|disable <key>|help]')
    print('without arguments: opens the interactive switchboard gui.')
    return
end

set_autostart(true)
view = view and view:raise() or AmyScreen{}:show()
