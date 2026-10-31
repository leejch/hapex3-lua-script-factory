-- 按屏幕内与视线夹角最小的敌人距离，自动切换四档参数方案。
-- 使用 game 玩家快照、math.CalcAngle、event 帧更新、draw 文字及 config 方案接口。
-- 距离区间为 [0,50)、[50,100)、[100,200)、[200,+∞)，单位为米。
-- 在屏幕宽度 85%、高度 25% 处显示目标距离与名称，无有效目标时隐藏并保持方案。
-- 四个方案均须启用本脚本，避免方案切换时被运行时自动卸载。

local DISTANCE_PLAN_RULES = {
    { max = 50, plan = "config_0_50" },
    { max = 100, plan = "config_50_100" },
    { max = 200, plan = "config_100_200" },
    { max = math.huge, plan = "config_200_inf" },
}

-- 缺失方案和失败切换都限频重试，避免每帧刷日志或反复加载配置。
local SWITCH_RETRY_INTERVAL_FRAMES = 120
local last_attempt_plan = nil
local last_attempt_frame = -math.huge

local function is_finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function valid_position(position)
    return position ~= nil and is_finite(position.x)
        and is_finite(position.y) and is_finite(position.z)
end

local function find_target_distance()
    if not game:is_in_game() then
        return nil
    end

    local lp = game.localplayer
    if lp == nil or lp.is_dead or lp.is_down
        or not valid_position(lp.camera_origin)
        or lp.view_angle == nil
        or not is_finite(lp.view_angle.x) or not is_finite(lp.view_angle.y)
    then
        return nil
    end

    local view_pitch = math.rad(lp.view_angle.x)
    local view_yaw = math.rad(lp.view_angle.y)
    local best_cosine = -math.huge
    local best_distance = nil
    local best_name = nil
    local players = game.entities.players
    for _, player in pairs(players) do
        if player.in_screen and not player.is_teammate
            and not player.is_dead and not player.is_down
            and player.index ~= lp.index
            and is_finite(player.distance) and player.distance >= 0
            and valid_position(player.origin)
        then
            -- 统一以实体原点为角度参考，避免头部骨骼尚未刷新或遗留旧值时选错敌人。
            local origin = player.origin
            local camera = lp.camera_origin
            if origin.x ~= camera.x or origin.y ~= camera.y or origin.z ~= camera.z then
                local pitch, yaw = math.CalcAngle(camera, origin)
                if is_finite(pitch) and is_finite(yaw) then
                    pitch = math.rad(pitch)
                    yaw = math.rad(yaw)
                    -- 两个方向的点积越大，真实三维夹角越小；自然处理 ±180° 跨界。
                    local cosine = math.sin(view_pitch) * math.sin(pitch)
                        + math.cos(view_pitch) * math.cos(pitch) * math.cos(yaw - view_yaw)
                    if cosine > best_cosine
                        or (cosine == best_cosine
                            and (best_distance == nil or player.distance < best_distance))
                    then
                        best_cosine = cosine
                        best_distance = player.distance
                        best_name = player.name
                    end
                end
            end
        end
    end
    return best_distance, best_name
end

local function draw_target_info(distance, name)
    local width, height = draw.screen()
    local x, y = width * 0.85, height * 0.25
    local options = { size = 20, outline = true }
    local color = draw.rgba(1, 1, 1, 1)
    draw.text(x, y, color, string.format("%.0f m", distance), options)
    draw.text(x, y + 24, color,
        type(name) == "string" and name ~= "" and name or "未知玩家", options)
end

local function find_plan(distance)
    for _, rule in ipairs(DISTANCE_PLAN_RULES) do
        if distance < rule.max then
            return rule.plan
        end
    end
end

local function switch_to_plan(plan, distance)
    if config.current() == plan then
        last_attempt_plan = nil
        last_attempt_frame = -math.huge
        return
    end

    local frame = time.frame_count()
    if last_attempt_plan == plan
        and frame - last_attempt_frame < SWITCH_RETRY_INTERVAL_FRAMES
    then
        return
    end
    last_attempt_plan = plan
    last_attempt_frame = frame

    -- 当前接口会为不存在的名称创建默认方案，因此必须在切换之前确认存在。
    local listed, plans = pcall(config.list)
    local available = false
    if listed and type(plans) == "table" then
        for _, name in pairs(plans) do
            if name == plan then
                available = true
                break
            end
        end
    end
    if not available then
        log.warn("距离切参暂缓：方案列表不可用或不存在参数方案 " .. plan)
        return
    end

    -- 切换接口没有可靠返回值，以当前方案名确认；延迟发布时等待后续帧即可。
    local called, switch_error = pcall(config.switch, plan)
    if config.current() == plan then
        last_attempt_plan = nil
        last_attempt_frame = -math.huge
        log.info(string.format("中心夹角最小敌人距离 %.1f 米，已切换参数方案 %s", distance, plan))
    elseif not called then
        log.warn("距离切参失败：" .. tostring(switch_error))
    end
end

event.on("frame_update", function()
    local distance, name = find_target_distance()
    if distance ~= nil then
        -- 每帧重绘，且先于可能卸载本脚本的方案切换，避免使用跨帧实体引用。
        draw_target_info(distance, name)
        switch_to_plan(find_plan(distance), distance)
    end
end)

log.success("基于中心夹角最小敌人距离自动切参脚本已注册")
