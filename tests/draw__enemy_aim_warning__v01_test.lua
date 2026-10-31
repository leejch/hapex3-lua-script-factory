-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 验证全范围版本的 800ms 持续瞄准延迟、立即隐藏、屏内中心线和屏外边缘线。

local current_time = 0.0
local event_handlers = {}
local esp_callbacks = {}
local draw_lines = {}
local logs = {}

local function assert_near(actual, expected)
    assert(math.abs(actual - expected) < 1e-6)
end

event = {
    on = function(name, handler)
        event_handlers[name] = handler
    end,
}

time = {
    now = function()
        return current_time
    end,
}

draw = {
    u8 = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a }
    end,
    screen = function()
        return 1920, 1080
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
    return 1000, 600 + world_pos.z, true
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
        logs[#logs + 1] = { level = "success", message = message }
    end,
}

game = {
    localplayer = {
        index = 1,
        camera_origin = { x = 0, y = 0, z = 0 },
        view_angle = { pitch = 0, yaw = 0 },
    },
    entities = {
        players = {
            {
                index = 2,
                in_screen = true,
                can_draw = true,
            },
        },
    },
}

_SCRIPT_PATH = "scripts/finished/draw/draw__enemy_aim_warning__v01.lua"

dofile(_SCRIPT_PATH)

assert(type(event_handlers.frame_update) == "function")
assert(esp_callbacks.enemy_aim_warning ~= nil)
assert(#logs == 1 and logs[1].level == "success")
assert(esp_callbacks.enemy_aim_warning.opts.kind == "free")
assert(esp_callbacks.enemy_aim_warning.element.enableds[1])
assert(esp_callbacks.enemy_aim_warning.element.enableds[2])
assert(esp_callbacks.enemy_aim_warning.element.enableds[3])
assert(esp_callbacks.enemy_aim_warning.element.enableds[4])

event_handlers.frame_update()
assert(#draw_lines == 0)

local callback = esp_callbacks.enemy_aim_warning.callback
local box = {
    min = { x = 900, y = 400 },
    max = { x = 1000, y = 600 },
}

local function visible_aim_callback(index, yaw)
    callback({
        index = index,
        origin = { x = 0, y = 10, z = 0 },
        head_pos = { x = 0, y = 10, z = 100 },
        yaw = yaw,
        in_screen = true,
        can_draw = true,
    }, { box = box })
end

-- 持续瞄准未达到 800ms 时不绘制，达到后绘制身体中心红线。
visible_aim_callback(2, -90)
assert(#draw_lines == 0)
current_time = 0.79
visible_aim_callback(2, -90)
assert(#draw_lines == 0)
current_time = 0.81
visible_aim_callback(2, -90)
assert(#draw_lines == 1)
assert(draw_lines[1].x1 == 960 and draw_lines[1].y1 == 540)
assert(draw_lines[1].x2 == 950 and draw_lines[1].y2 == 500)
assert(draw_lines[1].color.r == 255 and draw_lines[1].color.g == 0 and draw_lines[1].color.b == 0)
assert(draw_lines[1].thickness == 2.0)

-- 一旦不再瞄准，当前帧立即停止绘制；重新瞄准需要重新累计 800ms。
current_time = 0.82
visible_aim_callback(2, 0)
assert(#draw_lines == 1)
current_time = 0.83
visible_aim_callback(2, -90)
assert(#draw_lines == 1)
current_time = 1.64
visible_aim_callback(2, -90)
assert(#draw_lines == 2)

-- 屏内过滤仍然生效。
visible_aim_callback(3, 30)
assert(#draw_lines == 2)
callback({
    index = 4,
    origin = { x = 0, y = 10, z = 0 },
    yaw = -90,
    is_teammate = true,
    in_screen = true,
    can_draw = true,
}, { box = box })
assert(#draw_lines == 2)

-- 屏外正后方敌人通过 frame_update 处理，延迟后指向屏幕底边。
game.entities.players[2] = {
    index = 8,
    origin = { x = -10, y = 0, z = 0 },
    yaw = 0,
    in_screen = false,
    can_draw = true,
}
current_time = 2.0
event_handlers.frame_update()
assert(#draw_lines == 2)
current_time = 2.81
event_handlers.frame_update()
assert(#draw_lines == 3)
assert(draw_lines[3].x1 == 960 and draw_lines[3].y1 == 540)
assert_near(draw_lines[3].x2, 960)
assert_near(draw_lines[3].y2, 1080)

-- 屏外敌人停止瞄准后立即隐藏，重新瞄准不会继承旧计时。
game.entities.players[2].yaw = 90
current_time = 2.82
event_handlers.frame_update()
assert(#draw_lines == 3)
game.entities.players[2].yaw = 0
current_time = 2.83
event_handlers.frame_update()
assert(#draw_lines == 3)
current_time = 3.64
event_handlers.frame_update()
assert(#draw_lines == 4)

-- 屏外右侧敌人最终指向屏幕右边。
game.entities.players[2] = {
    index = 9,
    origin = { x = 0, y = 10, z = 0 },
    yaw = -90,
    in_screen = false,
    can_draw = true,
}
current_time = 4.0
event_handlers.frame_update()
current_time = 4.81
event_handlers.frame_update()
assert(#draw_lines == 5)
assert(draw_lines[5].x1 == 960 and draw_lines[5].y1 == 540)
assert_near(draw_lines[5].x2, 1920)
assert_near(draw_lines[5].y2, 540)

print("draw__enemy_aim_warning__v01_test: ok")
