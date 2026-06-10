-- 在屏幕中央绘制最近敌人的方向警示圆环。
-- 使用 game.entities.players 找到最近的非队友存活目标，并用 math.WorldToScreen / math.CalcAngle 计算方向。
-- 使用 draw.circle 绘制空心环轮廓，使用 draw.polyline 绘制仅占 5% 圆心角的实心条带。
-- 所有 draw 调用都放在 render_post 中逐帧提交，避免前景绘制列表清空导致不可见。

local RING_RADIUS = 74
local RING_THICKNESS = 10
local ARC_PORTION = 0.05
local ARC_SEGMENTS = 8
local MAX_DISTANCE_METERS = 300

local COLOR_RING = draw.rgba(1.0, 1.0, 1.0, 0.22)
local COLOR_ALERT = draw.rgba(1.0, 0.24, 0.10, 0.92)
local COLOR_ALERT_VISIBLE = draw.rgba(1.0, 0.78, 0.18, 0.96)
local COLOR_EDGE = draw.rgba(0.0, 0.0, 0.0, 0.45)

local PI = math.pi
local TWO_PI = PI * 2.0
local HALF_PI = PI * 0.5
local ARC_RADIANS = TWO_PI * ARC_PORTION

local function atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end

    return math.atan(y, x)
end

local function player_is_valid_enemy(player)
    if player.is_teammate then return false end
    if player.is_dead or player.is_down then return false end
    if not player.origin then return false end
    if (player.distance or 999999) > MAX_DISTANCE_METERS then return false end
    return true
end

local function nearest_enemy()
    local best = nil
    local best_distance = 999999

    -- 玩家实体是 userdata 支撑的表，必须用 pairs；这样不会被 # 返回 0 的情况误导。
    for _, player in pairs(game.entities.players) do
        if player_is_valid_enemy(player) then
            local distance = player.distance or 999999
            if distance < best_distance then
                best = player
                best_distance = distance
            end
        end
    end

    return best
end

local function direction_angle_from_screen(enemy, center_x, center_y)
    local target = enemy.head_pos or enemy.origin
    local sx, sy, ok = math.WorldToScreen(target)
    if ok then
        local dx = sx - center_x
        local dy = sy - center_y
        if (dx * dx + dy * dy) > 4.0 then
            return atan2(dy, dx)
        end
    end

    local local_player = game.localplayer
    if not (local_player and local_player.camera_origin and local_player.view_angle) then
        return nil
    end

    local _, target_yaw = math.CalcAngle(local_player.camera_origin, target)
    local yaw_delta = math.AngleNormalize(target_yaw - local_player.view_angle.y)

    -- 目标正前方时把条带放在 12 点方向；左右和背后按水平相对方位环绕。
    return (yaw_delta * PI / 180.0) - HALF_PI
end

local function annular_sector_points(center_x, center_y, angle)
    local outer_radius = RING_RADIUS + RING_THICKNESS * 0.5
    local inner_radius = RING_RADIUS - RING_THICKNESS * 0.5
    local start_angle = angle - ARC_RADIANS * 0.5
    local points = {}

    for i = 0, ARC_SEGMENTS do
        local t = i / ARC_SEGMENTS
        local a = start_angle + ARC_RADIANS * t
        points[#points + 1] = { center_x + math.cos(a) * outer_radius, center_y + math.sin(a) * outer_radius }
    end

    for i = ARC_SEGMENTS, 0, -1 do
        local t = i / ARC_SEGMENTS
        local a = start_angle + ARC_RADIANS * t
        points[#points + 1] = { center_x + math.cos(a) * inner_radius, center_y + math.sin(a) * inner_radius }
    end

    return points
end

local function draw_warning_ring(center_x, center_y, enemy, angle)
    draw.circle(center_x, center_y, RING_RADIUS + RING_THICKNESS * 0.5, COLOR_RING, {
        segments = 96,
        thickness = 1.5,
    })
    draw.circle(center_x, center_y, RING_RADIUS - RING_THICKNESS * 0.5, COLOR_RING, {
        segments = 96,
        thickness = 1.5,
    })

    local sector = annular_sector_points(center_x, center_y, angle)
    local color = enemy.is_visible and COLOR_ALERT_VISIBLE or COLOR_ALERT
    draw.polyline(sector, color, { filled = true })
    draw.polyline(sector, COLOR_EDGE, { closed = true, thickness = 1.0 })
end

event.on("render_post", function(e)
    local screen_w, screen_h = draw.screen()
    local center_x = screen_w * 0.5
    local center_y = screen_h * 0.5
    local enemy = nearest_enemy()

    if not enemy then return end

    local angle = direction_angle_from_screen(enemy, center_x, center_y)
    if not angle then return end

    draw_warning_ring(center_x, center_y, enemy, angle)
end)

log.success("Nearest enemy warning ring script loaded")
