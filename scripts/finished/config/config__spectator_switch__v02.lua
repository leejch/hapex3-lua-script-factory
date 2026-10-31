-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 按本人 UID 统计当前对局中正在观战本人的玩家数量，并自动切换 HApex3.0 参数方案。
-- 观战人数区间由下方 SPECTATOR_PLAN_RULES 维护，min/max 都是闭区间，max=nil 表示无上限。
-- 优先使用 UID，必要时使用 game.localplayer.self_base/index 兜底，再解码 players[].spec_index 句柄并调用 config.switch。
-- 正式版不创建调试 ESP；只保留必要的日志告警，避免影响游戏画面。

local SPECTATOR_PLAN_RULES = {
    { min = 0, max = 0, plan = "config" },
    { min = 1, max = 1, plan = "config_a" },
    { min = 2, max = 2, plan = "config_b" },
    { min = 3, max = nil, plan = "config_c" },
}

-- 切换失败时保留短暂重试间隔，避免配置名写错后每个帧更新都调用切换接口。
local SWITCH_RETRY_INTERVAL_FRAMES = 120

-- 实际运行时 spec_index 是 EHandle 形式的原始值，实体索引位在低 12 位。
local SPEC_HANDLE_INDEX_MODULUS = 4096

local last_failed_plan = nil
local last_failed_frame = -math.huge
local last_scan_error = nil
local last_mapping_error = nil
local last_reported_count = nil
local last_reported_plan = nil

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

local function is_nonnegative_integer(value)
    return is_integer(value) and value >= 0
end

local function decode_spec_index(value)
    if not is_nonnegative_integer(value) then
        return nil
    end

    -- 例如 65575 的低 12 位是 39；直接拿原始句柄与本人 index 比较会匹配不到。
    return value % SPEC_HANDLE_INDEX_MODULUS
end

local function canonical_uid(value)
    -- platform_uid 官方类型是字符串；不把 Lua number 转回字符串，避免大 UID 发生精度损失。
    if type(value) ~= "string" or not value:match("^%d+$") then
        return nil
    end

    local normalized = value:gsub("^0+", "")
    if normalized == "" then
        return nil
    end
    return normalized
end

local function validate_plan_rules(rules)
    if type(rules) ~= "table" or #rules == 0 then
        return false, "观战人数映射不能为空"
    end

    local previous_max = nil
    for index, rule in ipairs(rules) do
        if type(rule) ~= "table"
            or not is_nonnegative_integer(rule.min)
            or (rule.max ~= nil and not is_nonnegative_integer(rule.max))
            or (rule.max ~= nil and rule.max < rule.min)
            or type(rule.plan) ~= "string"
            or rule.plan == ""
        then
            return false, "第 " .. index .. " 条映射格式无效"
        end

        -- 表按 min 升序排列且不能重叠；允许留空区间，留空时运行中会保持现有方案并告警。
        if previous_max == nil and index > 1 then
            return false, "无上限区间必须是最后一条映射"
        end
        if previous_max ~= nil and rule.min <= previous_max then
            return false, "第 " .. index .. " 条映射与前一条区间重叠或未按顺序排列"
        end

        previous_max = rule.max
    end

    return true, nil
end

local rules_valid, rules_error = validate_plan_rules(SPECTATOR_PLAN_RULES)
if not rules_valid then
    log.error("观战切参脚本未启动：" .. rules_error)
    return
end

local function find_plan_for_count(spectator_count)
    for _, rule in ipairs(SPECTATOR_PLAN_RULES) do
        if spectator_count >= rule.min
            and (rule.max == nil or spectator_count <= rule.max)
        then
            return rule.plan
        end
    end
    return nil
end

local function plan_is_available(plan)
    local ok, plans = pcall(config.list)
    if not ok or type(plans) ~= "table" then
        return nil
    end

    local plan_count = 0
    for _, available_plan in pairs(plans) do
        plan_count = plan_count + 1
        if tostring(available_plan) == plan then
            return true
        end
    end

    -- 空列表在部分运行时只表示列表暂不可用，不能据此判定方案不存在。
    if plan_count == 0 then
        return nil
    end
    return false
end

local function collect_player_snapshot()
    if not game:is_in_game() then
        return nil, "当前不在对局中"
    end

    local localplayer = game.localplayer
    if localplayer == nil then
        return nil, "game.localplayer 尚未可用"
    end

    local self_uid = canonical_uid(localplayer.platform_uid)
    local local_index = localplayer.index
    if not is_nonnegative_integer(local_index) then
        local_index = nil
    end

    local self_base = localplayer.self_base
    if type(self_base) ~= "number" or self_base <= 0 or self_base ~= math.floor(self_base) then
        self_base = nil
    end

    if self_uid == nil and local_index == nil and self_base == nil then
        return nil, "game.localplayer 尚未提供有效 UID、self_base 或 index"
    end

    local entities = game.entities
    local players = entities and entities.players
    if players == nil then
        return nil, "game.entities.players 尚未可用"
    end

    -- 固定本帧实体引用后再做身份匹配和反向统计，避免两次遍历跨越不同快照。
    local player_snapshot = {}
    for key, player in pairs(players) do
        local player_index = player.index
        if not is_nonnegative_integer(player_index) and is_nonnegative_integer(key) then
            -- 某些运行时版本可能只把实体索引放在 players 的键上。
            player_index = key
        end
        player_snapshot[#player_snapshot + 1] = {
            entity = player,
            index = player_index,
        }
    end

    local base_index = nil
    local base_match_count = 0
    local uid_index = nil
    local uid_match_count = 0

    for _, entry in ipairs(player_snapshot) do
        local player = entry.entity
        if not player.is_npc and entry.index ~= nil then
            if self_base ~= nil and player.base == self_base then
                base_match_count = base_match_count + 1
                base_index = entry.index
            end
            if self_uid ~= nil and canonical_uid(player.platform_uid) == self_uid then
                uid_match_count = uid_match_count + 1
                uid_index = entry.index
            end
        end
    end

    local self_index = nil
    if base_match_count == 1 then
        -- self_base 在死亡观战时仍指向真实本机，优先于跟随观战目标的 base/index。
        self_index = base_index
    elseif uid_match_count == 1 then
        self_index = uid_index
    elseif uid_match_count > 1 then
        return nil, "同一 UID 匹配到多个玩家实体，已停止切参"
    elseif local_index ~= nil then
        -- 若实体表不包含本人，仍可使用 localplayer.index 统计指向本人的 spec_index。
        self_index = local_index
    else
        return nil, "无法从 UID、self_base 或 localplayer.index 确认本人实体"
    end

    local spectator_count = 0
    for _, entry in ipairs(player_snapshot) do
        local player = entry.entity
        local player_index = entry.index
        local decoded_spec_index = decode_spec_index(player.spec_index)
        if not player.is_npc
            and is_nonnegative_integer(player_index)
            and player_index ~= self_index
            and decoded_spec_index ~= nil
            and decoded_spec_index == self_index
        then
            spectator_count = spectator_count + 1
        end
    end

    return {
        self_index = self_index,
        spectator_count = spectator_count,
    }, nil
end

local function report_scan_error(message)
    if message == "当前不在对局中" then
        last_scan_error = nil
        return
    end

    if message ~= last_scan_error then
        log.warn("观战切参暂缓：" .. message)
        last_scan_error = message
    end
end

local function switch_to_plan(plan, spectator_count, frame)
    local current_plan = config.current()
    if current_plan == plan then
        last_failed_plan = nil
        last_failed_frame = -math.huge
        if last_reported_count ~= spectator_count or last_reported_plan ~= plan then
            log.info(string.format("本人当前有 %d 名观战者，使用参数方案 %s", spectator_count, plan))
            last_reported_count = spectator_count
            last_reported_plan = plan
        end
        return
    end

    if last_failed_plan == plan
        and frame - last_failed_frame < SWITCH_RETRY_INTERVAL_FRAMES
    then
        return
    end

    last_failed_plan = plan
    last_failed_frame = frame
    -- 某些运行时会在成功切换后返回 nil/false，因此不能用返回值判断结果。
    local switch_called, switch_error = pcall(config.switch, plan)
    local observed_plan = config.current()
    if observed_plan == plan then
        last_failed_plan = nil
        last_failed_frame = -math.huge
        last_reported_count = spectator_count
        last_reported_plan = plan
        log.info(string.format("本人当前有 %d 名观战者，已切换参数方案 %s", spectator_count, plan))
        return
    end

    if not switch_called then
        log.warn("观战切参失败：config.switch 调用异常：" .. tostring(switch_error))
        return
    end

    if plan_is_available(plan) == false then
        log.warn("观战切参失败：不存在参数方案 " .. plan)
        return
    end

    -- current 可能在下一帧才发布新方案；本次不因返回值或瞬时旧值误报失败。
end

event.on("frame_update", function()
    local frame = time.frame_count()
    local snapshot, scan_error = collect_player_snapshot()
    if snapshot == nil then
        report_scan_error(scan_error)
        return
    end

    last_scan_error = nil
    local target_plan = find_plan_for_count(snapshot.spectator_count)
    if target_plan == nil then
        local mapping_error = "观战人数 " .. snapshot.spectator_count .. " 没有对应的参数方案"
        if mapping_error ~= last_mapping_error then
            log.warn("观战切参暂缓：" .. mapping_error)
            last_mapping_error = mapping_error
        end
        return
    end

    last_mapping_error = nil
    switch_to_plan(target_plan, snapshot.spectator_count, frame)
end)

log.success("观战人数自动切参正式版已注册")
