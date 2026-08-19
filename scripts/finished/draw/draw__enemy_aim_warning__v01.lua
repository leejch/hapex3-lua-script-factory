-- 用多种 yaw/view_angle 解释诊断敌人是否把准星指向当前玩家。
-- 使用 game.localplayer、game.entities.players、math.CalcAngle、math.WorldToScreen、esp.add 和 draw.*。
-- 每种候选线的敌人端点按头部到脚部均匀分布，避免多条线重叠。
-- 确认算法后再关闭 DEBUG_DRAW，并恢复单条最终红线。

local AIM_CONE_DEGREES = 5.0
-- 临时诊断开关：确认实际运行时究竟经过了哪一层绘制/数据流程后再关闭。
local DEBUG_DRAW = true
local DEBUG_SINGLE_RED = true
-- 端点已经由上一轮确认；关闭橙/紫探针，避免与候选算法颜色混淆。
local DEBUG_ENDPOINTS = false

local FINAL_RED = draw.u8(255, 0, 0, 255)
local DEBUG_ORIGIN = draw.u8(255, 140, 0, 255)
local DEBUG_BOX_CENTER = draw.u8(64, 255, 255, 255)
local DEBUG_PROJECTED_CENTER = draw.u8(180, 64, 255, 255)
local TEST_YAW_DIRECT = draw.u8(255, 0, 0, 255)
local TEST_YAW_REVERSED = draw.u8(64, 255, 64, 255)
local TEST_YAW_PLUS_90 = draw.u8(64, 160, 255, 255)
local TEST_YAW_MINUS_90 = draw.u8(255, 220, 64, 255)
local TEST_YAW_PLUS_180 = draw.u8(255, 64, 160, 255)
local TEST_YAW_NEGATED_PLUS_90 = draw.u8(128, 255, 64, 255)
local TEST_YAW_NEGATED_MINUS_90 = draw.u8(64, 128, 255, 255)
local TEST_YAW_NEGATED_PLUS_180 = draw.u8(200, 64, 255, 255)
local TEST_YAW_ELEVATION = draw.u8(255, 64, 220, 255)
local TEST_YAW_PITCH = draw.u8(255, 140, 32, 255)
local TEST_VIEW_YAW_HORIZONTAL = draw.u8(64, 240, 240, 255)
local TEST_VIEW_YAW_ELEVATION = draw.u8(180, 64, 255, 255)
local TEST_MIXED_3D = draw.u8(255, 255, 255, 255)
local TEST_STANDARD_3D = draw.u8(190, 190, 190, 255)

local local_position = {
    x = nil,
    y = nil,
    z = nil,
}
local local_index = -1
local missing_view_angle_reported = false
local screen_box_fallback_reported = false

local function is_number(value)
    return type(value) == "number" and value == value and value > -1e6 and value < 1e6
end

local function read_vec3(value)
    if value == nil then return nil end

    local x, y, z = value.x, value.y, value.z
    if not (is_number(x) and is_number(y) and is_number(z)) then
        return nil
    end

    return x, y, z
end

local function read_player_position(player)
    local ok, camera_position = pcall(function()
        return player.camera_origin
    end)
    if ok then
        local x, y, z = read_vec3(camera_position)
        if x ~= nil then return x, y, z end
    end

    local origin = player.origin
    return read_vec3(origin)
end

local function read_enemy_view_angles(player)
    -- 当前 MCP 文档没有把 view_angle 列入 PlayerEntity 的公开字段；用 pcall 兼容
    -- 运行时已经提供该字段的版本，并在字段缺失时安全地返回 nil。
    local ok, view_angle = pcall(function()
        return player.view_angle
    end)
    if not ok or view_angle == nil then return nil end

    -- Vec2 文档保证 x/y；需求示例使用 pitch/yaw，因此两种字段名都兼容。
    local ok_pitch, named_pitch = pcall(function() return view_angle.pitch end)
    local ok_x, x_pitch = pcall(function() return view_angle.x end)
    local ok_yaw, named_yaw = pcall(function() return view_angle.yaw end)
    local ok_y, y_yaw = pcall(function() return view_angle.y end)

    local pitch = ok_pitch and named_pitch or nil
    if pitch == nil and ok_x then pitch = x_pitch end

    local yaw = ok_yaw and named_yaw or nil
    if yaw == nil and ok_y then yaw = y_yaw end

    if not is_number(pitch) then pitch = nil end
    if not is_number(yaw) then yaw = nil end
    return pitch, yaw
end

local function angle_close(first, second)
    if not (is_number(first) and is_number(second)) then return false end

    local error = math.AngleNormalize(first - second)
    return is_number(error) and math.abs(error) <= AIM_CONE_DEGREES
end

local function cone_close(target_elevation, view_elevation, horizontal_error)
    if not (is_number(target_elevation) and is_number(view_elevation)
        and is_number(horizontal_error)) then
        return false
    end

    -- 用球面夹角判断，避免水平和垂直各自 5 度时把对角线放宽到约 7 度。
    local target = math.rad(target_elevation)
    local view = math.rad(view_elevation)
    local horizontal = math.rad(math.AngleNormalize(horizontal_error))
    local dot = math.cos(target) * math.cos(view) * math.cos(horizontal)
        + math.sin(target) * math.sin(view)
    dot = math.max(-1.0, math.min(1.0, dot))

    return math.deg(math.acos(dot)) <= AIM_CONE_DEGREES
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
    local_index = is_number(player.index) and player.index or -1
    return true
end

local function is_direct_yaw_aiming(enemy, ox, oy, oz)
    local dx = local_position.x - ox
    local dy = local_position.y - oy
    local dz = local_position.z - oz
    if dx * dx + dy * dy + dz * dz <= 1e-8 then return false end

    local _, target_horizontal_yaw = math.CalcAngle(
        math.Vec3(ox, oy, oz),
        math.Vec3(local_position.x, local_position.y, local_position.z)
    )
    return angle_close(target_horizontal_yaw, enemy.yaw)
end

local function is_yaw_plus_180_aiming(enemy, ox, oy, oz)
    local dx = local_position.x - ox
    local dy = local_position.y - oy
    local dz = local_position.z - oz
    if dx * dx + dy * dy + dz * dz <= 1e-8 then return false end

    local _, target_horizontal_yaw = math.CalcAngle(
        math.Vec3(ox, oy, oz),
        math.Vec3(local_position.x, local_position.y, local_position.z)
    )
    return angle_close(target_horizontal_yaw, enemy.yaw + 180.0)
end

local function is_inside_aim_cone(enemy, vertical_yaw, ox, oy, oz)
    if ox == nil then return false end

    local dx = local_position.x - ox
    local dy = local_position.y - oy
    local dz = local_position.z - oz
    local distance_sq = dx * dx + dy * dy + dz * dz
    if distance_sq <= 1e-8 then return false end

    -- CalcAngle 的 pitch 按 MCP 约定为负值向上；转成需求约定的仰角后，正值向上。
    local target_pitch, target_horizontal_yaw = math.CalcAngle(
        math.Vec3(ox, oy, oz),
        math.Vec3(local_position.x, local_position.y, local_position.z)
    )
    if not (is_number(target_pitch) and is_number(target_horizontal_yaw)) then
        return false
    end

    local target_vertical_yaw = -target_pitch
    local enemy_horizontal_yaw = enemy.yaw
    if not is_number(enemy_horizontal_yaw) then return false end
    local horizontal_error = math.AngleNormalize(target_horizontal_yaw - enemy_horizontal_yaw)
    if not is_number(horizontal_error) then return false end

    -- 在球面上计算真实夹角，而不是分别比较两个轴，避免斜向目标被放宽到约 7 度。
    local target_vertical = math.rad(target_vertical_yaw)
    local enemy_vertical = math.rad(vertical_yaw)
    local horizontal = math.rad(horizontal_error)
    local dot = math.cos(target_vertical) * math.cos(enemy_vertical) * math.cos(horizontal)
        + math.sin(target_vertical) * math.sin(enemy_vertical)
    dot = math.max(-1.0, math.min(1.0, dot))

    return math.deg(math.acos(dot)) <= AIM_CONE_DEGREES
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
        -- 某些 Vec2 包装使用数组下标；同时兼容命名字段和数组字段。
        x = read_member(value, 1)
        y = read_member(value, 2)
    end
    if not (is_number(x) and is_number(y)) then return nil end
    return x, y
end

local function read_screen_box(ctx)
    local box = read_member(ctx, "box")
    if box == nil then return nil end

    local min_point = read_member(box, "min") or read_member(box, 1)
    local max_point = read_member(box, "max") or read_member(box, 2)
    local min_x, min_y = read_vec2(min_point)
    local max_x, max_y = read_vec2(max_point)
    if min_x == nil or max_x == nil then return nil end

    -- 空框常见表现是 min/max 全为 0；不能把它误当作左上角屏幕位置。
    if max_x <= min_x or max_y <= min_y then return nil end
    return min_x, min_y, max_x, max_y
end

local function draw_box_line(ctx, color, thickness, anchor, offset_x, offset_y)
    local min_x, min_y, max_x, max_y = read_screen_box(ctx)
    if min_x == nil then return false end

    local enemy_x = (min_x + max_x) * 0.5
    local enemy_y = (min_y + max_y) * 0.5
    if anchor == "min" then
        enemy_x, enemy_y = min_x, min_y
    elseif anchor == "max" then
        enemy_x, enemy_y = max_x, max_y
    end
    enemy_x = enemy_x + (offset_x or 0.0)
    enemy_y = enemy_y + (offset_y or 0.0)
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
        color,
        { thickness = thickness }
    )
    return true
end

local function draw_screen_line(enemy_x, enemy_y, color, thickness, offset_x, offset_y)
    if not (is_number(enemy_x) and is_number(enemy_y)) then return false end

    enemy_x = enemy_x + (offset_x or 0.0)
    enemy_y = enemy_y + (offset_y or 0.0)

    local screen_width, screen_height = draw.screen()
    if not (is_number(screen_width) and is_number(screen_height)) then return false end

    draw.line(
        screen_width * 0.5,
        screen_height * 0.5,
        enemy_x,
        enemy_y,
        color,
        { thickness = thickness }
    )
    return true
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

local function draw_projected_center_line(enemy, ox, oy, oz, color, thickness, offset_x, offset_y)
    -- ctx.box 不可用时，用脚底和头部两个世界点的屏幕中点作为备用中心。
    -- head_pos 是 PlayerEntity 的屏幕内字段，比给 origin 硬编码一个高度可靠。
    local foot_x, foot_y = project_world_point({ x = ox, y = oy, z = oz })
    local head_position = read_member(enemy, "head_pos")
    local head_world_x, head_world_y, head_world_z = read_vec3(head_position)
    local head_x, head_y = project_world_point(head_position)
    if is_number(head_x) and is_number(head_y)
        and is_number(head_world_x) and is_number(head_world_y) and is_number(head_world_z)
        and (head_world_x - ox) * (head_world_x - ox)
            + (head_world_y - oy) * (head_world_y - oy)
            + (head_world_z - oz) * (head_world_z - oz) > 1e-8 then
        return draw_screen_line(
            (foot_x + head_x) * 0.5,
            (foot_y + head_y) * 0.5,
            color,
            thickness,
            offset_x,
            offset_y
        )
    end

    -- 某些运行时版本不提供 head_pos；Apex 玩家高度约 72 游戏单位，36 是身体中部。
    local center_x, center_y = project_world_point({ x = ox, y = oy, z = oz + 36.0 })
    if not (is_number(center_x) and is_number(center_y)) then return false end
    return draw_screen_line(
        center_x,
        center_y,
        color,
        thickness,
        offset_x,
        offset_y
    )
end

local function draw_projected_body_point_line(enemy, ox, oy, oz, color, thickness, fraction)
    local foot_x, foot_y = project_world_point({ x = ox, y = oy, z = oz })
    if not (is_number(foot_x) and is_number(foot_y)) then return false end

    local head_position = read_member(enemy, "head_pos")
    local head_world_x, head_world_y, head_world_z = read_vec3(head_position)
    local head_x, head_y = project_world_point(head_position)
    local has_head = is_number(head_x) and is_number(head_y)
        and is_number(head_world_x) and is_number(head_world_y) and is_number(head_world_z)
        and (head_world_x - ox) * (head_world_x - ox)
            + (head_world_y - oy) * (head_world_y - oy)
            + (head_world_z - oz) * (head_world_z - oz) > 1e-8

    if not has_head then
        -- head_pos 缺失时，使用约 72 游戏单位的人体高度估算头部位置。
        head_x, head_y = project_world_point({ x = ox, y = oy, z = oz + 72.0 })
    end
    if not (is_number(head_x) and is_number(head_y)) then return false end

    local t = math.max(0.0, math.min(1.0, fraction or 0.5))
    return draw_screen_line(
        head_x + (foot_x - head_x) * t,
        head_y + (foot_y - head_y) * t,
        color,
        thickness
    )
end

local function draw_center_line(ctx, enemy, ox, oy, oz, color, thickness, offset_x, offset_y)
    if draw_box_line(ctx, color, thickness, "center", offset_x, offset_y) then
        return true
    end
    return draw_projected_center_line(enemy, ox, oy, oz, color, thickness, offset_x, offset_y)
end

local function draw_world_to_screen_line(ox, oy, oz, color, thickness, offset_x, offset_y)
    local screen_x, screen_y = project_world_point({ x = ox, y = oy, z = oz })
    if not (is_number(screen_x) and is_number(screen_y)) then return end

    -- 同一敌人可能同时命中多个候选算法；给终点少量错开，避免后画的颜色完全盖住前面的颜色。
    screen_x = screen_x + (offset_x or 0.0)
    screen_y = screen_y + (offset_y or 0.0)

    local screen_width, screen_height = draw.screen()
    if not (is_number(screen_width) and is_number(screen_height)) then return end

    draw.line(
        screen_width * 0.5,
        screen_height * 0.5,
        screen_x,
        screen_y,
        color,
        { thickness = thickness or 2.0 }
    )
end

local function draw_aim_candidate_lines(enemy, ox, oy, oz)
    local distance_sq = (local_position.x - ox) * (local_position.x - ox)
        + (local_position.y - oy) * (local_position.y - oy)
        + (local_position.z - oz) * (local_position.z - oz)
    if distance_sq <= 1e-8 then return end

    local target_pitch, target_horizontal_yaw = math.CalcAngle(
        math.Vec3(ox, oy, oz),
        math.Vec3(local_position.x, local_position.y, local_position.z)
    )
    if not (is_number(target_pitch) and is_number(target_horizontal_yaw)) then
        return
    end

    local target_elevation = -target_pitch
    local enemy_yaw = enemy.yaw
    local view_pitch, view_yaw = read_enemy_view_angles(enemy)
    local line_thickness = 2.0
    local candidate_count = 14

    local function emit(color, matched, slot)
        if matched then
            local fraction = (slot - 1) / (candidate_count - 1)
            draw_projected_body_point_line(enemy, ox, oy, oz, color, line_thickness, fraction)
        end
    end

    -- 红：直接把 PlayerEntity.yaw 当作水平朝向。
    if is_number(enemy_yaw) then
        emit(TEST_YAW_DIRECT, angle_close(target_horizontal_yaw, enemy_yaw), 1)
        -- 绿：水平 yaw 方向取反。
        emit(TEST_YAW_REVERSED, angle_close(target_horizontal_yaw, -enemy_yaw), 2)
        -- 蓝/黄：水平 yaw 需要额外加/减 90 度。
        emit(TEST_YAW_PLUS_90, angle_close(target_horizontal_yaw, enemy_yaw + 90.0), 3)
        emit(TEST_YAW_MINUS_90, angle_close(target_horizontal_yaw, enemy_yaw - 90.0), 4)
        -- 粉/浅绿/浅蓝/紫：再测试 180 度基准和取反后的轴向变换。
        emit(TEST_YAW_PLUS_180, angle_close(target_horizontal_yaw, enemy_yaw + 180.0), 5)
        emit(TEST_YAW_NEGATED_PLUS_90, angle_close(target_horizontal_yaw, -enemy_yaw + 90.0), 6)
        emit(TEST_YAW_NEGATED_MINUS_90, angle_close(target_horizontal_yaw, -enemy_yaw - 90.0), 7)
        emit(TEST_YAW_NEGATED_PLUS_180, angle_close(target_horizontal_yaw, -enemy_yaw + 180.0), 8)
        -- 粉/橙：把 PlayerEntity.yaw 分别当作仰角，正值向上/标准 pitch。
        emit(TEST_YAW_ELEVATION, angle_close(target_elevation, enemy_yaw), 9)
        emit(TEST_YAW_PITCH, angle_close(target_pitch, enemy_yaw), 10)
    end

    if view_yaw ~= nil then
        -- 青：view_angle.yaw 是水平 yaw。
        emit(TEST_VIEW_YAW_HORIZONTAL, angle_close(target_horizontal_yaw, view_yaw), 11)
        -- 紫：按用户约定，把 view_angle.yaw 当作仰角。
        emit(TEST_VIEW_YAW_ELEVATION, angle_close(target_elevation, view_yaw), 12)

        if is_number(enemy_yaw) then
            -- 白：水平使用 PlayerEntity.yaw，垂直使用 view_angle.yaw。
            emit(
                TEST_MIXED_3D,
                cone_close(target_elevation, view_yaw, target_horizontal_yaw - enemy_yaw),
                13
            )
        end
    end

    if view_pitch ~= nil and view_yaw ~= nil then
        -- 灰：标准三维解释，view_angle.yaw 为水平，-pitch 为仰角。
        emit(
            TEST_STANDARD_3D,
            cone_close(-target_pitch, -view_pitch, target_horizontal_yaw - view_yaw),
            14
        )
    end

    if view_pitch == nil and view_yaw == nil and not missing_view_angle_reported then
        missing_view_angle_reported = true
        log.warn("敌人 PlayerEntity 未提供 view_angle，本轮仅测试 PlayerEntity.yaw 候选")
    end
end

event.on("frame_update", function()
    -- 先复制坐标标量，再访问 players；不要跨 game.* 快照持有 Vec3 引用。
    get_local_position()
end)

local enemy_aim_warning = esp.add("enemy_aim_warning", function(enemy, ctx)
    if local_position.x == nil then return nil end
    if enemy.index == local_index or enemy.is_teammate or enemy.is_dead then return nil end
    if enemy.in_screen ~= true then return nil end
    if enemy.can_draw == false then return nil end

    local ox, oy, oz = read_player_position(enemy)
    if ox == nil then return nil end

    if DEBUG_SINGLE_RED then
        if is_direct_yaw_aiming(enemy, ox, oy, oz) then
            draw_center_line(ctx, enemy, ox, oy, oz, FINAL_RED, 2.0)
        end
        return nil
    end

    if DEBUG_DRAW then
        draw_aim_candidate_lines(enemy, ox, oy, oz)
    end

    if DEBUG_ENDPOINTS then
        -- 橙：已确认可工作的 enemy.origin 投影，终点仍是脚底。
        draw_world_to_screen_line(ox, oy, oz, DEBUG_ORIGIN, 1.5)

        -- 青：ctx.box 中心；紫：头脚投影/36 单位高度的几何中心备用。
        local box_drawn = draw_box_line(ctx, DEBUG_BOX_CENTER, 1.5, "center")
        if not box_drawn then
            draw_projected_center_line(enemy, ox, oy, oz, DEBUG_PROJECTED_CENTER, 1.5)
        end
    end

    if DEBUG_DRAW then return nil end

    -- 粉色候选已确认：enemy.yaw 需要加 180 度；终点取身体中心。
    if is_yaw_plus_180_aiming(enemy, ox, oy, oz) then
        local drawn = draw_center_line(ctx, enemy, ox, oy, oz, FINAL_RED, 2.0)
        if not drawn then
            if not screen_box_fallback_reported then
                screen_box_fallback_reported = true
                log.warn("ESP ctx.box 无有效屏幕坐标，红线使用 enemy.origin/head_pos 的屏幕中点失败")
            end
        end
    end
    return nil
end, {
    label = "Enemy Aim Warning",
    kind = "free",
})

-- free 元素没有槽位拖拽入口，显式打开四种场景，避免默认禁用导致回调完全不触发。
if enemy_aim_warning ~= nil then
    enemy_aim_warning.enableds = { true, true, true, true }
end

log.success("敌人瞄准警告绘制已注册")
