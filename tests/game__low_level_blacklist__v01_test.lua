-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 模拟 HApex3.0 运行时，验证按队伍等级规则自动加入 black 的核心行为。
-- 覆盖本机 UID、team_num/squad_id、self_base 三重识别及身份未就绪时的封闭保护。
-- 验证成功事务生成 before/after/add 文件且不会生成 remove.json。
-- 验证审计日志落盘失败时恢复原始 rosters.json，避免留下半完成修改。
-- 验证加载阶段不会立即访问玩家快照，首次扫描延迟到 2000 帧后。
-- 运行：pnpm --package=fengari-node-cli dlx fengari tests/game__low_level_blacklist__v01_test.lua

local SCRIPT_PATH = "scripts/finished/game/game__low_level_blacklist__v01.lua"
local EXPECTED_TIMESTAMP_US = 1784000000250000
local EXPECTED_TIMESTAMP_TEXT = "1784000000250000"
local ENCODED_AFTER_2 = "{\n  \"black\": [\n    {}\n  ]\n}"
local ENCODED_AFTER_4 = "{\n    \"black\": [\n        {}\n    ]\n}"
local ENCODED_ADD_2 = "[\n  {}\n]"
local ENCODED_ADD_4 = "[\n    {}\n]"

local function run_scenario(options)
    local store = { ["conf/rosters.json"] = "BEFORE" }
    local rosters = options.rosters
    local event_handlers = {}
    local errors = {}
    local infos = {}
    local warnings = {}
    local notifications = {}

    file = {}

    function file.read(path)
        return store[path]
    end

    function file.write(path, content)
        if options.fail_final_add and path:match("/add%.json$") then
            return false
        end
        store[path] = content
        return true
    end

    function file.exists(path)
        return store[path] ~= nil
    end

    function file.remove(path)
        store[path] = nil
        return true
    end

    function file.rename(old_path, new_path)
        if options.fail_final_add and new_path:match("/add%.json$") then
            return false
        end
        if store[old_path] == nil or store[new_path] ~= nil then
            return false
        end
        store[new_path] = store[old_path]
        store[old_path] = nil
        return true
    end

    json = {
        decode = function(text)
            if text == "BEFORE" then
                return rosters
            end
            return nil, "unexpected JSON input"
        end,
        encode = function(value, pretty)
            assert(pretty == true)
            if value.black ~= nil then
                return ENCODED_AFTER_2
            end
            return ENCODED_ADD_2
        end,
    }

    time = {
        now = function()
            return 123.25
        end,
        frame_count = function()
            return 42
        end,
    }

    utils = {
        unix_time = function()
            return 1784000000
        end,
    }

    game = {
        localplayer = {
            platform_uid = options.localplayer_platform_uid,
            team_num = options.localplayer_team_num,
            squad_id = options.localplayer_squad_id,
            self_base = options.self_base,
            base = options.localplayer_base,
        },
        entities = { players = options.players },
    }

    function game:is_in_game()
        return options.is_in_game ~= false
    end

    event = {
        on = function(name, callback)
            event_handlers[name] = callback
        end,
    }

    log = {
        info = function(message)
            infos[#infos + 1] = message
        end,
        warn = function(message)
            warnings[#warnings + 1] = message
        end,
        success = function(_) end,
        error = function(message)
            errors[#errors + 1] = message
        end,
    }

    gui = {
        notify = {
            success = function(_, message)
                notifications[#notifications + 1] = { kind = "success", message = message }
            end,
            error = function(_, message)
                notifications[#notifications + 1] = { kind = "error", message = message }
            end,
        },
    }

    dofile(SCRIPT_PATH)

    local function advance_frames(count)
        for _ = 1, count do
            event_handlers.frame_update({})
        end
    end

    return {
        store = store,
        rosters = rosters,
        event_handlers = event_handlers,
        errors = errors,
        infos = infos,
        warnings = warnings,
        notifications = notifications,
        advance_frames = advance_frames,
    }
end

local existing_entry = {
    addtime = 1783999999000000,
    name = "Existing",
    uid = 1008278005183,
}

local npc_entity = setmetatable({ is_npc = true }, {
    __index = function(_, field)
        error("NPC 不应读取字段：" .. field)
    end,
})

local teammate_entity = setmetatable({ is_npc = false, is_teammate = true }, {
    __index = function(_, field)
        error("本人队伍不应读取字段：" .. field)
    end,
})

local self_entity = setmetatable({
    is_npc = false,
    is_teammate = false,
    platform_uid = "1008278005999",
}, {
    __index = function(_, field)
        error("玩家本人不应读取字段：" .. field)
    end,
})

local same_team_entity = setmetatable({
    is_npc = false,
    is_teammate = false,
    platform_uid = "2000000041",
    team_num = 7,
    squad_id = 70,
}, {
    __index = function(_, field)
        error("按本机队伍字段识别后不应读取字段：" .. field)
    end,
})

local self_base_fallback_entity = setmetatable({
    is_npc = false,
    is_teammate = false,
    platform_uid = "2000000042",
    team_num = 99,
    squad_id = 990,
    base = 111,
}, {
    __index = function(_, field)
        error("self_base 识别本人后不应读取字段：" .. field)
    end,
})

local function ignored_uid_entity(platform_uid)
    return setmetatable({
        is_npc = false,
        is_teammate = false,
        base = 999,
        platform_uid = platform_uid,
    }, {
        __index = function(_, field)
            error("范围外 UID 不应读取字段：" .. field)
        end,
    })
end

local success = run_scenario({
    -- 本人真实队伍为 team 7；死亡后 localplayer.base 指向正在观战的 team 20 玩家。
    localplayer_platform_uid = "1008278005999",
    localplayer_team_num = 7,
    localplayer_squad_id = 70,
    self_base = 111,
    localplayer_base = 222,
    rosters = {
        black = { existing_entry },
        celeb = { { legacy_shape = true } },
        pro = {},
        white = {},
    },
    players = {
        { name = "BoundaryMin", platform_uid = "2000000000", grade = 1, team_num = 50, is_npc = false, is_teammate = false },
        { name = "SoloLow", platform_uid = "2000000001", grade = 499, team_num = 10, is_npc = false, is_teammate = false },
        { name = "Boundary500", platform_uid = "2000000002", grade = 500, team_num = 10, is_npc = false, is_teammate = false },
        { name = "High", platform_uid = "2000000003", grade = 1500, team_num = 10, is_npc = false, is_teammate = false },
        { name = "PairA", platform_uid = "2000000011", grade = 100, team_num = 20, base = 222, is_npc = false, is_teammate = false },
        { name = "PairB", platform_uid = "2000000012", grade = 499, team_num = 20, is_npc = false, is_teammate = false },
        { name = "Third999", platform_uid = "2000000013", grade = 999, team_num = 20, is_npc = false, is_teammate = false },
        { name = "PairC", platform_uid = "2000000021", grade = 100, team_num = 30, is_npc = false, is_teammate = false },
        { name = "PairD", platform_uid = "2000000022", grade = 200, team_num = 30, is_npc = false, is_teammate = false },
        { name = "Third1000", platform_uid = "2000000023", grade = 1000, team_num = 30, is_npc = false, is_teammate = false },
        { name = "TwoPlayerA", platform_uid = "2000000031", grade = 100, team_num = 60, is_npc = false, is_teammate = false },
        { name = "TwoPlayerB", platform_uid = "2000000032", grade = 200, team_num = 60, is_npc = false, is_teammate = false },
        { name = "BoundaryMax", platform_uid = "1999999999999", grade = 1, team_num = 51, is_npc = false, is_teammate = false },
        npc_entity,
        self_entity,
        teammate_entity,
        same_team_entity,
        self_base_fallback_entity,
        ignored_uid_entity("1999999999"),
        ignored_uid_entity("2000000000000"),
        ignored_uid_entity("76561199610378140"),
    },
})

assert(type(success.event_handlers.frame_update) == "function")
assert(#success.rosters.black == 1)
assert(success.store["conf/rosters.json"] == "BEFORE")
assert(#success.notifications == 0)

success.advance_frames(1999)
assert(#success.rosters.black == 1)
assert(success.store["conf/rosters.json"] == "BEFORE")

success.advance_frames(1)
assert(#success.errors == 0)
assert(
    #success.notifications == 1 and success.notifications[1].kind == "success",
    table.concat(success.infos, " | ")
)
assert(#success.rosters.black == 11)

local added_names = {}
for index = 2, #success.rosters.black do
    local entry = success.rosters.black[index]
    added_names[entry.name] = true
    assert(entry.addtime == EXPECTED_TIMESTAMP_US)
end
assert(added_names.BoundaryMin)
assert(added_names.BoundaryMax)
assert(added_names.SoloLow)
assert(added_names.PairA and added_names.PairB and added_names.Third999)
assert(added_names.PairC and added_names.PairD)
assert(added_names.TwoPlayerA and added_names.TwoPlayerB)
assert(not added_names.Boundary500)
assert(not added_names.Third1000)
assert(success.store["conf/rosters.json"] == ENCODED_AFTER_4)

local success_log_dir = "conf/rosters_log/" .. EXPECTED_TIMESTAMP_TEXT
assert(success.store[success_log_dir .. "/before.json"] == "BEFORE")
assert(success.store[success_log_dir .. "/after.json"] == ENCODED_AFTER_4)
assert(success.store[success_log_dir .. "/add.json"] == ENCODED_ADD_4)
assert(success.store[success_log_dir .. "/remove.json"] == nil)
assert(success.store[success_log_dir .. "/after.pending.json"] == nil)
assert(success.store[success_log_dir .. "/add.pending.json"] == nil)

local rollback = run_scenario({
    fail_final_add = true,
    localplayer_platform_uid = "1008278005999",
    localplayer_team_num = 7,
    localplayer_squad_id = 70,
    self_base = 111,
    rosters = { black = {}, celeb = {}, pro = {}, white = {} },
    players = {
        { name = "Low", platform_uid = "1008278005180", grade = 499, team_num = 1, is_npc = false, is_teammate = false },
    },
})

assert(rollback.store["conf/rosters.json"] == "BEFORE")
assert(#rollback.errors == 0 and #rollback.notifications == 0)
rollback.advance_frames(2000)

assert(#rollback.errors == 1)
assert(#rollback.notifications == 1 and rollback.notifications[1].kind == "error")
assert(rollback.store["conf/rosters.json"] == "BEFORE")

local rollback_log_dir = "conf/rosters_log/" .. EXPECTED_TIMESTAMP_TEXT
assert(rollback.store[rollback_log_dir .. "/before.json"] == "BEFORE")
assert(rollback.store[rollback_log_dir .. "/after.json"] == nil)
assert(rollback.store[rollback_log_dir .. "/add.json"] == nil)
assert(rollback.store[rollback_log_dir .. "/after.pending.json"] == nil)
assert(rollback.store[rollback_log_dir .. "/add.pending.json"] == nil)

local protected_player = setmetatable({}, {
    __index = function(_, field)
        error("本机队伍身份未就绪时不应枚举玩家字段：" .. field)
    end,
})

local identity_unavailable = run_scenario({
    localplayer_platform_uid = "1008278005999",
    localplayer_team_num = 0,
    localplayer_squad_id = -1,
    self_base = 111,
    rosters = { black = {}, celeb = {}, pro = {}, white = {} },
    players = { protected_player },
})

identity_unavailable.advance_frames(2000)
assert(#identity_unavailable.errors == 0)
assert(#identity_unavailable.notifications == 0)
assert(#identity_unavailable.warnings == 1)
assert(identity_unavailable.store["conf/rosters.json"] == "BEFORE")
assert(#identity_unavailable.rosters.black == 0)

print("game__low_level_blacklist__v01 tests passed")
