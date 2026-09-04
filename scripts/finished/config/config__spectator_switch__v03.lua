-- 分开统计正在观战本人的队友与敌人，并按互斥优先级自动切换 HApex3.0 参数方案。
-- 有队友观战时只匹配 TEAMMATE_SPECTATOR_PLAN_RULES，没有队友观战时只匹配 ENEMY_SPECTATOR_PLAN_RULES。
-- 通过 UID、self_base 或 index 确认本人，再解码 players[].spec_index 句柄并使用 is_teammate 分类。
-- 两组人数区间的 min/max 都是闭区间，max=nil 表示无上限；正式版不绘制调试内容。

local ENEMY_SPECTATOR_PLAN_RULES = {
    { min = 0, max = 0, plan = "config" },
    { min = 1, max = 1, plan = "config_a" },
    { min = 2, max = 2, plan = "config_b" },
    { min = 3, max = nil, plan = "config_c" },
}

local TEAMMATE_SPECTATOR_PLAN_RULES = {
    { min = 1, max = 1, plan = "config_teammate_a" },
    { min = 2, max = 2, plan = "config_teammate_b" },
    { min = 3, max = nil, plan = "config_teammate_c" },
}

local SWITCH_RETRY_INTERVAL_FRAMES = 120
local SPEC_HANDLE_INDEX_MODULUS = 4096

local last_failed_plan = nil
local last_failed_frame = -math.huge
local last_scan_error = nil
local last_mapping_error = nil
local last_reported_key = nil
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
    return value % SPEC_HANDLE_INDEX_MODULUS
end

local function canonical_uid(value)
    -- UID 保持字符串比较，避免 uint64 经 Lua number 表示后损失精度。
    if type(value) ~= "string" or not value:match("^%d+$") then
        return nil
    end
    local normalized = value:gsub("^0+", "")
    if normalized == "" then
        return nil
    end
    return normalized
end

local function validate_plan_rules(rules, label, required_first_min)
    if type(rules) ~= "table" or #rules == 0 then
        return false, label .. "观战人数映射不能为空"
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
            return false, label .. "第 " .. index .. " 条映射格式无效"
        end
        if index == 1 and rule.min ~= required_first_min then
            return false, label .. "第一条映射必须从 " .. required_first_min .. " 开始"
        end
        if previous_max == nil and index > 1 then
            return false, label .. "无上限区间必须是最后一条映射"
        end
        if previous_max ~= nil and rule.min <= previous_max then
            return false, label .. "第 " .. index .. " 条映射与前一条区间重叠或未按顺序排列"
        end
        previous_max = rule.max
    end
    return true, nil
end

local enemy_rules_valid, enemy_rules_error = validate_plan_rules(ENEMY_SPECTATOR_PLAN_RULES, "敌人", 0)
local teammate_rules_valid, teammate_rules_error = validate_plan_rules(TEAMMATE_SPECTATOR_PLAN_RULES, "队友", 1)
if not enemy_rules_valid or not teammate_rules_valid then
    log.error("观战切参脚本未启动：" .. (enemy_rules_error or teammate_rules_error))
    return
end

local function find_plan_for_count(rules, count)
    for _, rule in ipairs(rules) do
        if count >= rule.min and (rule.max == nil or count <= rule.max) then
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
    local local_index = is_nonnegative_integer(localplayer.index) and localplayer.index or nil
    local self_base = localplayer.self_base
    if type(self_base) ~= "number" or self_base <= 0 or self_base ~= math.floor(self_base) then
        self_base = nil
    end
    if self_uid == nil and local_index == nil and self_base == nil then
        return nil, "game.localplayer 尚未提供有效 UID、self_base 或 index"
    end

    local players = game.entities and game.entities.players
    if players == nil then
        return nil, "game.entities.players 尚未可用"
    end

    -- 固定同一帧的实体引用，避免身份解析和观战分类跨越不同快照。
    local player_snapshot = {}
    for key, player in pairs(players) do
        local player_index = player.index
        if not is_nonnegative_integer(player_index) and is_nonnegative_integer(key) then
            player_index = key
        end
        player_snapshot[#player_snapshot + 1] = { entity = player, index = player_index }
    end

    local base_index, base_match_count = nil, 0
    local uid_index, uid_match_count = nil, 0
    for _, entry in ipairs(player_snapshot) do
        local player = entry.entity
        if not player.is_npc and entry.index ~= nil then
            if self_base ~= nil and player.base == self_base then
                base_index, base_match_count = entry.index, base_match_count + 1
            end
            if self_uid ~= nil and canonical_uid(player.platform_uid) == self_uid then
                uid_index, uid_match_count = entry.index, uid_match_count + 1
            end
        end
    end

    local self_index = nil
    if base_match_count == 1 then
        -- 死亡观战时 self_base 仍指向真实本人，不能使用会跟随观战目标的 base/index。
        self_index = base_index
    elseif uid_match_count == 1 then
        self_index = uid_index
    elseif uid_match_count > 1 then
        return nil, "同一 UID 匹配到多个玩家实体，已停止切参"
    elseif local_index ~= nil then
        self_index = local_index
    else
        return nil, "无法从 UID、self_base 或 localplayer.index 确认本人实体"
    end

    local teammate_count, enemy_count = 0, 0
    for _, entry in ipairs(player_snapshot) do
        local player = entry.entity
        local decoded_spec_index = decode_spec_index(player.spec_index)
        if not player.is_npc
            and is_nonnegative_integer(entry.index)
            and entry.index ~= self_index
            and decoded_spec_index == self_index
        then
            -- is_teammate 是官方按本机阵营计算的布尔字段，false 明确表示敌人。
            if player.is_teammate == true then
                teammate_count = teammate_count + 1
            elseif player.is_teammate == false then
                enemy_count = enemy_count + 1
            else
                return nil, "观战者 " .. entry.index .. " 的 is_teammate 尚未可用"
            end
        end
    end

    return { teammate_count = teammate_count, enemy_count = enemy_count }, nil
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

local function counts_key(teammate_count, enemy_count)
    return teammate_count .. ":" .. enemy_count
end

local function describe_counts(teammate_count, enemy_count)
    return string.format("队友观战 %d 人、敌人观战 %d 人", teammate_count, enemy_count)
end

local function switch_to_plan(plan, teammate_count, enemy_count, frame)
    local key = counts_key(teammate_count, enemy_count)
    if config.current() == plan then
        last_failed_plan, last_failed_frame = nil, -math.huge
        if last_reported_key ~= key or last_reported_plan ~= plan then
            log.info(describe_counts(teammate_count, enemy_count) .. "，使用参数方案 " .. plan)
            last_reported_key, last_reported_plan = key, plan
        end
        return
    end
    if last_failed_plan == plan and frame - last_failed_frame < SWITCH_RETRY_INTERVAL_FRAMES then
        return
    end

    last_failed_plan, last_failed_frame = plan, frame
    local switch_called, switch_error = pcall(config.switch, plan)
    if config.current() == plan then
        last_failed_plan, last_failed_frame = nil, -math.huge
        last_reported_key, last_reported_plan = key, plan
        log.info(describe_counts(teammate_count, enemy_count) .. "，已切换参数方案 " .. plan)
        return
    end
    if not switch_called then
        log.warn("观战切参失败：config.switch 调用异常：" .. tostring(switch_error))
    elseif plan_is_available(plan) == false then
        log.warn("观战切参失败：不存在参数方案 " .. plan)
    end
end

event.on("frame_update", function()
    local frame = time.frame_count()
    local snapshot, scan_error = collect_player_snapshot()
    if snapshot == nil then
        report_scan_error(scan_error)
        return
    end
    last_scan_error = nil

    local use_teammate_rules = snapshot.teammate_count > 0
    local active_count = use_teammate_rules and snapshot.teammate_count or snapshot.enemy_count
    local active_rules = use_teammate_rules and TEAMMATE_SPECTATOR_PLAN_RULES or ENEMY_SPECTATOR_PLAN_RULES
    local target_plan = find_plan_for_count(active_rules, active_count)
    if target_plan == nil then
        local rule_kind = use_teammate_rules and "队友" or "敌人"
        local mapping_error = rule_kind .. "观战人数 " .. active_count .. " 没有对应的参数方案"
        if mapping_error ~= last_mapping_error then
            log.warn("观战切参暂缓：" .. mapping_error)
            last_mapping_error = mapping_error
        end
        return
    end

    last_mapping_error = nil
    switch_to_plan(target_plan, snapshot.teammate_count, snapshot.enemy_count, frame)
end)

log.success("队友与敌人观战人数分流切参脚本已注册")
