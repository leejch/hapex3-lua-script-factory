-- 模拟 HApex3.0 运行时，验证低等级玩家自动加入 black 名单的核心行为。
-- 覆盖最新版 game 字段、500 级边界、NPC 过滤、重复 UID 和微秒时间戳。
-- 验证成功事务生成 before/after/add 文件且不会生成 remove.json。
-- 验证审计日志落盘失败时恢复原始 rosters.json，避免留下半完成修改。
-- 运行：pnpm --package=fengari-node-cli dlx fengari tests/game__low_level_blacklist__v01_test.lua

local SCRIPT_PATH = "scripts/finished/game/game__low_level_blacklist__v01.lua"
local EXPECTED_TIMESTAMP_US = 1784000000250000

local function run_scenario(options)
    local store = { ["conf/rosters.json"] = "BEFORE" }
    local rosters = options.rosters
    local event_handlers = {}
    local errors = {}
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
        encode = function(value)
            if value.black ~= nil then
                return "AFTER"
            end
            return "ADD"
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
        entities = { players = options.players },
    }

    function game:is_in_game()
        return true
    end

    event = {
        on = function(name, callback)
            event_handlers[name] = callback
        end,
    }

    log = {
        info = function(_) end,
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

    return {
        store = store,
        rosters = rosters,
        event_handlers = event_handlers,
        errors = errors,
        notifications = notifications,
    }
end

local existing_entry = {
    addtime = 1783999999000000,
    name = "Existing",
    uid = 1008278005183,
}

local success = run_scenario({
    rosters = { black = { existing_entry }, celeb = {}, pro = {}, white = {} },
    players = {
        { name = "Low", platform_uid = "1008278005180", grade = 499, is_npc = false },
        { name = "Boundary", platform_uid = "1008278005181", grade = 500, is_npc = false },
        { name = "Bot", platform_uid = "1008278005182", grade = 1, is_npc = true },
        { name = "Existing", platform_uid = "1008278005183", grade = 1, is_npc = false },
    },
})

assert(type(success.event_handlers.frame_update) == "function")
assert(#success.errors == 0)
assert(#success.notifications == 1 and success.notifications[1].kind == "success")
assert(#success.rosters.black == 2)
assert(success.rosters.black[2].name == "Low")
assert(success.rosters.black[2].uid == 1008278005180)
assert(success.rosters.black[2].addtime == EXPECTED_TIMESTAMP_US)
assert(success.store["conf/rosters.json"] == "AFTER")

local success_log_dir = "conf/rosters_log/" .. string.format("%.0f", EXPECTED_TIMESTAMP_US)
assert(success.store[success_log_dir .. "/before.json"] == "BEFORE")
assert(success.store[success_log_dir .. "/after.json"] == "AFTER")
assert(success.store[success_log_dir .. "/add.json"] == "ADD")
assert(success.store[success_log_dir .. "/remove.json"] == nil)
assert(success.store[success_log_dir .. "/after.pending.json"] == nil)
assert(success.store[success_log_dir .. "/add.pending.json"] == nil)

local rollback = run_scenario({
    fail_final_add = true,
    rosters = { black = {}, celeb = {}, pro = {}, white = {} },
    players = {
        { name = "Low", platform_uid = "1008278005180", grade = 499, is_npc = false },
    },
})

assert(#rollback.errors == 1)
assert(#rollback.notifications == 1 and rollback.notifications[1].kind == "error")
assert(rollback.store["conf/rosters.json"] == "BEFORE")

local rollback_log_dir = "conf/rosters_log/" .. string.format("%.0f", EXPECTED_TIMESTAMP_US)
assert(rollback.store[rollback_log_dir .. "/before.json"] == "BEFORE")
assert(rollback.store[rollback_log_dir .. "/after.json"] == nil)
assert(rollback.store[rollback_log_dir .. "/add.json"] == nil)
assert(rollback.store[rollback_log_dir .. "/after.pending.json"] == nil)
assert(rollback.store[rollback_log_dir .. "/add.pending.json"] == nil)

print("game__low_level_blacklist__v01 tests passed")
