-- 在屏幕左上方覆盖绘制小地图敌方箭头雷达。
-- 使用 game.localplayer 与 game.entities.players 读取本地和敌方位置、朝向、队伍。
-- 使用 draw.rect、draw.triangle、draw.line 在每个 frame_update 中绘制方形区域与缺口箭头。
-- 默认按 2560x1440 下 64,64 到 388,388 的游戏内小地图区域校准。
-- 小地图坐标不随本地视角旋转，敌方箭头宽 1.5 像素、长 3 像素并使用 enemy.yaw 旋转。

local tab = gui.tab("MinimapRadar")
local g_main = tab:group("main", "小地图敌方箭头", 0, 0, 420, 0)

local c_enable = g_main:checkbox("enable", "启用覆盖", true)
local c_auto_scale = g_main:checkbox("auto_scale", "按 2K 分辨率等比缩放", true)
local s_x = g_main:slider("x", "左上角 X", 0, 3840, 64):set_format("%d px")
local s_y = g_main:slider("y", "左上角 Y", 0, 2160, 64):set_format("%d px")
local s_size = g_main:slider("size", "方形边长", 120, 640, 324):set_format("%d px")
local s_radius = g_main:slider("radius_m", "小地图半径", 50, 450, 200):set_format("%d m")
local s_alpha = g_main:slider("alpha", "背景透明度", 20, 180, 64):set_format("%d")

g_main:button("reset", "重置 2K 默认位置", function()
    s_x:set(64)
    s_y:set(64)
    s_size:set(324)
    s_radius:set(200)
    gui.notify:success("小地图雷达已重置", 2.0)
end)

local REF_W = 2560.0
local REF_H = 1440.0
local UNITS_PER_METER = 39.37
local BORDER_COLOR = draw.u8(255, 255, 255, 170)
local GRID_COLOR = draw.u8(255, 255, 255, 34)
local LOCAL_COLOR = draw.u8(255, 255, 255, 230)

local TEAM_COLOR_CACHE = {}

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
    local cached = TEAM_COLOR_CACHE[team]
    if cached then return cached end

    -- 用队伍号生成稳定颜色，避免固定色盘在多队伍场景下循环撞色。
    local seed = (team * 1103515245 + 12345) % 2147483648
    local r = 70 + (seed % 170)
    seed = (seed * 1103515245 + 12345) % 2147483648
    local g = 70 + (seed % 170)
    seed = (seed * 1103515245 + 12345) % 2147483648
    local b = 70 + (seed % 170)

    cached = draw.u8(r, g, b, 235)
    TEAM_COLOR_CACHE[team] = cached
    return cached
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

local function world_to_minimap(delta, cx, cy, half, radius_m)
    local meters_x = delta.x / UNITS_PER_METER
    local meters_y = delta.y / UNITS_PER_METER

    local px = cx + (meters_x / radius_m) * half
    local py = cy - (meters_y / radius_m) * half

    return px, py
end

local function atan2_deg(y, x)
    if x > 0.0 then return math.atan(y / x) / 0.017453292519943295 end
    if x < 0.0 and y >= 0.0 then return (math.atan(y / x) / 0.017453292519943295) + 180.0 end
    if x < 0.0 and y < 0.0 then return (math.atan(y / x) / 0.017453292519943295) - 180.0 end
    if y > 0.0 then return 90.0 end
    if y < 0.0 then return -90.0 end
    return 0.0
end

local function player_facing_yaw(player)
    if player.yaw ~= nil then return player.yaw end

    local v = player.abs_velocity
    if v and v:length_2d() > 1.0 then
        -- yaw 是敌人视角朝向；缺失时只用移动方向兜底，避免箭头完全固定不动。
        return atan2_deg(v.y, v.x)
    end

    return 0.0
end

local function draw_open_arrow(cx, cy, yaw_deg, color, length, width)
    local a = deg_to_rad(yaw_deg or 0.0)
    local fx = math.cos(a)
    local fy = -math.sin(a)
    local rx = -fy
    local ry = fx

    local half_len = length * 0.5
    local half_width = width * 0.5
    local tip_x = cx + fx * half_len
    local tip_y = cy + fy * half_len
    local base_x = cx - fx * half_len
    local base_y = cy - fy * half_len
    local l_x = base_x - rx * half_width
    local l_y = base_y - ry * half_width
    local r_x = base_x + rx * half_width
    local r_y = base_y + ry * half_width

    -- 只画轮廓不填充，让 3px 小箭头保持中间缺口，同时仍能清楚体现朝向。
    draw.triangle(tip_x, tip_y, l_x, l_y, r_x, r_y, color, { filled = false, thickness = 1.0 })
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
    local arrow_length = 3.0
    local arrow_width = 1.5

    for _, enemy in pairs(game.entities.players) do
        if enemy and (not enemy.is_teammate) and (not enemy.is_dead) and enemy.origin then
            local delta = enemy.origin - lp.origin
            local dist_m = delta:length_2d() / UNITS_PER_METER
            if dist_m <= radius_m then
                local px, py = world_to_minimap(delta, cx, cy, half, radius_m)
                if px >= x1 and px <= x2 and py >= y1 and py <= y2 then
                    local yaw = player_facing_yaw(enemy)
                    local color = team_color(enemy.team_num)
                    draw_open_arrow(px, py, yaw, color, arrow_length, arrow_width)
                end
            end
        end
    end
end)

log.success("小地图敌方箭头脚本已加载")
