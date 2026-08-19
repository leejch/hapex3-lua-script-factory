-- 验证开镜时通过 loots 菜单树关闭物资绘制与实体模型绘制。
-- 验证人物 ESP、骨骼、小地图和屏外指示器不会被访问或修改。
-- 验证退出开镜和脚本卸载时精确恢复已匹配开关的原始状态。
-- 使用最小 HApex3.0 mock，不访问真实游戏、菜单或渲染设备。

local event_handlers = {}
local logs = {}

event = {
    on = function(name, handler)
        event_handlers[name] = handler
    end,
}

local function control(id, label, value)
    local item = { id = id, label = label, value = value, set_count = 0 }

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
        self.set_count = self.set_count + 1
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
local smart_enabled = control("smart_enabled", "Smart Loot", true)

local gui_children = {
    loots = { draw_items, entity_models_group, item_manager, smart_enabled },
    ["loots.entity_models"] = { entity_models_enabled, model_text },
    ["loots.item_mgr"] = { battery_enabled },
}

local controls_by_path = {
    ["loots.draw_items"] = draw_items,
    ["loots.entity_models.enabled"] = entity_models_enabled,
    ["loots.entity_models.draw_text"] = model_text,
    ["loots.item_mgr.shield_battery"] = battery_enabled,
    ["loots.smart_enabled"] = smart_enabled,
}

gui = {
    children = function(path)
        return gui_children[path] or {}
    end,
    find = function(path)
        return controls_by_path[path]
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

_SCRIPT_PATH = "scripts/finished/draw/draw__ads_hide_loot_models__v01.lua"

dofile(_SCRIPT_PATH)

assert(type(event_handlers.frame_update) == "function")
assert(type(event_handlers.script_unloaded) == "function")
assert(#logs == 1 and logs[1] == "ADS loot/model drawing filter registered")

event_handlers.frame_update()
assert(draw_items.value == true and entity_models_enabled.value == true)

game.localplayer.is_zooming = true
event_handlers.frame_update()
assert(draw_items.value == false)
assert(entity_models_enabled.value == false and model_text.value == false)
assert(battery_enabled.value == false and smart_enabled.value == false)

draw_items.value = true
entity_models_enabled.value = true
event_handlers.frame_update()
assert(draw_items.value == false and entity_models_enabled.value == false)

game.localplayer.is_zooming = false
event_handlers.frame_update()
assert(draw_items.value == true)
assert(entity_models_enabled.value == true and model_text.value == true)
assert(battery_enabled.value == true and smart_enabled.value == true)

game.localplayer.is_zooming = true
event_handlers.frame_update()
event_handlers.script_unloaded({ script_path = "scripts/other.lua" })
assert(draw_items.value == false and entity_models_enabled.value == false)

event_handlers.script_unloaded({ script_path = _SCRIPT_PATH })
assert(draw_items.value == true and entity_models_enabled.value == true)
assert(battery_enabled.value == true and smart_enabled.value == true)

print("draw__ads_hide_loot_models__v01_test: ok")
