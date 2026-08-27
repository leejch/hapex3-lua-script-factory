-- 按本人 UID 统计当前对局中正在观战本人的玩家数量，并自动切换 HApex3.0 参数方案。
-- 观战人数区间由下方 SPECTATOR_PLAN_RULES 维护，min/max 都是闭区间，max=nil 表示无上限。
-- 优先使用 UID，必要时使用 game.localplayer.self_base/index 兜底，再解码 players[].spec_index 句柄并调用 config.switch。
-- 通过 free ESP 在屏幕中央约 30% 高度处显示身份、spec_index 原值/解码值、观战数量和切参结果诊断。

local SPECTATOR_PLAN_RULES = {
    { min = 0, max = 0, plan = "config" },
    { min = 1, max = 2, plan = "config_a" },
    { min = 3, max = 4, plan = "config_b" },
    { min = 5, max = nil, plan = "config_c" },
}

-- 切换失败时保留短暂重试间隔，避免配置名写错后每个渲染帧都调用切换接口。
local SWITCH_RETRY_INTERVAL_FRAMES = 120

-- 截图中的 spec_index 是 EHandle 形式的原始值，实体索引位在低 12 位。
local SPEC_HANDLE_INDEX_MODULUS = 4096

local last_failed_plan = nil
local last_failed_frame = -math.huge
local last_scan_error = nil
local last_mapping_error = nil
local last_reported_count = nil
local last_reported_plan = nil

local MAX_DEBUG_SPEC_REFS = 10
local debug_state = {
    status = "等待首次扫描",
    error = "",
    local_uid = "-",
    local_index = "-",
    local_spec_index = "-",
    self_base = "-",
    resolved_index = "-",
    resolved_by = "-",
    player_total = 0,
    uid_matches = 0,
    base_matches = 0,
    spectator_count = "-",
    target_plan = "-",
    current_plan = "-",
    switch_status = "未执行",
    available_plans = "-",
    spec_refs = "-",
    self_matches = "-",
}

local function set_scan_error(message)
    debug_state.status = "扫描暂停"
    debug_state.error = message
    return nil, message
end

local function list_to_text(values)
    if #values == 0 then
        return "-"
    end
    return table.concat(values, ", ")
end

local function refresh_available_plans()
    local ok, plans = pcall(config.list)
    if not ok or type(plans) ~= "table" then
        debug_state.available_plans = "读取失败"
        return
    end

    local names = {}
    for index, plan in ipairs(plans) do
        if index > MAX_DEBUG_SPEC_REFS then
            names[#names + 1] = "..."
            break
        end
        names[#names + 1] = tostring(plan)
    end
    debug_state.available_plans = list_to_text(names)
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

    -- 例如 65575 的低 12 位是 39；直接拿 65575 与本人 index 比较会永远匹配不到。
    return value % SPEC_HANDLE_INDEX_MODULUS
end

local function format_spec_index(value)
    if not is_integer(value) then
        return "-"
    end

    local decoded = decode_spec_index(value)
    if decoded == nil or decoded == value then
        return tostring(value)
    end
    return tostring(value) .. "(" .. tostring(decoded) .. ")"
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

local function collect_player_snapshot()
    debug_state.error = ""
    debug_state.spectator_count = "-"
    debug_state.target_plan = "-"
    debug_state.self_matches = "-"
    debug_state.spec_refs = "-"

    if not game:is_in_game() then
        debug_state.status = "当前不在对局中"
        debug_state.local_uid = "-"
        debug_state.local_index = "-"
        debug_state.local_spec_index = "-"
        debug_state.self_base = "-"
        debug_state.resolved_index = "-"
        debug_state.resolved_by = "-"
        debug_state.player_total = 0
        debug_state.uid_matches = 0
        debug_state.base_matches = 0
        return set_scan_error("当前不在对局中")
    end

    local localplayer = game.localplayer
    if localplayer == nil then
        return set_scan_error("game.localplayer 尚未可用")
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

    debug_state.status = "读取玩家快照"
    debug_state.local_uid = self_uid or "无效"
    debug_state.local_index = local_index and tostring(local_index) or "-"
    debug_state.local_spec_index = format_spec_index(localplayer.spec_index)
    debug_state.self_base = self_base and tostring(self_base) or "-"

    if self_uid == nil and local_index == nil and self_base == nil then
        return set_scan_error("game.localplayer 尚未提供有效 UID、self_base 或 index")
    end

    local entities = game.entities
    local players = entities and entities.players
    if players == nil then
        return set_scan_error("game.entities.players 尚未可用")
    end

    -- 先固定本帧实体引用和索引，再进行身份匹配和反向统计，避免两次遍历跨越不同快照。
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
    debug_state.player_total = #player_snapshot

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
    debug_state.uid_matches = uid_match_count
    debug_state.base_matches = base_match_count

    local self_index = nil
    local self_source = nil
    if base_match_count == 1 then
        -- self_base 在死亡观战时仍指向真实本机，优先级高于可能跟随观战目标的 base/index。
        self_index = base_index
        self_source = "self_base"
    elseif uid_match_count == 1 then
        self_index = uid_index
        self_source = "platform_uid"
    elseif uid_match_count > 1 then
        return set_scan_error("同一 UID 匹配到多个玩家实体，已停止切参")
    elseif local_index ~= nil then
        -- 若实体表不包含本人，仍可直接使用 localplayer.index 统计指向本人的 spec_index。
        self_index = local_index
        self_source = "localplayer.index"
    else
        return set_scan_error("无法从 UID、self_base 或 localplayer.index 确认本人实体")
    end
    debug_state.resolved_index = tostring(self_index)
    debug_state.resolved_by = self_source
    debug_state.status = "统计 spec_index 句柄"

    local spectator_count = 0
    local spec_refs = {}
    local self_matches = {}
    for _, entry in ipairs(player_snapshot) do
        local player = entry.entity
        local player_index = entry.index
        local raw_spec_index = player.spec_index
        local decoded_spec_index = decode_spec_index(raw_spec_index)
        if decoded_spec_index ~= nil and #spec_refs < MAX_DEBUG_SPEC_REFS then
            spec_refs[#spec_refs + 1] = tostring(player_index)
                .. "->" .. tostring(raw_spec_index)
                .. "(" .. tostring(decoded_spec_index) .. ")"
        end
        if not player.is_npc
            and is_nonnegative_integer(player_index)
            and player_index ~= self_index
            and decoded_spec_index ~= nil
            and decoded_spec_index == self_index
        then
            spectator_count = spectator_count + 1
            if #self_matches < MAX_DEBUG_SPEC_REFS then
                self_matches[#self_matches + 1] = tostring(player_index)
            end
        end
    end

    debug_state.spectator_count = tostring(spectator_count)
    debug_state.spec_refs = list_to_text(spec_refs)
    debug_state.self_matches = list_to_text(self_matches)

    return {
        self_uid = self_uid,
        self_index = self_index,
        self_source = self_source,
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
    debug_state.target_plan = plan
    debug_state.current_plan = current_plan and tostring(current_plan) or "-"
    if current_plan == plan then
        last_failed_plan = nil
        last_failed_frame = -math.huge
        debug_state.switch_status = "当前已是目标方案"
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
        debug_state.switch_status = "等待失败重试"
        return
    end

    last_failed_plan = plan
    last_failed_frame = frame
    refresh_available_plans()
    debug_state.switch_status = "正在调用 config.switch"
    -- 某些运行时会在成功切换后返回 nil/false，因此不能用返回值判断结果。
    local switch_called, switch_error = pcall(config.switch, plan)
    local observed_plan = config.current()
    debug_state.current_plan = observed_plan and tostring(observed_plan) or "-"
    if observed_plan == plan then
        last_failed_plan = nil
        last_failed_frame = -math.huge
        debug_state.switch_status = "已生效（以 current 为准）"
        last_reported_count = spectator_count
        last_reported_plan = plan
        log.info(string.format("本人当前有 %d 名观战者，已切换参数方案 %s", spectator_count, plan))
        return
    end

    if not switch_called then
        debug_state.switch_status = "config.switch 调用异常"
        log.warn("观战切参失败：config.switch 调用异常：" .. tostring(switch_error))
        return
    end

    if plan_is_available(plan) == false then
        debug_state.switch_status = "方案不存在"
        log.warn("观战切参失败：不存在参数方案 " .. plan)
        return
    end

    -- current 可能在下一帧才发布新方案；本次不因返回值或瞬时旧值误报失败。
    debug_state.switch_status = "等待 current 更新"
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
        debug_state.status = "映射缺失"
        debug_state.switch_status = "未切换"
        if mapping_error ~= last_mapping_error then
            log.warn("观战切参暂缓：" .. mapping_error)
            last_mapping_error = mapping_error
        end
        return
    end

    last_mapping_error = nil
    switch_to_plan(target_plan, snapshot.spectator_count, frame)
end)

local DEBUG_FONT = draw.font("small")
local DEBUG_FONT_SIZE = 16.0
local last_debug_draw_frame = -1

local function build_debug_lines()
    return {
        "观战切参诊断",
        "状态: " .. debug_state.status,
        "本机 UID: " .. debug_state.local_uid,
        "local index: " .. debug_state.local_index
            .. " | local spec_index: " .. debug_state.local_spec_index,
        "self_base: " .. debug_state.self_base,
        "本人 index: " .. debug_state.resolved_index .. " (来源: " .. debug_state.resolved_by .. ")",
        string.format(
            "players: %d | UID 匹配: %d | base 匹配: %d",
            debug_state.player_total,
            debug_state.uid_matches,
            debug_state.base_matches
        ),
        "spec refs: " .. debug_state.spec_refs,
        "指向本人 index: " .. debug_state.self_matches,
        "观战人数: " .. debug_state.spectator_count .. " | 目标方案: " .. debug_state.target_plan,
        "当前方案: " .. debug_state.current_plan .. " | 切换: " .. debug_state.switch_status,
        "可用方案: " .. debug_state.available_plans,
        debug_state.error ~= "" and "错误: " .. debug_state.error or "",
    }
end

local function draw_debug_overlay()
    local screen_width, screen_height = draw.screen()
    local lines = build_debug_lines()
    local measure_options = { size = DEBUG_FONT_SIZE }
    if DEBUG_FONT ~= nil then
        measure_options.font = DEBUG_FONT
    end

    local max_width = 0
    for _, line in ipairs(lines) do
        local width = draw.measure(line, measure_options)
        if width > max_width then
            max_width = width
        end
    end

    local padding = 12.0
    local line_height = 21.0
    local panel_width = math.min(max_width + padding * 2, screen_width - 16.0)
    local text_top = screen_height * 0.10
    local panel_x = (screen_width - panel_width) * 0.5
    local panel_y = text_top - 8.0
    local panel_height = #lines * line_height + 8.0

    draw.rect(
        panel_x,
        panel_y,
        panel_x + panel_width,
        panel_y + panel_height,
        draw.rgba(0.02, 0.02, 0.04, 0.86),
        { filled = true, rounding = 5 }
    )

    local text_options = { size = DEBUG_FONT_SIZE, outline = true }
    if DEBUG_FONT ~= nil then
        text_options.font = DEBUG_FONT
    end
    for index, line in ipairs(lines) do
        local width = draw.measure(line, measure_options)
        local text_x = (screen_width - width) * 0.5
        local color = draw.rgba(0.88, 0.94, 1.0, 1.0)
        if index == 1 then
            color = draw.rgba(1.0, 0.85, 0.25, 1.0)
        elseif debug_state.error ~= "" or debug_state.switch_status == "config.switch 调用异常" then
            color = draw.rgba(1.0, 0.42, 0.42, 1.0)
        end
        draw.text(text_x, text_top + (index - 1) * line_height, color, line, text_options)
    end
end

-- free ESP 回调按玩家触发；同一帧只绘制一次，避免玩家数量造成重复叠字。
local debug_esp = esp.add("spectator_switch_debug", function(_, _)
    local frame = time.frame_count()
    if frame ~= last_debug_draw_frame then
        last_debug_draw_frame = frame
        draw_debug_overlay()
    end
    return nil
end, {
    label = "Spectator Switch Debug",
    kind = "free",
    dist = { 0.0, 100000.0 },
})

-- free 元素没有槽位拖拽入口，显式打开四种场景，确保诊断回调会执行。
if debug_esp ~= nil then
    debug_esp.enableds = { true, true, true, true }
end

log.success("观战人数自动切参脚本已注册，并启用屏幕诊断")
