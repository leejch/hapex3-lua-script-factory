-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 验证 ADS 视野锥内外的名称、段位、等级显示逻辑。
-- 验证独立开关、异常数据保护和不受 ADS 影响的自定义骨骼绘制。
-- 使用最小 HApex3.0 mock，不访问真实游戏、菜单或渲染设备。

local event_handlers = {}
local esp_callbacks = {}
local controls = {}
local draw_lines = {}
local logs = {}

event = {
    on = function(name, handler)
        event_handlers[name] = handler
    end,
}

local function make_control(id, value)
    local item = { id = id, value = value }

    function item:get()
        return self.value
    end

    function item:set(next_value)
        self.value = next_value
    end

    function item:set_hint()
        return self
    end

    function item:set_format()
        return self
    end

    controls[id] = item
    return item
end

local function make_group()
    local group = {}

    function group:checkbox(id, _, default)
        return make_control(id, default)
    end

    function group:slider_float(id, _, _, _, default)
        return make_control(id, default)
    end

    function group:color_edit(id, _, r, g, b, a)
        return make_control(id, { r, g, b, a or 1.0 })
    end

    return group
end

gui = {
    tab = function()
        local tab = {}

        function tab:group()
            return make_group()
        end

        return tab
    end,
}

draw = {
    rgba = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a }
    end,
    line = function(x1, y1, x2, y2, color, opts)
        draw_lines[#draw_lines + 1] = {
            x1 = x1,
            y1 = y1,
            x2 = x2,
            y2 = y2,
            color = color,
            thickness = opts.thickness,
        }
    end,
}

math.Vec3 = function(x, y, z)
    return { x = x, y = y, z = z }
end

math.CalcAngle = function(from_pos, to_pos)
    local dx = to_pos.x - from_pos.x
    local dy = to_pos.y - from_pos.y
    local dz = to_pos.z - from_pos.z
    local horizontal = math.sqrt(dx * dx + dy * dy)
    local pitch = -math.deg(math.atan(dz, horizontal))
    local yaw = math.deg(math.atan(dy, dx))
    return pitch, yaw
end

math.AngleNormalize = function(angle)
    while angle >= 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    return angle
end

math.WorldToScreen = function(world_pos)
    if world_pos.offscreen then
        return 0, 0, false
    end
    return 960, 540, true
end

esp = {
    add = function(id, callback, opts)
        local element = {}
        esp_callbacks[id] = { callback = callback, opts = opts, element = element }
        return element
    end,
}

log = {
    success = function(message)
        logs[#logs + 1] = message
    end,
}

local function make_player(fields)
    local player = fields

    function player:has_fresh_bones()
        return self.fresh_bones
    end

    function player:bone(index)
        return self.bones[index]
    end

    return player
end

local inside = make_player({
    name = "Inside",
    rank = 4,
    xp = 12,
    is_dead = false,
    is_teammate = false,
    is_visible = true,
    head_pos = { x = 100, y = 0, z = 0 },
    origin = { x = 100, y = 0, z = 0 },
    fresh_bones = true,
    bones = {
        [1] = { x = 100, y = 0, z = 0 },
        [2] = { x = 100, y = 0, z = 10 },
        [3] = { x = 100, y = 0, z = 20 },
    },
})

local outside = make_player({
    name = "Outside",
    rank = 7,
    xp = 21,
    is_dead = false,
    is_teammate = false,
    is_visible = true,
    head_pos = { x = 100, y = 20, z = 0 },
    origin = { x = 100, y = 20, z = 0 },
    fresh_bones = true,
    bones = {
        [1] = { x = 100, y = 20, z = 0 },
        [2] = { x = 100, y = 20, z = 10 },
        [3] = { x = 100, y = 20, z = 20 },
    },
})

local fallback = make_player({
    name = "Fallback",
    rank = 8,
    xp = 30,
    is_dead = false,
    is_teammate = false,
    is_visible = true,
    head_pos = { x = 0, y = 0, z = 0 },
    origin = { x = 100, y = 0, z = -45 },
    fresh_bones = false,
    bones = {},
})

local offscreen = make_player({
    name = "Offscreen",
    rank = 9,
    xp = 31,
    is_dead = false,
    is_teammate = false,
    is_visible = false,
    head_pos = { x = 100, y = 0, z = 0, offscreen = true },
    origin = { x = 100, y = 0, z = 0 },
    fresh_bones = false,
    bones = {},
})

local teammate = make_player({
    name = "Teammate",
    rank = 10,
    xp = 32,
    is_dead = false,
    is_teammate = true,
    is_visible = true,
    head_pos = { x = 100, y = 0, z = 0 },
    origin = { x = 100, y = 0, z = 0 },
    fresh_bones = true,
    bones = inside.bones,
})

local dead = make_player({
    name = "Dead",
    rank = 11,
    xp = 33,
    is_dead = true,
    is_teammate = false,
    is_visible = true,
    head_pos = { x = 100, y = 0, z = 0 },
    origin = { x = 100, y = 0, z = 0 },
    fresh_bones = true,
    bones = inside.bones,
})

game = {
    BONE_LINKS = { { 1, 2 }, { 2, 3 } },
    localplayer = {
        is_dead = false,
        is_zooming = true,
        target_zoom_fov = 10.0,
        camera_origin = { x = 0, y = 0, z = 0 },
        origin = { x = 0, y = 0, z = 0 },
        view_angle = { x = 0, y = 0 },
    },
    entities = {
        players = { inside, outside, teammate, dead },
    },
}

_SCRIPT_PATH = "scripts/finished/esp/esp__ads_fov_declutter__v01.lua"

dofile(_SCRIPT_PATH)

assert(type(event_handlers.frame_update) == "function")
assert(esp_callbacks.declutter_name ~= nil)
assert(esp_callbacks.declutter_rank ~= nil)
assert(esp_callbacks.declutter_level ~= nil)
assert(#logs == 1)

local function render(id, player)
    return esp_callbacks[id].callback(player, {})
end

-- 默认 ADS FOV 为 10 度：正前方目标在锥内，偏移约 11.3 度的目标在锥外。
assert(render("declutter_name", inside) == nil)
assert(render("declutter_rank", inside) == nil)
assert(render("declutter_level", inside) == nil)
assert(render("declutter_name", outside) == "Outside")
assert(render("declutter_rank", outside) == "7")
assert(render("declutter_level", outside) == "Lv.21")

-- 非 ADS 时不隐藏任何文字。
game.localplayer.is_zooming = false
assert(render("declutter_name", inside) == "Inside")
assert(render("declutter_rank", inside) == "4")
assert(render("declutter_level", inside) == "Lv.12")
game.localplayer.is_zooming = true

-- 三种文字开关相互独立。
controls.hide_name:set(false)
assert(render("declutter_name", inside) == "Inside")
assert(render("declutter_rank", inside) == nil)
assert(render("declutter_level", inside) == nil)
controls.hide_name:set(true)

-- 总开关关闭时保留所有文字。
controls.enable_declutter:set(false)
assert(render("declutter_name", inside) == "Inside")
assert(render("declutter_rank", inside) == "4")
assert(render("declutter_level", inside) == "Lv.12")
controls.enable_declutter:set(true)

-- 头部位置缺失时使用 origin + 45 的后备位置。
assert(render("declutter_name", fallback) == nil)

-- 投影失败或 ADS FOV 不可用时不主动隐藏。
assert(render("declutter_name", offscreen) == "Offscreen")
game.localplayer.target_zoom_fov = 0.0
assert(render("declutter_name", inside) == "Inside")
game.localplayer.target_zoom_fov = 10.0

-- 队友和死亡玩家不由这些敌方文字元素显示。
assert(render("declutter_name", teammate) == nil)
assert(render("declutter_name", dead) == nil)

-- frame_update 中绘制符合条件的两个敌人，每个敌人有两条骨骼连接。
event_handlers.frame_update()
assert(#draw_lines == 4)
for _, line in ipairs(draw_lines) do
    assert(line.thickness == 1.5)
    assert(line.color.r == 1.0 and line.color.g == 1.0 and line.color.b == 1.0)
    assert(line.color.a == 0.8)
end

-- 关闭骨骼开关后不再追加绘制。
controls.draw_skeleton:set(false)
event_handlers.frame_update()
assert(#draw_lines == 4)

print("esp__ads_fov_declutter__v01_test: ok")
