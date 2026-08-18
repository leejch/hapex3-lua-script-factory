-- 验证开镜时保留原生骨骼、小地图和屏外指示器，不创建自定义绘制。
-- 验证玩家其他元素、物品绘制、模型绘制和非保护 ESP 元素会被关闭。
-- 验证退出开镜和脚本卸载时精确恢复原始开启与关闭状态。
-- 使用最小 HApex3.0 mock，不访问真实游戏、菜单或渲染设备。

local event_handlers = {}
local logs = {}

event = {
    on = function(name, handler)
        event_handlers[name] = handler
    end,
}

local function control(id, label, value)
    local item = { id = id, label = label, value = value }

    function item:get_id()
        return self.id
    end

    function item:get_label()
        return self.label
    end

    function item:has_value()
        return true
    end

    function item:get()
        return self.value
    end

    function item:set(next_value)
        self.value = next_value
    end

    return item
end

local function container(id, label)
    local item = { id = id, label = label }

    function item:get_id()
        return self.id
    end

    function item:get_label()
        return self.label
    end

    function item:has_value()
        return false
    end

    return item
end

local visual_master = control("master", "Player Visuals", true)
local players_group = container("players", "Players")
local players_master = control("enabled", "Enabled", true)
local box_group = container("box", "Box")
local box_enabled = control("enable", "Enabled", true)
local skeleton = control("skeleton", "骨骼", true)
local minimap = control("minimap", "小地图", true)
local offscreen = control("offscreen_indicator", "屏外指示器", true)
local name = control("name", "Name", false)
local color = control("color", "Color", { 1, 1, 1, 1 })

local loot_master = control("master", "Ground Loot", true)
local loot_text = control("text", "Item Text", true)
local model_master = control("master", "Entity Models", true)
local model_draw = control("draw", "Model Drawing", true)

local gui_children = {
    visuals = { visual_master, players_group },
    ["visuals.players"] = {
        players_master, box_group, skeleton, minimap, offscreen, name, color,
    },
    ["visuals.players.box"] = { box_enabled },
    loot = { loot_master, loot_text },
    models = { model_master, model_draw },
}

local controls_by_path = {
    ["visuals.master"] = visual_master,
    ["visuals.players.enabled"] = players_master,
    ["visuals.players.box.enable"] = box_enabled,
    ["visuals.players.skeleton"] = skeleton,
    ["visuals.players.minimap"] = minimap,
    ["visuals.players.offscreen_indicator"] = offscreen,
    ["visuals.players.name"] = name,
    ["visuals.players.color"] = color,
    ["loot.master"] = loot_master,
    ["loot.text"] = loot_text,
    ["models.master"] = model_master,
    ["models.draw"] = model_draw,
}

gui = {
    children = function(path)
        return gui_children[path] or {}
    end,
    find = function(path)
        return controls_by_path[path]
    end,
}

local function esp_element(label, enabled)
    local item = { label = label, enabled = enabled }

    function item:get_enabled(scenario)
        return self.enabled[scenario]
    end

    function item:set_enabled(value, scenario)
        self.enabled[scenario] = value
    end

    return item
end

local tag = esp_element("Player Tag", { [0] = true, [1] = false, [2] = true, [3] = true })
local native_skeleton = esp_element("Skeleton", { [0] = true, [1] = true, [2] = true, [3] = false })
local radar = esp_element("Minimap Radar", { [0] = true, [1] = true, [2] = false, [3] = true })
local arrow = esp_element("Offscreen Indicator", { [0] = false, [1] = true, [2] = true, [3] = true })

esp = {
    INV = 0,
    VIS = 1,
    DWN = 2,
    ALLY = 3,
    elements = {
        tag = tag,
        skeleton = native_skeleton,
        minimap = radar,
        offscreen_indicator = arrow,
    },
    find = function(id)
        return esp.elements[id]
    end,
}

game = {
    localplayer = { is_zooming = false },
}

log = {
    warn = function(message)
        logs[#logs + 1] = message
    end,
    success = function(message)
        logs[#logs + 1] = message
    end,
}

_SCRIPT_PATH = "scripts/finished/draw/draw__ads_skeleton_only__v01.lua"

dofile(_SCRIPT_PATH)

assert(type(event_handlers.frame_update) == "function")
assert(type(event_handlers.script_unloaded) == "function")
assert(#logs == 1 and logs[1] == "ADS native-skeleton visual filter registered")

event_handlers.frame_update()
assert(visual_master.value == true and players_master.value == true)
assert(box_enabled.value == true and skeleton.value == true)
assert(minimap.value == true and offscreen.value == true)
assert(loot_master.value == true and loot_text.value == true)
assert(model_master.value == true and model_draw.value == true)
assert(tag.enabled[0] == true)

game.localplayer.is_zooming = true
event_handlers.frame_update()
assert(visual_master.value == true and players_master.value == true)
assert(box_enabled.value == false and name.value == false)
assert(skeleton.value == true and minimap.value == true and offscreen.value == true)
assert(type(color.value) == "table")
assert(loot_master.value == false and loot_text.value == false)
assert(model_master.value == false and model_draw.value == false)
assert(tag.enabled[0] == false and tag.enabled[1] == false)
assert(tag.enabled[2] == false and tag.enabled[3] == false)
assert(native_skeleton.enabled[0] == true and native_skeleton.enabled[3] == false)
assert(radar.enabled[0] == true and radar.enabled[2] == false)
assert(arrow.enabled[0] == false and arrow.enabled[1] == true)

box_enabled.value = true
loot_master.value = true
tag.enabled[0] = true
event_handlers.frame_update()
assert(box_enabled.value == false and loot_master.value == false and tag.enabled[0] == false)

game.localplayer.is_zooming = false
event_handlers.frame_update()
assert(visual_master.value == true and players_master.value == true)
assert(box_enabled.value == true and skeleton.value == true)
assert(minimap.value == true and offscreen.value == true and name.value == false)
assert(loot_master.value == true and loot_text.value == true)
assert(model_master.value == true and model_draw.value == true)
assert(tag.enabled[0] == true and tag.enabled[1] == false)
assert(tag.enabled[2] == true and tag.enabled[3] == true)

game.localplayer.is_zooming = true
event_handlers.frame_update()
event_handlers.script_unloaded({ script_path = "scripts/other.lua" })
assert(box_enabled.value == false and loot_master.value == false and tag.enabled[0] == false)

event_handlers.script_unloaded({ script_path = _SCRIPT_PATH })
assert(box_enabled.value == true and loot_master.value == true and model_master.value == true)
assert(skeleton.value == true and minimap.value == true and offscreen.value == true)
assert(tag.enabled[0] == true and tag.enabled[1] == false)
assert(tag.enabled[2] == true and tag.enabled[3] == true)

print("draw__ads_skeleton_only__v01_test: ok")
