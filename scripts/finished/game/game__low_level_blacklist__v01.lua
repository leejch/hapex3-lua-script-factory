-- 自动扫描 HApex3.0 当前对局，并把等级低于 500 的真实玩家加入 black 名单。
-- 使用 game.entities.players 的 platform_uid、grade 与 name 字段读取玩家资料。
-- 每次实际修改 conf/rosters.json 都保留操作前、操作后和新增记录的可回读备份。
-- 本脚本只执行新增，不会删除或移动现有名单记录。

local ROSTERS_PATH = "conf/rosters.json"
local LOG_ROOT = "conf/rosters_log"
local GRADE_LIMIT = 500
local SCAN_INTERVAL_FRAMES = 600
local MAX_SAFE_INTEGER = 9007199254740991

local CATEGORIES = { "black", "celeb", "pro", "white" }
local operation_running = false
local last_timestamp_us = 0

local function is_positive_integer(value)
    return type(value) == "number"
        and value > 0
        and value == math.floor(value)
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

    for _, category in ipairs(CATEGORIES) do
        local entries = rosters[category]
        if not is_array(entries) then
            return false, category .. " 字段不是连续数组"
        end

        for index, entry in ipairs(entries) do
            if type(entry) ~= "table"
                or type(entry.addtime) ~= "number"
                or type(entry.name) ~= "string"
                or not is_positive_integer(entry.uid)
                or entry.uid > MAX_SAFE_INTEGER
            then
                return false, category .. "[" .. index .. "] 不符合 addtime/name/uid 格式"
            end
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

local function platform_uid_to_number(platform_uid)
    if type(platform_uid) ~= "string" or not platform_uid:match("^%d+$") then
        return nil
    end

    local canonical = platform_uid:gsub("^0+", "")
    if canonical == "" then
        canonical = "0"
    end

    local uid = tonumber(canonical)
    if not is_positive_integer(uid) or uid > MAX_SAFE_INTEGER then
        return nil
    end

    -- 名单要求 uid 为 JSON 数字，因此拒绝任何转成 number 后会丢失精度的 UID。
    if string.format("%.0f", uid) ~= canonical then
        return nil
    end

    return uid, canonical
end

local function collect_candidates()
    local candidates = {}
    local seen_uids = {}
    local stats = {
        total = 0,
        npc = 0,
        invalid_name = 0,
        invalid_platform_uid = 0,
        invalid_grade = 0,
        grade_not_below_limit = 0,
        duplicate_uid = 0,
    }

    for _, player in pairs(game.entities.players) do
        stats.total = stats.total + 1

        local name = player.name
        local platform_uid = player.platform_uid
        local grade = player.grade
        local uid, uid_key = platform_uid_to_number(platform_uid)

        if player.is_npc then
            stats.npc = stats.npc + 1
        elseif type(name) ~= "string" or name == "" then
            stats.invalid_name = stats.invalid_name + 1
        elseif uid == nil then
            stats.invalid_platform_uid = stats.invalid_platform_uid + 1
        elseif type(grade) ~= "number" or grade < 0 or grade ~= math.floor(grade) then
            stats.invalid_grade = stats.invalid_grade + 1
        elseif grade >= GRADE_LIMIT then
            stats.grade_not_below_limit = stats.grade_not_below_limit + 1
        elseif seen_uids[uid_key] then
            stats.duplicate_uid = stats.duplicate_uid + 1
        else
            seen_uids[uid_key] = true
            candidates[#candidates + 1] = {
                name = name,
                uid = uid,
                uid_key = uid_key,
            }
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
    local timestamp_us = utils.unix_time() * 1000000.0 + subsecond_us

    if timestamp_us <= last_timestamp_us then
        timestamp_us = last_timestamp_us + 1
    end

    while file.exists(LOG_ROOT .. "/" .. string.format("%.0f", timestamp_us) .. "/before.json") do
        timestamp_us = timestamp_us + 1
    end

    last_timestamp_us = timestamp_us
    return timestamp_us
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

local function commit_roster_update(before_json, after_json, additions_json, timestamp_us)
    local log_dir = LOG_ROOT .. "/" .. string.format("%.0f", timestamp_us)
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
    if not game:is_in_game() then
        return
    end

    local candidates, stats = collect_candidates()
    log.info(
        "[low-level-blacklist] scan frame=" .. time.frame_count()
        .. " players=" .. stats.total
        .. " candidates=" .. #candidates
        .. " skipped(npc=" .. stats.npc
        .. ",invalid_name=" .. stats.invalid_name
        .. ",invalid_platform_uid=" .. stats.invalid_platform_uid
        .. ",invalid_grade=" .. stats.invalid_grade
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
        known_black_uids[string.format("%.0f", entry.uid)] = true
    end

    local new_candidates = {}
    for _, candidate in ipairs(candidates) do
        if not known_black_uids[candidate.uid_key] then
            known_black_uids[candidate.uid_key] = true
            new_candidates[#new_candidates + 1] = candidate
        end
    end

    if #new_candidates == 0 then
        log.info("[low-level-blacklist] 所有符合条件的玩家都已存在于 black，名单未修改")
        return
    end

    local timestamp_us = next_timestamp_us()
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

    local after_json = json.encode(rosters, true)
    local additions_json = json.encode(additions, true)
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
        timestamp_us
    )
    if not committed then
        log.error("[low-level-blacklist] " .. result)
        gui.notify:error(result, 6)
        return
    end

    local message = "已将 " .. #additions .. " 名等级低于 500 的玩家加入 black"
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
    if time.frame_count() % SCAN_INTERVAL_FRAMES == 0 then
        run_scan_safely()
    end
end)

run_scan_safely()
log.success("低等级玩家自动 black 名单脚本已注册")
