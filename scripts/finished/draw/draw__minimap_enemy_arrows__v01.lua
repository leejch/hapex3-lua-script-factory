-- 在屏幕左上方覆盖绘制小地图敌方箭头雷达。
-- 使用 game.localplayer 与 game.entities.players 读取本地和敌方位置、朝向、队伍。
-- 使用 draw.rect、draw.triangle、draw.line 在每个 frame_update 中绘制方形区域与缺口箭头。
-- 默认按 2560x1440 下 64,64 到 388,388 的游戏内小地图区域校准，并提供菜单参数微调。
-- 当前 Lua API 未暴露鼠标坐标，位置通过菜单 X/Y/大小滑块手动调整保存。

local tab = gui.tab("MinimapRadar")
local g_main = tab:group("main", "小地图敌方箭头", 0, 0, 420, 0)

local c_enable = g_main:checkbox("enable", "启用覆盖", true)
local c_auto_scale = g_main:checkbox("auto_scale", "按 2K 分辨率等比缩放", true)
local c_rotate = g_main:checkbox("rotate_with_view", "小地图随视角旋转", true)
local s_x = g_main:slider("x", "左上角 X", 0, 3840, 64):set_format("%d px")
local s_y = g_main:slider("y", "左上角 Y", 0, 2160, 64):set_format("%d px")
local s_size = g_main:slider("size", "方形边长", 120, 640, 324):set_format("%d px")
local s_radius = g_main:slider("radius_m", "小地图半径", 50, 450, 200):set_format("%d m")
local s_arrow = g_main:slider("arrow_size", "箭头大小", 6, 22, 11):set_format("%d px")
local s_alpha = g_main:slider("alpha", "背景透明度", 20, 180, 64):set_format("%d")

g_main:button("reset", "重置 2K 默认位置", function()
    s_x:set(64)
    s_y:set(64)
    s_size:set(324)
    s_radius:set(200)
    gui.notify:success("小地图雷达已重置", 2.0)
end)

g_main:tips("drag_note", "HApex3.0 Lua 当前没有鼠标坐标/按键读取接口；请用 X/Y/边长滑块对齐小地图。", "i", { 1.0, 0.85, 0.25, 1.0 })

local REF_W = 2560.0
local REF_H = 1440.0
local UNITS_PER_METER = 39.37
local BORDER_COLOR = draw.u8(255, 255, 255, 170)
local GRID_COLOR = draw.u8(255, 255, 255, 34)
local LOCAL_COLOR = draw.u8(255, 255, 255, 230)

local TEAM_PALETTE = {
    draw.u8(255, 86, 86, 235),
    draw.u8(86, 190, 255, 235),
    draw.u8(255, 205, 74, 235),
    draw.u8(175, 105, 255, 235),
    draw.u8(70, 230, 155, 235),
    draw.u8(255, 124, 210, 235),
    draw.u8(255, 150, 66, 235),
    draw.u8(120, 235, 235, 235),
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function deg_to_rad(deg)
    return deg * 0.017453292519943295
end

local function team_color(team_num)
    local team = team_num or 0
    local idx = (team % #TEAM_PALETTE) + 1
    return TEAM_PALETTE[idx]
end

local function scaled_rect()
    local sw, sh = draw.screen()
    local scale = 1.0
    if c_auto_scale:get() then
        local sx = sw / REF_W
        local sy = sh / REF_H
        scale = (sx < sy) and sx or sy
    end

    local x1 = (s_x:get() or 64) * scale
    local y1 = (s_y:get() or 64) * scale
    local size = (s_size:get() or 324) * scale
    return x1, y1, x1 + size, y1 + size, size, scale
end

local function world_to_minimap(delta, local_yaw, cx, cy, half, radius_m)
    local meters_x = delta.x / UNITS_PER_METER
    local meters_y = delta.y / UNITS_PER_METER

    local px, py
    if c_rotate:get() then
        local yaw = deg_to_rad(local_yaw or 0.0)
        local cos_y = math.cos(yaw)
        local sin_y = math.sin(yaw)
        local right_m = meters_x * -sin_y + meters_y * cos_y
        local forward_m = meters_x * cos_y + meters_y * sin_y
        px = cx + (right_m / radius_m) * half
        py = cy - (forward_m / radius_m) * half
    else
        px = cx + (meters_x / radius_m) * half
        py = cy - (meters_y / radius_m) * half
    end

    return px, py
end

local function draw_open_arrow(cx, cy, yaw_deg, color, size, cut_color)
    local a = deg_to_rad(yaw_deg or 0.0)
    local fx = math.sin(a)
    local fy = -math.cos(a)
    local rx = math.cos(a)
    local ry = math.sin(a)

    local tip_x = cx + fx * size
    local tip_y = cy + fy * size
    local base_x = cx - fx * size * 0.72
    local base_y = cy - fy * size * 0.72
    local wing = size * 0.68

    local l_x = base_x - rx * wing
    local l_y = base_y - ry * wing
    local r_x = base_x + rx * wing
    local r_y = base_y + ry * wing

    draw.triangle(tip_x, tip_y, l_x, l_y, r_x, r_y, color, { filled = true })

    -- 用内部小三角制造“缺口”，避免实心箭头在小地图上遮挡太多信息。
    local inner = size * 0.48
    local inner_tip_x = cx + fx * inner * 0.84
    local inner_tip_y = cy + fy * inner * 0.84
    local inner_base_x = cx - fx * inner * 0.52
    local inner_base_y = cy - fy * inner * 0.52
    local inner_wing = inner * 0.72
    draw.triangle(
        inner_tip_x,
        inner_tip_y,
        inner_base_x - rx * inner_wing,
        inner_base_y - ry * inner_wing,
        inner_base_x + rx * inner_wing,
        inner_base_y + ry * inner_wing,
        cut_color,
        { filled = true }
    )

    draw.triangle(tip_x, tip_y, l_x, l_y, r_x, r_y, color, { filled = false, thickness = 1.5 })
end

local function draw_minimap_frame(x1, y1, x2, y2, cx, cy, half)
    local alpha = clamp(s_alpha:get() or 64, 20, 180)
    local bg = draw.u8(8, 10, 14, alpha)

    draw.rect(x1, y1, x2, y2, bg, { filled = true })
    draw.rect(x1, y1, x2, y2, BORDER_COLOR, { filled = false, thickness = 1.5 })
    draw.line(cx, y1, cx, y2, GRID_COLOR, { thickness = 1.0 })
    draw.line(x1, cy, x2, cy, GRID_COLOR, { thickness = 1.0 })
    draw.circle(cx, cy, 3.0, LOCAL_COLOR, { filled = true, segments = 16 })
    return bg
end

event.on("frame_update", function(e)
    if not c_enable:get() then return end

    local lp = game.localplayer
    if not lp or lp.is_dead or not lp.origin then return end

    local x1, y1, x2, y2, size, scale = scaled_rect()
    local cx = (x1 + x2) * 0.5
    local cy = (y1 + y2) * 0.5
    local half = size * 0.5
    local bg = draw_minimap_frame(x1, y1, x2, y2, cx, cy, half)

    local radius_m = s_radius:get() or 200
    if radius_m < 1 then radius_m = 1 end
    local local_yaw = 0.0
    if lp.view_angle then local_yaw = lp.view_angle.y or 0.0 end
    local arrow_size = (s_arrow:get() or 11) * scale

    for _, enemy in pairs(game.entities.players) do
        if enemy and (not enemy.is_teammate) and (not enemy.is_dead) and enemy.origin then
            local delta = enemy.origin - lp.origin
            local dist_m = delta:length_2d() / UNITS_PER_METER
            if dist_m <= radius_m then
                local px, py = world_to_minimap(delta, local_yaw, cx, cy, half, radius_m)
                if px >= x1 and px <= x2 and py >= y1 and py <= y2 then
                    local yaw = enemy.yaw or 0.0
                    if c_rotate:get() then yaw = yaw - local_yaw end
                    local color = team_color(enemy.team_num)
                    draw_open_arrow(px, py, yaw, color, arrow_size, bg)
                end
            end
        end
    end
end)

log.success("小地图敌方箭头脚本已加载")
