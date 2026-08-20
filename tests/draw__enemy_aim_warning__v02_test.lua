-- 验证全范围版本的 800ms 持续瞄准延迟、立即隐藏、亮粉色屏内线和屏外文字告警样式。

local current_time = 0.0
local event_handlers = {}
local esp_callbacks = {}
local draw_lines = {}
local draw_texts = {}
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
    measure = function()
        return 100, 10
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
    text = function(x, y, color, value, opts)
        draw_texts[#draw_texts + 1] = {
            x = x,
            y = y,
            color = color,
            text = value,
            opts = opts,
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

_SCRIPT_PATH = "scripts/finished/draw/draw__enemy_aim_warning__v02.lua"

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

-- 持续瞄准未达到 800ms 时不绘制，达到后绘制身体中心亮粉色线。
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
assert(draw_lines[1].color.r == 255 and draw_lines[1].color.g == 0 and draw_lines[1].color.b == 255)
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

-- 屏外正后方敌人通过 frame_update 处理，延迟后显示指定位置的文字告警。
game.entities.players[2] = {
    index = 8,
    origin = { x = -10, y = 0, z = 0 },
    yaw = 0,
    in_screen = false,
    can_draw = true,
    team_num = 7,
    name = "EnemyRear",
    grade = 42,
    kills = 3,
}
current_time = 2.0
event_handlers.frame_update()
assert(#draw_lines == 2)
assert(#draw_texts == 0)
current_time = 2.81
event_handlers.frame_update()
assert(#draw_lines == 2)
assert(#draw_texts == 1)
assert(draw_texts[1].x == 672 and draw_texts[1].y == 216)
assert(draw_texts[1].color.r == 255 and draw_texts[1].color.g == 255 and draw_texts[1].color.b == 153)
assert(draw_texts[1].opts.size == 12.0)
assert(draw_texts[1].opts.outline.r == 0 and draw_texts[1].opts.outline.g == 0 and draw_texts[1].opts.outline.b == 0)
assert(draw_texts[1].text == "背后被人瞄准！队伍: 7，玩家: EnemyRear，等级: 42，击杀: 3")

-- 屏外敌人短暂停止瞄准时保持文字，重新瞄准后继续保持显示。
game.entities.players[2].yaw = 90
current_time = 2.82
event_handlers.frame_update()
assert(#draw_lines == 2)
assert(#draw_texts == 2)
game.entities.players[2].yaw = 0
current_time = 2.83
event_handlers.frame_update()
assert(#draw_lines == 2)
assert(#draw_texts == 3)
current_time = 3.64
event_handlers.frame_update()
assert(#draw_lines == 2)
assert(#draw_texts == 4)

-- 屏外告警在短暂失去瞄准时继续显示，连续 2 秒未被瞄准后才隐藏。
game.entities.players[2].yaw = 90
current_time = 3.65
event_handlers.frame_update()
assert(#draw_texts == 5)
current_time = 5.64
event_handlers.frame_update()
assert(#draw_texts == 6)
current_time = 5.65
event_handlers.frame_update()
assert(#draw_texts == 6)

-- 告警隐藏后重新被连续瞄准 800ms，重新显示并开始新的 2 秒保持计时。
game.entities.players[2].yaw = 0
current_time = 5.66
event_handlers.frame_update()
assert(#draw_texts == 6)
current_time = 6.47
event_handlers.frame_update()
assert(#draw_texts == 7)

-- 屏外右侧敌人也使用文字告警，不再绘制屏外亮粉色线。
game.entities.players[2] = {
    index = 9,
    origin = { x = 0, y = 10, z = 0 },
    yaw = -90,
    in_screen = false,
    can_draw = true,
    team_num = 8,
    name = "EnemyRight",
    grade = 43,
    kills = 4,
}
current_time = 4.0
event_handlers.frame_update()
current_time = 4.81
event_handlers.frame_update()
assert(#draw_lines == 2)
assert(#draw_texts == 8)
assert(draw_texts[8].x == 672 and draw_texts[8].y == 216)
assert(draw_texts[8].text == "背后被人瞄准！队伍: 8，玩家: EnemyRight，等级: 43，击杀: 4")

print("draw__enemy_aim_warning__v02_test: ok")
