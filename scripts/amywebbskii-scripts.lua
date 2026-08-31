-- amywebbskii-scripts: interactive suite switchboard & QoL utilities for Dwarf Fortress
--@module = true

local gui = require('gui')
local widgets = require('gui.widgets')

local TOOLS = {
    {
        key = 'embark-neighbors',
        name = 'Embark Neighbors',
        cmd = 'neighbors',
        desc = 'Interactive GUI table on the embark screen showing accurate population slice estimations, civ races, site types, conflict status, and travel distances.',
        category = 'embark',
    },
    {
        key = 'choose-your-hermit',
        name = 'Choose Your Hermit',
        cmd = 'choose_hermit',
        desc = 'Select a specific dwarf from your starting seven to embark as a lone hermit, dismissing the others.',
        category = 'fort',
    },
    {
        key = 'wagonless-hermit',
        name = 'Wagonless Hermit',
        cmd = 'hermit-no-wagon',
        desc = 'Suppresses the embark wagon and excess draft animals for a true wilderness hermit survival experience.',
        category = 'fort',
    },
    {
        key = 'claim-foreign-items',
        name = 'Claim Foreign Items',
        cmd = 'claim_foreign_items',
        desc = 'Automatically or manually reclaims external items dropped by visiting caravans, merchants, and siegers.',
        category = 'fort',
    },
    {
        key = 'slow-digging',
        name = 'Slow Digging',
        cmd = 'slow_digging',
        desc = 'Slows down raw mining speed by a configurable multiplier to give fortress expansion weight and deliberate pacing.',
        category = 'fort',
    },
}

AmyWindow = defclass(AmyWindow, widgets.Window)
AmyWindow.ATTRS{
    frame_title = 'amywebbskii-scripts',
    frame = {w = 78, h = 26},
    resizable = true,
    resize_min = {w = 60, h = 18},
}

function AmyWindow:init()
    self:addviews{
        widgets.Label{
            frame = {l = 0, t = 0},
            text = {
                {text = 'Amywebbskii Scripts Suite', pen = COLOR_LIGHTCYAN},
                {text = ' (DFHack QoL & Fortress Utilities)', pen = COLOR_GREY},
            },
        },
        widgets.Label{
            frame = {l = 0, t = 1},
            text = {
                {text = 'Select a tool to view details or execute:', pen = COLOR_DARKGREY},
            },
        },
        widgets.List{
            view_id = 'tool_list',
            frame = {l = 0, t = 3, w = 32, b = 0},
            on_select = function(_, choice) self:show_tool(choice.item) end,
            on_submit = function(_, choice) self:run_tool(choice.item) end,
        },
        widgets.Panel{
            frame = {l = 34, t = 3, r = 0, b = 0},
            subviews = {
                widgets.Label{
                    view_id = 'tool_title',
                    frame = {l = 0, t = 0},
                    text = '',
                },
                widgets.Label{
                    view_id = 'tool_cmd',
                    frame = {l = 0, t = 1},
                    text = '',
                },
                widgets.Label{
                    view_id = 'tool_desc',
                    frame = {l = 0, t = 3, r = 0},
                    auto_height = true,
                    text = '',
                },
                widgets.HotkeyLabel{
                    frame = {l = 0, b = 0},
                    key = 'SELECT',
                    label = 'Run tool command',
                    on_activate = function()
                        local list = self.subviews.tool_list
                        local choice = list:getSelected()
                        if choice and choice.item then self:run_tool(choice.item) end
                    end,
                },
            },
        },
    }
    self:refresh()
end

function AmyWindow:refresh()
    local list = self.subviews.tool_list
    local choices = {}
    for _, tool in ipairs(TOOLS) do
        table.insert(choices, {
            text = tool.name,
            item = tool,
        })
    end
    list:setChoices(choices)
    if #TOOLS > 0 then self:show_tool(TOOLS[1]) end
end

function AmyWindow:show_tool(tool)
    if not tool then return end
    self.subviews.tool_title:setText({{text = tool.name, pen = COLOR_WHITE}})
    self.subviews.tool_cmd:setText({
        {text = 'Command: ', pen = COLOR_DARKGREY},
        {text = tool.cmd, pen = COLOR_LIGHTGREEN},
    })
    self.subviews.tool_desc:setText(tool.desc)
end

function AmyWindow:run_tool(tool)
    if not tool then return end
    print(('amywebbskii-scripts: executing `%s`...'):format(tool.cmd))
    dfhack.run_command(tool.cmd)
end

AmyScreen = defclass(AmyScreen, gui.ZScreen)
AmyScreen.ATTRS{focus_path = 'amywebbskii-scripts', def_actions = {dismiss = 'LEAVESCREEN'}}

function AmyScreen:init()
    self:addviews{AmyWindow{}}
end

function AmyScreen:onDismiss()
    view = nil
end

local arg = ({...})[1]
if arg == 'help' or arg == '-h' or arg == '--help' then
    print('amywebbskii-scripts: QoL suite and launcher')
    print('Available tools:')
    for _, t in ipairs(TOOLS) do
        print(string.format('  %-22s (%s) - %s', t.cmd, t.category, t.name))
    end
    return
end

view = view and view:raise() or AmyScreen{}:show()
