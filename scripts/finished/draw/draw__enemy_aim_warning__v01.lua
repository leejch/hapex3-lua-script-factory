-- 判断敌人的水平 yaw 是否在 5 度内指向当前玩家，并绘制一条 2px 红线。
-- 使用 game.localplayer、game.entities.players、math.CalcAngle、math.WorldToScreen、esp.add 和 draw.*。
-- 屏幕内终点优先读取 ESP 屏幕框，失败时使用头脚投影中点；屏幕外终点裁剪到对应屏幕边界。
-- 只保留正式运行逻辑，不包含候选算法、诊断探针或临时测试绘制。

local AIM_CONE_DEGREES = 5.0
local AIM_WARNING_DELAY_SECONDS = 0.8
local LINE_THICKNESS = 2.0
local FINAL_RED = draw.u8(255, 0, 0, 255)

local local_position = {
    x = nil,
    y = nil,
    z = nil,
}
local local_view_angle = {
    pitch = nil,
    yaw = nil,
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

local function read_view_angle(player)
    local angle = read_member(player, "view_angle")
    if angle == nil then return nil end

    local pitch = read_member(angle, "pitch")
    local yaw = read_member(angle, "yaw")
    if not is_number(pitch) then pitch = read_member(angle, "x") end
    if not is_number(yaw) then yaw = read_member(angle, "y") end
    if not (is_number(pitch) and is_number(yaw)) then return nil end
    return pitch, yaw
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
    local_view_angle.pitch = nil
    local_view_angle.yaw = nil
    local_index = -1

    local player = game.localplayer
    if player == nil then return false end

    local x, y, z = read_player_position(player)
    if x == nil then return false end

    local_position.x = x
    local_position.y = y
    local_position.z = z

    local pitch, yaw = read_view_angle(player)
    local_view_angle.pitch = pitch
    local_view_angle.yaw = yaw

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
        FINAL_RED,
        { thickness = LINE_THICKNESS }
    )
    return true
end

local function get_offscreen_endpoint(ox, oy, oz)
    if not (is_number(local_view_angle.pitch) and is_number(local_view_angle.yaw)) then
        return nil
    end

    local target_pitch, target_yaw = math.CalcAngle(
        math.Vec3(local_position.x, local_position.y, local_position.z),
        math.Vec3(ox, oy, oz)
    )
    if not (is_number(target_pitch) and is_number(target_yaw)) then return nil end

    local yaw_error = math.AngleNormalize(target_yaw - local_view_angle.yaw)
    local pitch_error = target_pitch - local_view_angle.pitch
    if not (is_number(yaw_error) and is_number(pitch_error)) then return nil end

    -- 用相对水平角决定左右/后方方向。正后方的方向向量为 (0, 1)，即屏幕底边。
    local yaw_radians = math.rad(yaw_error)
    local pitch_radians = math.rad(pitch_error)
    local direction_x = math.sin(yaw_radians)
    local direction_y = math.sin(pitch_radians) + math.max(0.0, -math.cos(yaw_radians))
    if math.abs(direction_x) <= 1e-8 and math.abs(direction_y) <= 1e-8 then
        direction_y = 1.0
    end

    local screen_width, screen_height = draw.screen()
    if not (is_number(screen_width) and is_number(screen_height)) then return nil end

    local half_width = screen_width * 0.5
    local half_height = screen_height * 0.5
    local scale = math.huge
    if math.abs(direction_x) > 1e-8 then
        scale = math.min(scale, half_width / math.abs(direction_x))
    end
    if math.abs(direction_y) > 1e-8 then
        scale = math.min(scale, half_height / math.abs(direction_y))
    end
    if scale == math.huge then return nil end

    return half_width + direction_x * scale,
        half_height + direction_y * scale
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

local function draw_offscreen_aim_line(ox, oy, oz)
    local screen_x, screen_y = get_offscreen_endpoint(ox, oy, oz)
    if not (is_number(screen_x) and is_number(screen_y)) then return false end
    return draw_screen_line(screen_x, screen_y)
end

event.on("frame_update", function()
    -- 每帧复制坐标标量，避免跨 game.* 快照持有 Vec3 引用。
    if not get_local_position() then return end

    -- ESP 回调在实体离开视野后可能不再触发；直接遍历实体表，保证屏幕外提示仍每帧刷新。
    local entities = game.entities
    local players = entities and entities.players
    if players == nil then return end

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
                draw_offscreen_aim_line(ox, oy, oz)
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

log.success("敌人瞄准红线（全范围版）已注册")
