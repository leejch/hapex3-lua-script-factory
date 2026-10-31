-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 自动扫描 HApex3.0 当前对局，按队伍等级条件把玩家加入 black 名单。
-- 使用本机 platform_uid 识别本人，并以本机 team_num/squad_id 排除真实本队。
-- 仅处理指定 UID 范围；每次修改都保留操作前、操作后和新增记录备份。
-- 本机身份未就绪时整次扫描取消；输出 JSON 使用每级 4 个空格缩进。

local ROSTERS_PATH = "conf/rosters.json"
local LOG_ROOT = "conf/rosters_log"

-- 等级低于 GRADE_LIMIT 加入黑名单
local GRADE_LIMIT = 500
-- 若队伍有2人低于 GRADE_LIMIT，且第3人低于 GRADE_LIMIT_2，则第3人连坐，也进黑名单
local GRADE_LIMIT_2 = 1000

local UID_MIN = 2000000000
local UID_MAX = 1999999999999
local UID_MIN_TEXT = "2000000000"
local UID_MAX_TEXT = "1999999999999"
local INITIAL_SCAN_DELAY_FRAMES = 2000
local SCAN_INTERVAL_FRAMES = 5000
local MAX_SAFE_INTEGER = 9007199254740991

local operation_running = false
local last_timestamp_us = 0
local frames_since_load = 0

local function is_positive_integer(value)
    return type(value) == "number"
        and value > 0
        and value == math.floor(value)
end

local function uid_in_processing_range(uid)
    return is_positive_integer(uid) and uid >= UID_MIN and uid <= UID_MAX
end

local function uid_text_in_processing_range(uid_text)
    local length = #uid_text
    if length < #UID_MIN_TEXT or length > #UID_MAX_TEXT then
        return false
    end
    if length == #UID_MIN_TEXT and uid_text < UID_MIN_TEXT then
        return false
    end
    if length == #UID_MAX_TEXT and uid_text > UID_MAX_TEXT then
        return false
    end
    return true
end

local function canonical_uid_text(value)
    if type(value) ~= "string" or not value:match("^%d+$") then
        return nil
    end

    local canonical = value:gsub("^0+", "")
    if canonical == "" then
        return "0"
    end
    return canonical
end

local function integer_to_decimal(value)
    if not is_positive_integer(value) then
        return nil
    end

    local digits = {}
    repeat
        local digit = value % 10
        digits[#digits + 1] = string.char(48 + digit)
        value = math.floor(value / 10)
    until value == 0

    local left = 1
    local right = #digits
    while left < right do
        digits[left], digits[right] = digits[right], digits[left]
        left = left + 1
        right = right - 1
    end

    return table.concat(digits)
end

local function is_array(value)
    if type(value) ~= "table" then
        return false
    end

    local count = 0
    local max_index = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return false
        end
        count = count + 1
        if key > max_index then
            max_index = key
        end
    end

    return max_index == count
end

local function validate_rosters(rosters)
    if type(rosters) ~= "table" then
        return false, "根节点不是 JSON 对象"
    end

    if not is_array(rosters.black) then
        return false, "black 字段不是连续数组"
    end

    for index, entry in ipairs(rosters.black) do
        local uid = type(entry) == "table" and entry.uid or nil
        if uid_in_processing_range(uid)
            and (type(entry.addtime) ~= "number" or type(entry.name) ~= "string")
        then
            return false, "black[" .. index .. "] 的范围内 UID 记录不符合 addtime/name/uid 格式"
        end
    end

    return true
end

local function load_rosters()
    local raw = file.read(ROSTERS_PATH)
    if raw == nil then
        return nil, nil, "无法读取 " .. ROSTERS_PATH .. "；已取消操作"
    end

    local rosters, decode_error = json.decode(raw)
    if rosters == nil then
        return nil, nil, "名单 JSON 解析失败：" .. tostring(decode_error)
    end

    local valid, validation_error = validate_rosters(rosters)
    if not valid then
        return nil, nil, "名单格式校验失败：" .. validation_error
    end

    return rosters, raw, nil
end

local function json_encode_4(value)
    local encoded = json.encode(value, true)
    if encoded == "null" then
        return encoded
    end

    -- 官方 pretty 输出为 2 空格；只放大行首缩进，不会改动 JSON 字符串内容。
    return (encoded:gsub("\n( +)", function(indent)
        return "\n" .. string.rep(" ", #indent * 2)
    end))
end

local function platform_uid_to_number(platform_uid)
    local canonical = canonical_uid_text(platform_uid)
    if canonical == nil then
        return nil, "invalid"
    end

    if not uid_text_in_processing_range(canonical) then
        return nil, "out_of_range"
    end

    local uid = tonumber(canonical)
    if not is_positive_integer(uid) or uid > MAX_SAFE_INTEGER then
        return nil, "invalid"
    end

    -- 安全整数范围内仍校验十进制往返，避免写入已经发生精度损失的 UID。
    if integer_to_decimal(uid) ~= canonical then
        return nil, "invalid"
    end

    return uid, nil
end

local function read_local_identity()
    if not game:is_in_game() then
        return nil, "当前不在对局中"
    end

    local localplayer = game.localplayer
    local team_num = is_positive_integer(localplayer.team_num) and localplayer.team_num or nil
    local squad_id = is_positive_integer(localplayer.squad_id) and localplayer.squad_id or nil

    -- 无法确认本人队伍时绝不继续，避免把本人或队友当成敌方候选人。
    if team_num == nil and squad_id == nil then
        return nil, "game.localplayer.team_num/squad_id 尚未提供有效的本人队伍身份"
    end

    local self_base = localplayer.self_base
    if not is_positive_integer(self_base) then
        self_base = nil
    end

    return {
        platform_uid = canonical_uid_text(localplayer.platform_uid),
        team_num = team_num,
        squad_id = squad_id,
        self_base = self_base,
    }, nil
end

local function collect_candidates()
    local teams = {}
    local seen_uids = {}
    local stats = {
        total = 0,
        npc = 0,
        self = 0,
        teammate = 0,
        uid_out_of_range = 0,
        invalid_name = 0,
        invalid_platform_uid = 0,
        invalid_grade = 0,
        invalid_team = 0,
        grade_not_below_limit = 0,
        duplicate_uid = 0,
        teams = 0,
    }
    local local_identity, identity_error = read_local_identity()
    if local_identity == nil then
        return nil, stats, identity_error
    end

    stats.local_platform_uid = local_identity.platform_uid or "unavailable"
    stats.local_team_num = local_identity.team_num or "unavailable"
    stats.local_squad_id = local_identity.squad_id or "unavailable"

    for _, player in pairs(game.entities.players) do
        stats.total = stats.total + 1

        if player.is_npc then
            stats.npc = stats.npc + 1
        elseif player.is_teammate then
            -- 官方字段可直接提前排除明确标记为本人队友的实体。
            stats.teammate = stats.teammate + 1
        else
            local platform_uid = player.platform_uid
            local platform_uid_text = canonical_uid_text(platform_uid)

            if platform_uid_text ~= nil
                and local_identity.platform_uid ~= nil
                and platform_uid_text == local_identity.platform_uid
            then
                -- platform_uid 是官方字符串身份字段，优先于内存基址识别真实本人。
                stats.self = stats.self + 1
            else
                local uid, uid_error = platform_uid_to_number(platform_uid)

                if uid_error == "out_of_range" then
                    -- 范围外 UID 不再读取队伍、昵称或等级，也不参与任何名单判断。
                    stats.uid_out_of_range = stats.uid_out_of_range + 1
                elseif uid == nil then
                    stats.invalid_platform_uid = stats.invalid_platform_uid + 1
                else
                    local team_num = is_positive_integer(player.team_num) and player.team_num or nil
                    local squad_id = is_positive_integer(player.squad_id) and player.squad_id or nil
                    local has_comparable_team = false
                    local belongs_to_local_team = false

                    if local_identity.team_num ~= nil and team_num ~= nil then
                        has_comparable_team = true
                        belongs_to_local_team = team_num == local_identity.team_num
                    end
                    if local_identity.squad_id ~= nil and squad_id ~= nil then
                        has_comparable_team = true
                        belongs_to_local_team = belongs_to_local_team
                            or squad_id == local_identity.squad_id
                    end

                    if belongs_to_local_team then
                        -- 这里比较的是 localplayer 的固定本机队伍字段，不使用观战目标的 base。
                        stats.teammate = stats.teammate + 1
                    elseif not has_comparable_team then
                        -- 无法证明该实体不属于本队时采取封闭策略，直接忽略。
                        stats.invalid_team = stats.invalid_team + 1
                    elseif local_identity.self_base ~= nil
                        and player.base == local_identity.self_base
                    then
                        -- UID 暂未解析时，self_base 仍可作为真实本人的额外兜底。
                        stats.self = stats.self + 1
                    else
                        local name = player.name
                        local grade = player.grade
                        local team_key = team_num ~= nil
                            and "team:" .. team_num
                            or "squad:" .. squad_id

                        if type(name) ~= "string" or name == "" then
                            stats.invalid_name = stats.invalid_name + 1
                        elseif type(grade) ~= "number" or grade < 0 or grade ~= math.floor(grade) then
                            stats.invalid_grade = stats.invalid_grade + 1
                        elseif seen_uids[uid] then
                            stats.duplicate_uid = stats.duplicate_uid + 1
                        else
                            seen_uids[uid] = true
                            if grade >= GRADE_LIMIT then
                                stats.grade_not_below_limit = stats.grade_not_below_limit + 1
                            end

                            local team = teams[team_key]
                            if team == nil then
                                team = {}
                                teams[team_key] = team
                                stats.teams = stats.teams + 1
                            end
                            team[#team + 1] = {
                                name = name,
                                uid = uid,
                                grade = grade,
                            }
                        end
                    end
                end
            end
        end
    end

    local candidates = {}
    for _, team in pairs(teams) do
        local primary_count = 0
        for _, member in ipairs(team) do
            if member.grade < GRADE_LIMIT then
                primary_count = primary_count + 1
            end
        end

        if primary_count >= 1 then
            for _, member in ipairs(team) do
                if member.grade < GRADE_LIMIT then
                    candidates[#candidates + 1] = member
                end
            end
        end

        if #team == 3 and primary_count == 2 then
            for _, member in ipairs(team) do
                if member.grade >= GRADE_LIMIT and member.grade < GRADE_LIMIT_2 then
                    candidates[#candidates + 1] = member
                end
            end
        end
    end

    table.sort(candidates, function(left, right)
        if left.uid == right.uid then
            return left.name < right.name
        end
        return left.uid < right.uid
    end)

    return candidates, stats
end

local function next_timestamp_us()
    -- 官方接口只提供秒级 Unix 时间；用单调时钟的小数部分补足微秒位并保证本次脚本内递增。
    local monotonic = time.now()
    local subsecond_us = math.floor((monotonic - math.floor(monotonic)) * 1000000)
    local timestamp_us = math.floor(utils.unix_time() * 1000000.0 + subsecond_us)

    if timestamp_us <= last_timestamp_us then
        timestamp_us = last_timestamp_us + 1
    end

    local timestamp_text = integer_to_decimal(timestamp_us)
    while file.exists(LOG_ROOT .. "/" .. timestamp_text .. "/before.json") do
        timestamp_us = timestamp_us + 1
        timestamp_text = integer_to_decimal(timestamp_us)
    end

    last_timestamp_us = timestamp_us
    return timestamp_us, timestamp_text
end

local function write_verified(path, content)
    if not file.write(path, content) then
        return false, "写入失败：" .. path
    end

    if file.read(path) ~= content then
        return false, "写入后回读不一致：" .. path
    end

    return true, nil
end

local function remove_if_exists(path)
    if file.exists(path) then
        file.remove(path)
    end
end

local function restore_rosters(before_json)
    local restored = write_verified(ROSTERS_PATH, before_json)
    return restored == true
end

local function promote_log_file(pending_path, final_path, expected_content)
    if file.rename(pending_path, final_path) and file.read(final_path) == expected_content then
        return true
    end

    local written = write_verified(final_path, expected_content)
    if written then
        remove_if_exists(pending_path)
        return true
    end

    return false
end

local function commit_roster_update(before_json, after_json, additions_json, timestamp_text)
    local log_dir = LOG_ROOT .. "/" .. timestamp_text
    local before_path = log_dir .. "/before.json"
    local after_pending_path = log_dir .. "/after.pending.json"
    local add_pending_path = log_dir .. "/add.pending.json"
    local after_path = log_dir .. "/after.json"
    local add_path = log_dir .. "/add.json"

    local ok, operation_error = write_verified(before_path, before_json)
    if not ok then
        return false, "操作前备份失败，名单未修改：" .. operation_error
    end

    ok, operation_error = write_verified(after_pending_path, after_json)
    if not ok then
        remove_if_exists(after_pending_path)
        return false, "操作后备份预写失败，名单未修改：" .. operation_error
    end

    ok, operation_error = write_verified(add_pending_path, additions_json)
    if not ok then
        remove_if_exists(after_pending_path)
        remove_if_exists(add_pending_path)
        return false, "新增记录预写失败，名单未修改：" .. operation_error
    end

    -- 备份完成后再次比较源文件，避免覆盖扫描期间由其他程序写入的新内容。
    if file.read(ROSTERS_PATH) ~= before_json then
        remove_if_exists(after_pending_path)
        remove_if_exists(add_pending_path)
        return false, "名单在操作期间被其他程序修改，已取消本次写入；操作前备份位于 " .. log_dir
    end

    ok, operation_error = write_verified(ROSTERS_PATH, after_json)
    if not ok then
        local restored = restore_rosters(before_json)
        remove_if_exists(after_pending_path)
        remove_if_exists(add_pending_path)
        return false, operation_error .. "；恢复原名单=" .. tostring(restored)
    end

    local after_saved = promote_log_file(after_pending_path, after_path, after_json)
    local additions_saved = promote_log_file(add_pending_path, add_path, additions_json)
    if not after_saved or not additions_saved then
        local restored = restore_rosters(before_json)
        if restored then
            remove_if_exists(after_path)
            remove_if_exists(add_path)
        end
        remove_if_exists(after_pending_path)
        remove_if_exists(add_pending_path)
        return false, "名单日志落盘不完整；已尝试恢复原名单，恢复结果=" .. tostring(restored)
    end

    return true, log_dir
end

local function scan_and_update()
    local candidates, stats, identity_error = collect_candidates()
    if candidates == nil then
        log.warn("[low-level-blacklist] 为保护本人及本队，本次扫描已取消：" .. identity_error)
        return
    end

    log.info(
        "[low-level-blacklist] scan frame=" .. time.frame_count()
        .. " identity(uid=" .. stats.local_platform_uid
        .. ",team_num=" .. stats.local_team_num
        .. ",squad_id=" .. stats.local_squad_id .. ")"
        .. " players=" .. stats.total
        .. " teams=" .. stats.teams
        .. " candidates=" .. #candidates
        .. " skipped(npc=" .. stats.npc
        .. ",self=" .. stats.self
        .. ",teammate=" .. stats.teammate
        .. ",uid_out_of_range=" .. stats.uid_out_of_range
        .. ",invalid_name=" .. stats.invalid_name
        .. ",invalid_platform_uid=" .. stats.invalid_platform_uid
        .. ",invalid_grade=" .. stats.invalid_grade
        .. ",invalid_team=" .. stats.invalid_team
        .. ",grade_not_below_500=" .. stats.grade_not_below_limit
        .. ",duplicate_uid=" .. stats.duplicate_uid .. ")"
    )

    if #candidates == 0 then
        return
    end

    local rosters, before_json, load_error = load_rosters()
    if rosters == nil then
        log.error("[low-level-blacklist] " .. load_error)
        gui.notify:error(load_error, 5)
        return
    end

    local known_black_uids = {}
    for _, entry in ipairs(rosters.black) do
        if type(entry) == "table" and uid_in_processing_range(entry.uid) then
            known_black_uids[entry.uid] = true
        end
    end

    local new_candidates = {}
    for _, candidate in ipairs(candidates) do
        if not known_black_uids[candidate.uid] then
            known_black_uids[candidate.uid] = true
            new_candidates[#new_candidates + 1] = candidate
        end
    end

    if #new_candidates == 0 then
        log.info("[low-level-blacklist] 所有符合条件的玩家都已存在于 black，名单未修改")
        return
    end

    local timestamp_us, timestamp_text = next_timestamp_us()
    local additions = {}
    for _, candidate in ipairs(new_candidates) do
        local entry = {
            addtime = timestamp_us,
            name = candidate.name,
            uid = candidate.uid,
        }
        additions[#additions + 1] = entry
        rosters.black[#rosters.black + 1] = entry
    end

    local after_json = json_encode_4(rosters)
    local additions_json = json_encode_4(additions)
    if after_json == "null" or additions_json == "null" then
        local message = "名单 JSON 序列化失败，名单未修改"
        log.error("[low-level-blacklist] " .. message)
        gui.notify:error(message, 5)
        return
    end

    local committed, result = commit_roster_update(
        before_json,
        after_json,
        additions_json,
        timestamp_text
    )
    if not committed then
        log.error("[low-level-blacklist] " .. result)
        gui.notify:error(result, 6)
        return
    end

    local message = "已按队伍等级规则将 " .. #additions .. " 名玩家加入 black"
    log.success("[low-level-blacklist] " .. message .. "；日志目录=" .. result)
    gui.notify:success(message, 4)
end

local function run_scan_safely()
    if operation_running then
        return
    end

    operation_running = true
    local ok, runtime_error = pcall(scan_and_update)
    operation_running = false

    if not ok then
        local message = "扫描发生 Lua 错误，已停止本次操作：" .. tostring(runtime_error)
        log.error("[low-level-blacklist] " .. message)
        gui.notify:error(message, 6)
    end
end

event.on("frame_update", function()
    frames_since_load = frames_since_load + 1
    if frames_since_load == INITIAL_SCAN_DELAY_FRAMES
        or (frames_since_load > INITIAL_SCAN_DELAY_FRAMES
            and (frames_since_load - INITIAL_SCAN_DELAY_FRAMES) % SCAN_INTERVAL_FRAMES == 0)
    then
        run_scan_safely()
    end
end)

log.success("低等级玩家自动 black 名单脚本已注册；首次扫描将在 2000 帧后进行")
