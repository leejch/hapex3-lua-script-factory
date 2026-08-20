-- 判断敌人的水平 yaw 是否在 5 度内指向当前玩家，并绘制一条 2px 亮粉色线。
-- 使用 game.localplayer、game.entities.players、math.CalcAngle、math.WorldToScreen、esp.add 和 draw.*。
-- 屏幕内保持身体中心亮粉色线；屏幕外改为在指定位置显示一行文字告警。
-- 只保留正式运行逻辑，不包含候选算法、诊断探针或临时测试绘制。

local AIM_CONE_DEGREES = 5.0
local AIM_WARNING_DELAY_SECONDS = 0.8
local OFFSCREEN_WARNING_X_RATIO = 0.35
local OFFSCREEN_WARNING_Y_RATIO = 0.3
local OFFSCREEN_WARNING_LINE_HEIGHT = 22.0
local OFFSCREEN_WARNING_TEXT_SCALE = 1.2
local LINE_THICKNESS = 2.0
local BRIGHT_PINK = draw.u8(255, 0, 255, 255)
local LIGHT_YELLOW = draw.u8(255, 255, 153, 255)
local BLACK_OUTLINE = draw.u8(0, 0, 0, 255)

local local_position = {
    x = nil,
    y = nil,
    z = nil,
}
local local_index = -1
local aim_started_at = {}

local function is_number(value)
    return type(value) == "number" and value == value and value > -1e6 and value < 1e6
end

local function read_member(value, key)
    if value == nil then return nil end

    local ok, result = pcall(function()
        return value[key]
    end)
    if ok then return result end
    return nil
end

local function read_vec2(value)
    if value == nil then return nil end

    local x = read_member(value, "x")
    local y = read_member(value, "y")
    if not (is_number(x) and is_number(y)) then
        -- 某些 Vec2 包装使用数组下标，同时兼容两种字段形式。
        x = read_member(value, 1)
        y = read_member(value, 2)
    end
    if not (is_number(x) and is_number(y)) then return nil end
    return x, y
end

local function read_vec3(value)
    if value == nil then return nil end

    local x = read_member(value, "x")
    local y = read_member(value, "y")
    local z = read_member(value, "z")
    if not (is_number(x) and is_number(y) and is_number(z)) then return nil end
    return x, y, z
end

local function read_player_position(player)
    local camera_origin = read_member(player, "camera_origin")
    local x, y, z = read_vec3(camera_origin)
    if x ~= nil then return x, y, z end

    return read_vec3(read_member(player, "origin"))
end

local function angle_close(first, second)
    if not (is_number(first) and is_number(second)) then return false end

    local error = math.AngleNormalize(first - second)
    return is_number(error) and math.abs(error) <= AIM_CONE_DEGREES
end

local function clear_aim_streak(enemy)
    local index = read_member(enemy, "index")
    if is_number(index) then aim_started_at[index] = nil end
end

local function warning_delay_elapsed(enemy, is_aimed)
    local index = read_member(enemy, "index")
    if not is_number(index) then return false end

    if not is_aimed then
        aim_started_at[index] = nil
        return false
    end

    local now = time.now()
    if not is_number(now) then return false end

    local started_at = aim_started_at[index]
    if started_at == nil then
        aim_started_at[index] = now
        return AIM_WARNING_DELAY_SECONDS <= 0.0
    end

    return now - started_at >= AIM_WARNING_DELAY_SECONDS
end

local function get_local_position()
    local_position.x = nil
    local_position.y = nil
    local_position.z = nil
    local_index = -1

    local player = game.localplayer
    if player == nil then return false end

    local x, y, z = read_player_position(player)
    if x == nil then return false end

    local_position.x = x
    local_position.y = y
    local_position.z = z

    local index = read_member(player, "index")
    local_index = is_number(index) and index or -1
    return true
end

local function is_being_aimed_at(enemy, ox, oy, oz)
    local dx = local_position.x - ox
    local dy = local_position.y - oy
    local dz = local_position.z - oz
    if dx * dx + dy * dy + dz * dz <= 1e-8 then return false end

    -- 当前运行时验证有效的是 PlayerEntity.yaw 的直接水平解释；垂直角度不参与判断。
    local _, target_horizontal_yaw = math.CalcAngle(
        math.Vec3(ox, oy, oz),
        math.Vec3(local_position.x, local_position.y, local_position.z)
    )
    return angle_close(target_horizontal_yaw, read_member(enemy, "yaw"))
end

local function read_screen_box(ctx)
    local box = read_member(ctx, "box")
    if box == nil then return nil end

    local min_point = read_member(box, "min") or read_member(box, 1)
    local max_point = read_member(box, "max") or read_member(box, 2)
    local min_x, min_y = read_vec2(min_point)
    local max_x, max_y = read_vec2(max_point)
    if min_x == nil or max_x == nil then return nil end

    if max_x <= min_x or max_y <= min_y then return nil end
    return min_x, min_y, max_x, max_y
end

local function draw_screen_line(enemy_x, enemy_y)
    if not (is_number(enemy_x) and is_number(enemy_y)) then return false end

    local screen_width, screen_height = draw.screen()
    if not (is_number(screen_width) and is_number(screen_height)) then return false end
    if enemy_x < -screen_width or enemy_x > screen_width * 2
        or enemy_y < -screen_height or enemy_y > screen_height * 2 then
        return false
    end

    draw.line(
        screen_width * 0.5,
        screen_height * 0.5,
        enemy_x,
        enemy_y,
        BRIGHT_PINK,
        { thickness = LINE_THICKNESS }
    )
    return true
end

local function draw_box_center_line(ctx)
    local min_x, min_y, max_x, max_y = read_screen_box(ctx)
    if min_x == nil then return false end

    return draw_screen_line(
        (min_x + max_x) * 0.5,
        (min_y + max_y) * 0.5
    )
end

local function project_world_point(point)
    local x, y, z = read_vec3(point)
    if x == nil then return nil end

    local success, screen_x, screen_y, visible = pcall(function()
        return math.WorldToScreen(math.Vec3(x, y, z))
    end)
    if not success or not visible or not (is_number(screen_x) and is_number(screen_y)) then
        return nil
    end
    return screen_x, screen_y
end

local function draw_projected_body_center(enemy, ox, oy, oz)
    -- ctx.box 不可用时，用脚底和头部两个世界点的屏幕中点作为备用中心。
    local foot_x, foot_y = project_world_point({ x = ox, y = oy, z = oz })
    local head_position = read_member(enemy, "head_pos")
    local head_world_x, head_world_y, head_world_z = read_vec3(head_position)
    local head_x, head_y = project_world_point(head_position)
    local has_distinct_head = is_number(head_x) and is_number(head_y)
        and is_number(head_world_x) and is_number(head_world_y) and is_number(head_world_z)
        and (head_world_x - ox) * (head_world_x - ox)
            + (head_world_y - oy) * (head_world_y - oy)
            + (head_world_z - oz) * (head_world_z - oz) > 1e-8

    if is_number(foot_x) and is_number(foot_y) and has_distinct_head then
        return draw_screen_line(
            (foot_x + head_x) * 0.5,
            (foot_y + head_y) * 0.5
        )
    end

    -- head_pos 缺失或脚底不在屏幕内时，用约 72 游戏单位高度的中点估算身体中心。
    local center_x, center_y = project_world_point({ x = ox, y = oy, z = oz + 36.0 })
    if not (is_number(center_x) and is_number(center_y)) then return false end
    return draw_screen_line(center_x, center_y)
end

local function draw_enemy_center_line(ctx, enemy, ox, oy, oz)
    if draw_box_center_line(ctx) then return true end
    return draw_projected_body_center(enemy, ox, oy, oz)
end

local function format_warning_value(value)
    if value == nil then return "[]" end

    local text = tostring(value)
    if text == "" then return "[]" end
    return text
end

local offscreen_warning_text_size = nil

local function get_offscreen_warning_text_size()
    if is_number(offscreen_warning_text_size) then
        return offscreen_warning_text_size
    end

    local success, _, default_height = pcall(function()
        return draw.measure("Ag")
    end)
    if not success or not is_number(default_height) or default_height <= 0 then
        return nil
    end

    offscreen_warning_text_size = default_height * OFFSCREEN_WARNING_TEXT_SCALE
    return offscreen_warning_text_size
end

local function draw_offscreen_warning_text(enemy, row)
    local screen_width, screen_height = draw.screen()
    if not (is_number(screen_width) and is_number(screen_height)) then return false end

    local team = read_member(enemy, "team_num")
    if team == nil then team = read_member(enemy, "squad_id") end
    local message = string.format(
        "你已被瞄准！队伍: %s，玩家: %s，等级: %s，击杀: %s",
        format_warning_value(team),
        format_warning_value(read_member(enemy, "name")),
        format_warning_value(read_member(enemy, "grade")),
        format_warning_value(read_member(enemy, "kills"))
    )

    local text_options = { outline = BLACK_OUTLINE }
    local text_size = get_offscreen_warning_text_size()
    if text_size ~= nil then
        text_options.size = text_size
    end

    draw.text(
        screen_width * OFFSCREEN_WARNING_X_RATIO,
        screen_height * OFFSCREEN_WARNING_Y_RATIO
            + (row - 1) * OFFSCREEN_WARNING_LINE_HEIGHT,
        LIGHT_YELLOW,
        message,
        text_options
    )
    return true
end

event.on("frame_update", function()
    -- 每帧复制坐标标量，避免跨 game.* 快照持有 Vec3 引用。
    if not get_local_position() then return end

    -- ESP 回调在实体离开视野后可能不再触发；直接遍历实体表，保证屏幕外提示仍每帧刷新。
    local entities = game.entities
    local players = entities and entities.players
    if players == nil then return end

    local offscreen_warning_row = 0
    for _, enemy in pairs(players) do
        local index = read_member(enemy, "index")
        if index == local_index
            or read_member(enemy, "is_teammate")
            or read_member(enemy, "is_dead") then
            clear_aim_streak(enemy)
        elseif read_member(enemy, "in_screen") ~= true then
            local ox, oy, oz = read_player_position(enemy)
            local is_aimed = ox ~= nil and is_being_aimed_at(enemy, ox, oy, oz)
            if warning_delay_elapsed(enemy, is_aimed) then
                offscreen_warning_row = offscreen_warning_row + 1
                draw_offscreen_warning_text(enemy, offscreen_warning_row)
            end
        end
    end
end)

local enemy_aim_warning = esp.add("enemy_aim_warning", function(enemy, ctx)
    if local_position.x == nil then return nil end
    if read_member(enemy, "index") == local_index then return nil end
    if read_member(enemy, "is_teammate") or read_member(enemy, "is_dead") then
        clear_aim_streak(enemy)
        return nil
    end
    if read_member(enemy, "in_screen") ~= true then return nil end
    if read_member(enemy, "can_draw") == false then
        clear_aim_streak(enemy)
        return nil
    end

    local ox, oy, oz = read_player_position(enemy)
    local is_aimed = ox ~= nil and is_being_aimed_at(enemy, ox, oy, oz)
    if not warning_delay_elapsed(enemy, is_aimed) then return nil end

    draw_enemy_center_line(ctx, enemy, ox, oy, oz)
    return nil
end, {
    label = "Enemy Aim Warning",
    kind = "free",
})

-- free 元素没有槽位拖拽入口，显式打开四种场景，避免默认禁用导致回调不触发。
if enemy_aim_warning ~= nil then
    enemy_aim_warning.enableds = { true, true, true, true }
end

log.success("敌人瞄准亮粉色提示（全范围版）已注册")
