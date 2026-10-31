-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 按屏幕内与准星视线夹角最小的敌人距离，自动切换四档参数方案。
-- 使用 game 玩家快照、math.CalcAngle、event 帧更新及 config 方案接口。
-- 距离区间为 [0,50)、[50,100)、[100,200)、[200,+∞)，单位为米。
-- 无有效敌人或本人死亡、倒地时保持当前方案，不绘制调试信息。
-- 所有目标方案均须启用本脚本，三个自动切参脚本每次仅启用一个。

-- 缺失方案和失败切换都限频重试，避免每帧刷日志或反复加载配置。
local SWITCH_RETRY_INTERVAL_FRAMES = 120
local last_attempt_plan = nil
local last_attempt_frame = -math.huge

local function is_finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function active_localplayer()
    if not game:is_in_game() then
        return nil
    end
    local lp = game.localplayer
    if lp == nil or lp.is_dead or lp.is_down then
        return nil
    end
    return lp
end

local function valid_position(position)
    return position ~= nil and is_finite(position.x)
        and is_finite(position.y) and is_finite(position.z)
end

local function find_target_distance(lp)
    if not valid_position(lp.camera_origin)
        or lp.view_angle == nil
        or not is_finite(lp.view_angle.x) or not is_finite(lp.view_angle.y)
    then
        return nil
    end

    local view_pitch = math.rad(lp.view_angle.x)
    local view_yaw = math.rad(lp.view_angle.y)
    local best_cosine = -math.huge
    local best_distance = nil
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
                    end
                end
            end
        end
    end
    return best_distance
end

local function distance_key(distance)
    if distance < 50 then return "0_50" end
    if distance < 100 then return "50_100" end
    if distance < 200 then return "100_200" end
    return "200_inf"
end

local function switch_to_plan(plan)
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
        log.warn("自动切参暂缓：方案列表不可用或不存在参数方案 " .. plan)
        return
    end

    -- 切换接口没有可靠返回值，以当前方案名确认；延迟发布时等待后续帧即可。
    local called, switch_error = pcall(config.switch, plan)
    if config.current() == plan then
        last_attempt_plan = nil
        last_attempt_frame = -math.huge
        log.info("已切换参数方案 " .. plan)
    elseif not called then
        log.warn("自动切参失败：" .. tostring(switch_error))
    end
end

event.on("frame_update", function()
    local lp = active_localplayer()
    if lp == nil then return end
    local distance = find_target_distance(lp)
    if distance ~= nil then
        switch_to_plan("config_" .. distance_key(distance))
    end
end)

log.success("距离自动切参脚本已注册")
