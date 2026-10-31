-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 按本人手持武器的开镜视野角分档，自动切换七种倍镜参数方案。
-- 使用 game.localplayer.is_zooming、target_zoom_fov、event 及 config 接口。
-- 未开镜使用 config_1x；开镜按实测视野角下界匹配一至十倍档。
-- 切枪旧值、无效视野角或小于 2 时保持方案，不依赖敌人、不绘制调试信息。
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

local SCOPE_RULES = {
    { min = 46.4, key = "1x" },
    { min = 32.14, key = "2x" },
    { min = 22.95, key = "3x" },
    { min = 16.42, key = "4x" },
    { min = 11.59, key = "6x" },
    { min = 8.98, key = "8x" },
    { min = 2, key = "10x" },
}

local function scope_key(lp, ads)
    -- 未开镜时无需读取旧武器或无效的视野角，直接使用一倍档。
    if ads == false then
        return "1x"
    end
    if ads ~= true or lp.weapon_fields_stale == true then
        return nil
    end
    local fov = lp.target_zoom_fov
    if not is_finite(fov) then
        return nil
    end
    -- 按下界从大到小匹配，因此边界恰好属于用户指定的左闭右开区间。
    for _, rule in ipairs(SCOPE_RULES) do
        if fov >= rule.min then
            return rule.key
        end
    end
    return nil
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
    local key = scope_key(lp, lp.is_zooming)
    if key ~= nil then
        switch_to_plan("config_" .. key)
    end
end)

log.success("倍镜自动切参脚本已注册")
