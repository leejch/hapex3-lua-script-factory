-- 在屏幕居中偏上 25% 高度位置绘制最近敌人方向预警。
-- 使用 game.entities.players 查找最近的非队友玩家，并读取距离与昵称。
-- 使用 math.CalcAngle 与本地视角计算相对方位，提供八向箭头提示。
-- 使用 draw.text 在每个 frame_update 中绘制箭头、距离和玩家昵称。

local ANCHOR_Y_RATIO = 0.25
local ARROW_FONT_SIZE = 34
local INFO_FONT_SIZE = 16
local LINE_GAP = 4
local ARROW_COLOR = draw.rgba(1.0, 0.82, 0.18, 1.0)
local DISTANCE_COLOR = draw.rgba(1.0, 1.0, 1.0, 1.0)
local NAME_COLOR = draw.rgba(0.78, 0.9, 1.0, 1.0)
local OUTLINE_COLOR = draw.rgba(0.0, 0.0, 0.0, 0.9)

local ARROWS = {
    "↑", -- 前方
    "↖", -- 左前
    "←", -- 左侧
    "↙", -- 左后
    "↓", -- 后方
    "↘", -- 右后
    "→", -- 右侧
    "↗", -- 右前
}

local arrow_font = draw.font("logo") or draw.font("default")
local info_font = draw.font("esp") or draw.font("default")

local function nearest_enemy()
    local nearest = nil
    local nearest_distance = nil

    for _, player in pairs(game.entities.players) do
        if player.origin and not player.is_teammate and not player.is_dead and not player.is_npc then
            local distance = player.distance
            if distance and distance > 0 and (not nearest_distance or distance < nearest_distance) then
                nearest = player
                nearest_distance = distance
            end
        end
    end

    return nearest, nearest_distance
end

local function arrow_for_enemy(enemy)
    local local_player = game.localplayer
    if not (local_player and local_player.camera_origin and local_player.view_angle and enemy.head_pos) then
        return nil
    end

    local _, enemy_yaw = math.CalcAngle(local_player.camera_origin, enemy.head_pos)
    local relative_yaw = math.AngleNormalize(enemy_yaw - local_player.view_angle.y)

    -- HApex3.0 的屏幕提示以“玩家当前朝向”为上方；正相对角按左侧方向映射到八向箭头。
    if relative_yaw >= 157.5 or relative_yaw < -157.5 then
        return ARROWS[5]
    elseif relative_yaw >= 112.5 then
        return ARROWS[4]
    elseif relative_yaw >= 67.5 then
        return ARROWS[3]
    elseif relative_yaw >= 22.5 then
        return ARROWS[2]
    elseif relative_yaw >= -22.5 then
        return ARROWS[1]
    elseif relative_yaw >= -67.5 then
        return ARROWS[8]
    elseif relative_yaw >= -112.5 then
        return ARROWS[7]
    else
        return ARROWS[6]
    end
end

local function draw_centered_text(center_x, top_y, color, text, opts)
    local width, height = draw.measure(text, opts)
    draw.text(center_x - width / 2, top_y, color, text, opts)
    return height
end

event.on("frame_update", function(e)
    local enemy, distance = nearest_enemy()
    if not enemy then return end

    local arrow = arrow_for_enemy(enemy)
    if not arrow then return end

    local screen_w, screen_h = draw.screen()
    local center_x = screen_w / 2
    local top_y = screen_h * ANCHOR_Y_RATIO

    local arrow_opts = { font = arrow_font, size = ARROW_FONT_SIZE, outline = OUTLINE_COLOR }
    local info_opts = { font = info_font, size = INFO_FONT_SIZE, outline = OUTLINE_COLOR }

    local arrow_h = draw_centered_text(center_x, top_y, ARROW_COLOR, arrow, arrow_opts)
    local distance_text = string.format("%.0f m", distance)
    local distance_h = draw_centered_text(center_x, top_y + arrow_h + LINE_GAP, DISTANCE_COLOR, distance_text, info_opts)

    local name = enemy.name
    if not name or name == "" then
        name = "Unknown"
    end

    draw_centered_text(center_x, top_y + arrow_h + distance_h + LINE_GAP * 2, NAME_COLOR, name, info_opts)
end)

log.success("Nearest enemy direction warning script loaded")
