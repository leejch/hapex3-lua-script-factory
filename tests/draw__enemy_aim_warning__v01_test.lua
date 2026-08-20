-- 验证正式红线逻辑，并覆盖身体中心、队友/自身过滤和备用投影路径。

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
    warn = function(message)
        logs[#logs + 1] = { level = "warn", message = message }
    end,
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
                distance = 10,
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

callback({
    index = 2,
    origin = { x = 0, y = 10, z = 0 },
    head_pos = { x = 0, y = 10, z = 100 },
    yaw = -90,
    in_screen = true,
    can_draw = true,
}, { box = box })

assert(#draw_lines == 1)
assert(draw_lines[1].x1 == 960 and draw_lines[1].y1 == 540)
assert(draw_lines[1].x2 == 950 and draw_lines[1].y2 == 500)
assert(draw_lines[1].color.r == 255 and draw_lines[1].color.g == 0 and draw_lines[1].color.b == 0)
assert(draw_lines[1].thickness == 2.0)

callback({
    index = 3,
    origin = { x = 0, y = 10, z = 0 },
    yaw = 30,
    view_angle = { pitch = 0, yaw = 30 },
    in_screen = true,
    can_draw = true,
}, { box = box })
assert(#draw_lines == 1)

callback({
    index = 4,
    origin = { x = 0, y = 10, z = 0 },
    yaw = 0,
    view_angle = { pitch = 0, yaw = 0 },
    is_teammate = true,
    in_screen = true,
    can_draw = true,
}, { box = box })
assert(#draw_lines == 1)

callback({
    index = 5,
    origin = { x = 0, y = 10, z = 0 },
    yaw = 30,
    in_screen = true,
    can_draw = true,
}, { box = box })
assert(#draw_lines == 1)

-- ctx.box 无效时，备用路径使用脚底与头部投影的中点。
callback({
    index = 6,
    origin = { x = 0, y = 10, z = 0 },
    head_pos = { x = 0, y = 10, z = 100 },
    yaw = -90,
    in_screen = true,
    can_draw = true,
}, { box = { min = { x = 0, y = 0 }, max = { x = 0, y = 0 } } })
assert(#draw_lines == 2)
assert(draw_lines[2].x2 == 1000 and draw_lines[2].y2 == 650)
assert(draw_lines[2].color.r == 255 and draw_lines[2].color.g == 0 and draw_lines[2].color.b == 0)

-- head_pos 缺失时使用脚底上移 36 个游戏单位的中心近似。
callback({
    index = 7,
    origin = { x = 0, y = 10, z = 0 },
    yaw = -90,
    in_screen = true,
    can_draw = true,
}, { box = { min = { x = 0, y = 0 }, max = { x = 0, y = 0 } } })
assert(#draw_lines == 3)
assert(draw_lines[3].x2 == 1000 and draw_lines[3].y2 == 636)
assert(draw_lines[3].color.r == 255 and draw_lines[3].color.g == 0 and draw_lines[3].color.b == 0)

-- 屏幕外正后方敌人：frame_update 仍应绘制到屏幕底边。
game.entities.players[2] = {
    index = 8,
    origin = { x = -10, y = 0, z = 0 },
    yaw = 0,
    in_screen = false,
    can_draw = true,
}
event_handlers.frame_update()
assert(#draw_lines == 4)
assert(draw_lines[4].x1 == 960 and draw_lines[4].y1 == 540)
assert_near(draw_lines[4].x2, 960)
assert_near(draw_lines[4].y2, 1080)
assert(draw_lines[4].color.r == 255 and draw_lines[4].color.g == 0 and draw_lines[4].color.b == 0)
assert(draw_lines[4].thickness == 2.0)

-- 屏幕外右侧敌人：frame_update 应将方向线裁剪到屏幕右边。
game.entities.players[2] = {
    index = 9,
    origin = { x = 0, y = 10, z = 0 },
    yaw = -90,
    in_screen = false,
    can_draw = true,
}
event_handlers.frame_update()
assert(#draw_lines == 5)
assert(draw_lines[5].x1 == 960 and draw_lines[5].y1 == 540)
assert_near(draw_lines[5].x2, 1920)
assert_near(draw_lines[5].y2, 540)
assert(draw_lines[5].color.r == 255 and draw_lines[5].color.g == 0 and draw_lines[5].color.b == 0)
assert(draw_lines[5].thickness == 2.0)

print("draw__enemy_aim_warning__v01_test: ok")
