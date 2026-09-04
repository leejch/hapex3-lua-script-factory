-- 模拟 HApex3.0 运行时，验证队友与敌人观战人数的互斥切参优先级。
-- 覆盖无队友时的敌人区间、有队友时忽略敌人数量、队友消失后的规则回退。
-- 同时验证未知阵营时保持当前方案，避免把未发布的 is_teammate 错算成敌人。
-- 运行：pnpm --package=fengari-node-cli dlx fengari tests/config__spectator_switch__v03_test.lua

local SCRIPT_PATH = "scripts/finished/config/config__spectator_switch__v03.lua"

local function spec_handle(index)
    return 65536 + index
end

local handlers, switches, warnings, infos = {}, {}, {}, {}
local frame, current_plan = 0, "manual"
local plans = {
    config = true,
    config_a = true,
    config_b = true,
    config_c = true,
    config_teammate_a = true,
    config_teammate_b = true,
    config_teammate_c = true,
}

local players = {
    { index = 42, platform_uid = "000111", is_npc = false, is_teammate = true, spec_index = -1 },
    { index = 50, platform_uid = "200", is_npc = false, is_teammate = false, spec_index = spec_handle(42) },
    { index = 51, platform_uid = "201", is_npc = false, is_teammate = false, spec_index = spec_handle(42) },
    { index = 52, platform_uid = "202", is_npc = false, is_teammate = false, spec_index = spec_handle(42) },
    { index = 60, platform_uid = "300", is_npc = false, is_teammate = true, spec_index = -1 },
    { index = 61, platform_uid = "301", is_npc = false, is_teammate = true, spec_index = -1 },
    { index = 62, platform_uid = "302", is_npc = false, is_teammate = true, spec_index = -1 },
}

game = { localplayer = { index = 9, platform_uid = "111" }, entities = { players = players } }
function game:is_in_game() return true end

config = {
    current = function() return current_plan end,
    list = function()
        local result = {}
        for plan in pairs(plans) do result[#result + 1] = plan end
        return result
    end,
    switch = function(plan)
        switches[#switches + 1] = plan
        if plans[plan] then current_plan = plan end
        return plans[plan] == true
    end,
}

time = { frame_count = function() return frame end }
event = { on = function(name, callback) handlers[name] = callback end }
log = {
    info = function(message) infos[#infos + 1] = message end,
    success = function(message) infos[#infos + 1] = message end,
    warn = function(message) warnings[#warnings + 1] = message end,
    error = function(message) error(message) end,
}

dofile(SCRIPT_PATH)

local function advance()
    frame = frame + 1
    handlers.frame_update({ delta_time = 1 / 144 })
end

-- 没有队友观战时，3 名敌人必须使用敌人 3+ 区间。
advance()
assert(current_plan == "config_c")
assert(switches[#switches] == "config_c")

-- 即使仍有 3 名敌人，只要 1 名队友开始观战，就只能使用队友 1 人区间。
players[5].spec_index = spec_handle(42)
advance()
assert(current_plan == "config_teammate_a")
assert(switches[#switches] == "config_teammate_a")

-- 敌人数量变化不能覆盖处于生效状态的队友规则。
players[2].spec_index = -1
players[3].spec_index = -1
players[4].spec_index = -1
advance()
assert(current_plan == "config_teammate_a")

players[6].spec_index = spec_handle(42)
advance()
assert(current_plan == "config_teammate_b")
players[7].spec_index = spec_handle(42)
advance()
assert(current_plan == "config_teammate_c")

-- 最后一名队友停止观战后，规则立即回退到敌人分支的 0 人基础方案。
players[5].spec_index, players[6].spec_index, players[7].spec_index = -1, -1, -1
advance()
assert(current_plan == "config")

-- 正在观战但阵营快照未知时暂停切参，不能默认归入敌人分支。
players[2].is_teammate = nil
players[2].spec_index = spec_handle(42)
advance()
assert(current_plan == "config")
assert(#warnings == 1)
assert(warnings[1]:find("is_teammate 尚未可用", 1, true) ~= nil)

-- 日志同时报告两类人数，便于核对实际采用的优先级。
local has_split_count = false
for _, message in ipairs(infos) do
    has_split_count = has_split_count
        or message:find("队友观战 1 人、敌人观战 3 人", 1, true) ~= nil
end
assert(has_split_count)

print("config__spectator_switch__v03 tests passed")
