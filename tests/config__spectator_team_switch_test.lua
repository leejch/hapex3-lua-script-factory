-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 模拟两种观战切参脚本，验证队伍过滤、本人身份和异常情况下的切参行为。
-- 测试运行器提供 SCRIPT_SOURCE 与 EXPECT_TEAMMATE，并分别加载两个脚本。

local handler, current, switches, warnings = nil, "manual", {}, {}
local plans = { "config", "config_a", "config_b", "config_c" }
local players = {
    { index = 42, base = 500, platform_uid = "111", team_num = 2, is_npc = false, spec_index = -1 },
    { index = 9, base = 900, platform_uid = "999", team_num = 8, is_npc = false, spec_index = -1 },
    { index = 10, team_num = 2, is_npc = false, spec_index = 65536 + 42 },
    { index = 11, team_num = 8, is_npc = false, spec_index = 65536 + 42 },
    { index = 12, team_num = 8, is_npc = false, spec_index = 65536 + 42 },
    { index = 13, team_num = 2, is_npc = false, spec_index = 65536 + 9 },
    { index = 14, team_num = 2, is_npc = true, spec_index = 65536 + 42 },
}
game = { localplayer = { index = 9, base = 900, self_base = 500, platform_uid = "999", team_num = 8 }, entities = { players = players } }
function game:is_in_game() return true end
event = { on = function(_, fn) handler = fn end }
time = { frame_count = function() return 200 end }
log = { success = function() end, warn = function(s) warnings[#warnings + 1] = s end, error = function(s) error(s) end }
config = {
    list = function() return plans end,
    current = function() return current end,
    switch = function(p) switches[#switches + 1] = p; current = p end,
}
assert(load(SCRIPT_SOURCE))()
handler()
assert(current == (EXPECT_TEAMMATE and "config_a" or "config_b"))
players[3].spec_index = -1
players[4].spec_index = -1
players[5].spec_index = -1
handler()
assert(current == "config")
players[3].spec_index = 65536 + 42
players[3].team_num = nil
handler()
assert(current == "config" and #warnings == 1)
players[3].team_num = 2
players[1].team_num = nil
handler()
assert(current == "config" and #warnings == 2)
players[1].team_num = 2
plans = { "config" }
players[4].spec_index = 65536 + 42
handler()
assert(current == "config" and #warnings == 3)
assert(#switches == 2)
