-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 验证开镜时关闭物资、实体模型和人物菜单中的全部布尔绘制开关。
-- 验证已注册的 ESP 人物信息在 INV、VIS、DWN、ALLY 四种场景下都会关闭。
-- 验证无关视觉分支不受影响，退出开镜和脚本卸载时恢复原始状态。
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

local draw_items = control("draw_items", "物资绘制", true)
local entity_models_group = container("entity_models", "实体模型")
local entity_models_enabled = control("enabled", "Enabled", true)
local model_text = control("draw_text", "Model Text", true)
local item_manager = container("item_mgr", "Item Manager")
local battery_enabled = control("shield_battery", "Shield Battery", true)

local player_master = control("master", "Player Visuals", true)
local players_group = container("players", "Players")
local player_box_group = container("box", "Box")
local player_box_enabled = control("enabled", "Enabled", true)
local player_box_fill = control("fill", "Fill", false)
local player_name = control("name", "Name", true)
local player_health = control("health_bar", "Health Bar", true)
local player_distance = control("distance", "Distance", true)
local player_skeleton = control("skeleton", "Skeleton", true)
local player_minimap = control("minimap", "Minimap", true)
local player_offscreen = control("offscreen", "Offscreen", true)
local player_advanced = container("advanced", "Advanced Player Info")
local player_badge = control("badge", "Badge", false)
local player_color = control("color", "Color", { 1, 1, 1, 1 })

local unrelated_group = container("hud", "HUD")
local crosshair = control("crosshair", "Crosshair", true)
local damage_numbers = control("damage_numbers", "Damage Numbers", true)

local gui_children = {
    loots = { draw_items, entity_models_group, item_manager },
    ["loots.entity_models"] = { entity_models_enabled, model_text },
    ["loots.item_mgr"] = { battery_enabled },
    visuals = { players_group, unrelated_group },
    ["visuals.players"] = {
        player_master, player_box_group, player_name, player_health,
        player_distance, player_skeleton, player_minimap, player_offscreen,
        player_advanced, player_color,
    },
    ["visuals.players.box"] = { player_box_enabled, player_box_fill },
    ["visuals.players.advanced"] = { player_badge },
    ["visuals.hud"] = { crosshair, damage_numbers },
}

local controls_by_path = {
    ["loots.draw_items"] = draw_items,
    ["loots.entity_models.enabled"] = entity_models_enabled,
    ["loots.entity_models.draw_text"] = model_text,
    ["loots.item_mgr.shield_battery"] = battery_enabled,
    ["visuals.players.master"] = player_master,
    ["visuals.players.box.enabled"] = player_box_enabled,
    ["visuals.players.box.fill"] = player_box_fill,
    ["visuals.players.name"] = player_name,
    ["visuals.players.health_bar"] = player_health,
    ["visuals.players.distance"] = player_distance,
    ["visuals.players.skeleton"] = player_skeleton,
    ["visuals.players.minimap"] = player_minimap,
    ["visuals.players.offscreen"] = player_offscreen,
    ["visuals.players.advanced.badge"] = player_badge,
    ["visuals.players.color"] = player_color,
    ["visuals.hud.crosshair"] = crosshair,
    ["visuals.hud.damage_numbers"] = damage_numbers,
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
local shield = esp_element("Shield Info", { [0] = false, [1] = true, [2] = true, [3] = false })
local custom = esp_element("Custom Player Info", { [0] = true, [1] = true, [2] = false, [3] = true })

esp = {
    INV = 0,
    VIS = 1,
    DWN = 2,
    ALLY = 3,
    elements = {
        tag = tag,
        shield = shield,
        custom = custom,
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

_SCRIPT_PATH = "scripts/finished/draw/draw__ads_hide_loot_models_player_info__v01.lua"

dofile(_SCRIPT_PATH)

assert(type(event_handlers.frame_update) == "function")
assert(type(event_handlers.script_unloaded) == "function")
assert(#logs == 1 and logs[1] == "ADS loot/model/player-info drawing filter registered")

event_handlers.frame_update()
assert(draw_items.value == true and entity_models_enabled.value == true)
assert(battery_enabled.value == true)
assert(player_master.value == true and player_box_enabled.value == true)
assert(player_box_fill.value == false and player_name.value == true)
assert(player_health.value == true and player_distance.value == true)
assert(player_skeleton.value == true and player_minimap.value == true)
assert(player_offscreen.value == true and player_badge.value == false)
assert(type(player_color.value) == "table")
assert(crosshair.value == true and damage_numbers.value == true)
assert(tag.enabled[0] == true and tag.enabled[1] == false)
assert(shield.enabled[0] == false and shield.enabled[1] == true)

game.localplayer.is_zooming = true
event_handlers.frame_update()
assert(draw_items.value == false)
assert(entity_models_enabled.value == false and model_text.value == false)
assert(battery_enabled.value == false)
assert(player_master.value == false and player_box_enabled.value == false)
assert(player_box_fill.value == false and player_name.value == false)
assert(player_health.value == false and player_distance.value == false)
assert(player_skeleton.value == false and player_minimap.value == false)
assert(player_offscreen.value == false and player_badge.value == false)
assert(type(player_color.value) == "table")
assert(crosshair.value == true and damage_numbers.value == true)
assert(tag.enabled[0] == false and tag.enabled[1] == false)
assert(tag.enabled[2] == false and tag.enabled[3] == false)
assert(shield.enabled[0] == false and shield.enabled[1] == false)
assert(shield.enabled[2] == false and shield.enabled[3] == false)
assert(custom.enabled[0] == false and custom.enabled[1] == false)
assert(custom.enabled[2] == false and custom.enabled[3] == false)

draw_items.value = true
player_name.value = true
tag.enabled[0] = true
event_handlers.frame_update()
assert(draw_items.value == false and player_name.value == false and tag.enabled[0] == false)

game.localplayer.is_zooming = false
event_handlers.frame_update()
assert(draw_items.value == true and entity_models_enabled.value == true)
assert(model_text.value == true and battery_enabled.value == true)
assert(player_master.value == true and player_box_enabled.value == true)
assert(player_box_fill.value == false and player_name.value == true)
assert(player_health.value == true and player_distance.value == true)
assert(player_skeleton.value == true and player_minimap.value == true)
assert(player_offscreen.value == true and player_badge.value == false)
assert(crosshair.value == true and damage_numbers.value == true)
assert(tag.enabled[0] == true and tag.enabled[1] == false)
assert(tag.enabled[2] == true and tag.enabled[3] == true)
assert(shield.enabled[0] == false and shield.enabled[1] == true)
assert(shield.enabled[2] == true and shield.enabled[3] == false)
assert(custom.enabled[0] == true and custom.enabled[1] == true)
assert(custom.enabled[2] == false and custom.enabled[3] == true)

game.localplayer.is_zooming = true
event_handlers.frame_update()
event_handlers.script_unloaded({ script_path = "scripts/other.lua" })
assert(draw_items.value == false and player_name.value == false and tag.enabled[0] == false)

event_handlers.script_unloaded({ script_path = _SCRIPT_PATH })
assert(draw_items.value == true and entity_models_enabled.value == true)
assert(model_text.value == true and battery_enabled.value == true)
assert(player_master.value == true and player_box_enabled.value == true)
assert(player_name.value == true and player_health.value == true)
assert(player_skeleton.value == true and player_minimap.value == true)
assert(player_offscreen.value == true and player_badge.value == false)
assert(tag.enabled[0] == true and tag.enabled[1] == false)
assert(shield.enabled[0] == false and shield.enabled[1] == true)
assert(custom.enabled[0] == true and custom.enabled[1] == true)

print("draw__ads_hide_loot_models_player_info__v01_test: ok")
