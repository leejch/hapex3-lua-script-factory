-- 验证屏内版本的 800ms 持续瞄准延迟、立即隐藏和屏外过滤。

local current_time = 0.0
local event_handlers = {}
local esp_callbacks = {}
local draw_lines = {}
local logs = {}

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

_SCRIPT_PATH = "scripts/finished/draw/draw__enemy_aim_warning__screen_only__v01.lua"

dofile(_SCRIPT_PATH)

assert(type(event_handlers.frame_update) == "function")
assert(esp_callbacks.enemy_aim_warning_screen_only ~= nil)
assert(#logs == 1 and logs[1].level == "success")
assert(esp_callbacks.enemy_aim_warning_screen_only.opts.kind == "free")

event_handlers.frame_update()
assert(#draw_lines == 0)

local callback = esp_callbacks.enemy_aim_warning_screen_only.callback
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

-- 800ms 内不显示，超过延迟后显示屏内身体中心红线。
visible_aim_callback(2, -90)
assert(#draw_lines == 0)
current_time = 0.81
visible_aim_callback(2, -90)
assert(#draw_lines == 1)
assert(draw_lines[1].x1 == 960 and draw_lines[1].y1 == 540)
assert(draw_lines[1].x2 == 950 and draw_lines[1].y2 == 500)
assert(draw_lines[1].color.r == 255 and draw_lines[1].color.g == 0 and draw_lines[1].color.b == 0)
assert(draw_lines[1].thickness == 2.0)

-- 停止瞄准立即隐藏，重新瞄准重新计时。
current_time = 0.82
visible_aim_callback(2, 0)
assert(#draw_lines == 1)
current_time = 0.83
visible_aim_callback(2, -90)
assert(#draw_lines == 1)
current_time = 1.64
visible_aim_callback(2, -90)
assert(#draw_lines == 2)

-- 目标离开视野时不绘制，并清除之前的连续瞄准计时。
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

-- 返回视野后仍需重新累计 800ms。
game.entities.players[2].in_screen = true
current_time = 2.01
visible_aim_callback(8, -90)
assert(#draw_lines == 2)
current_time = 2.82
visible_aim_callback(8, -90)
assert(#draw_lines == 3)

print("draw__enemy_aim_warning__screen_only__v01_test: ok")
