-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 模拟三个独立切参脚本，验证距离边界、倍率边界及全部二十八种组合。
-- 覆盖收镜优先、旧武器数据、目标筛选、缺失配置和切换失败限频。
-- 禁止访问 draw 与 esp，确保正式脚本没有残留调试绘制。
-- 运行：pnpm --package=fengari-node-cli dlx fengari tests/config__auto_switch_variants__v01_test.lua

local ROOT = "scripts/finished/config/config__"
local PATHS = {
    distance = ROOT .. "distance_switch__v01.lua",
    scope = ROOT .. "scope_switch__v01.lua",
    combined = ROOT .. "distance_scope_switch__v01.lua",
}
local DISTANCES = { { 20, "0_50" }, { 80, "50_100" }, { 150, "100_200" }, { 300, "200_inf" } }
local SCOPES = { { 50, "1x" }, { 40, "2x" }, { 25, "3x" }, { 20, "4x" },
    { 15, "6x" }, { 10, "8x" }, { 5, "10x" } }
local PLANS = {}
for _, distance in ipairs(DISTANCES) do
    PLANS[#PLANS + 1] = "config_" .. distance[2]
    for _, scope in ipairs(SCOPES) do
        PLANS[#PLANS + 1] = "config_" .. distance[2] .. "_" .. scope[2]
    end
end
for _, scope in ipairs(SCOPES) do PLANS[#PLANS + 1] = "config_" .. scope[2] end

local function enemy(distance, yaw, pitch)
    yaw, pitch = math.rad(yaw or 0), math.rad(pitch or 0)
    return {
        index = 2, distance = distance, in_screen = true,
        is_dead = false, is_down = false, is_teammate = false,
        origin = { x = 100 * math.cos(pitch) * math.cos(yaw),
            y = 100 * math.cos(pitch) * math.sin(yaw), z = -100 * math.sin(pitch) },
    }
end

local function scenario(kind, players, opts)
    opts = opts or {}
    local state = { current = "manual", switches = {}, warnings = {}, frame = 0 }
    local lp = {
        index = 1, is_dead = false, is_down = false,
        camera_origin = { x = 0, y = 0, z = 0 }, view_angle = { x = 0, y = 0 },
        is_zooming = true, target_zoom_fov = 40, weapon_fields_stale = false,
    }
    game = { localplayer = lp, entities = { players = players or {} },
        is_in_game = function() return opts.in_game ~= false end }
    local callback
    event = { on = function(name, fn) assert(name == "frame_update"); callback = fn end }
    time = { frame_count = function() return state.frame end }
    config = {
        current = function() return state.current end,
        list = function()
            if opts.list_error then error("列表不可用") end
            return opts.plans or PLANS
        end,
        switch = function(plan)
            state.switches[#state.switches + 1] = plan
            if opts.switch_error then error("切换失败") end
            if not opts.fail and not opts.delayed then state.current = plan end
            return false
        end,
    }
    log = { info = function() end, success = function() end,
        warn = function(message) state.warnings[#state.warnings + 1] = message end }
    draw = setmetatable({}, { __index = function() error("禁止调试绘制") end })
    esp = setmetatable({}, { __index = function() error("禁止调试元素") end })
    math.CalcAngle = function(from, to)
        local x, y, z = to.x - from.x, to.y - from.y, to.z - from.z
        return math.deg(math.atan(-z, math.sqrt(x * x + y * y))), math.deg(math.atan(y, x))
    end
    dofile(PATHS[kind])
    state.lp = lp
    state.step = function(count)
        for _ = 1, count or 1 do state.frame = state.frame + 1; callback({}) end
    end
    return state
end

local function check(state, expected)
    state.step()
    assert(state.current == expected, "预期 " .. expected .. "，实际 " .. state.current)
    state.step(3)
    assert(#state.switches == 1 and #state.warnings == 0)
end

local DISTANCE_BOUNDARIES = {
    { 0, "0_50" }, { 49.999, "0_50" }, { 50, "50_100" }, { 99.999, "50_100" },
    { 100, "100_200" }, { 199.999, "100_200" }, { 200, "200_inf" }, { 20000, "200_inf" },
}
local FOV_BOUNDARIES = {
    { 999, "1x" }, { 46.4, "1x" }, { 46.3999, "2x" }, { 32.14, "2x" },
    { 32.1399, "3x" }, { 22.95, "3x" }, { 22.9499, "4x" }, { 16.42, "4x" },
    { 16.4199, "6x" }, { 11.59, "6x" }, { 11.5899, "8x" }, { 8.98, "8x" },
    { 8.9799, "10x" }, { 2, "10x" },
}

for _, case in ipairs(DISTANCE_BOUNDARIES) do
    local s = scenario("distance", { enemy(case[1]) })
    s.lp.is_zooming = nil
    check(s, "config_" .. case[2])
    s = scenario("combined", { enemy(case[1]) })
    s.lp.is_zooming = false
    s.lp.target_zoom_fov = nil
    check(s, "config_" .. case[2] .. "_1x")
end
for _, case in ipairs(FOV_BOUNDARIES) do
    local s = scenario("scope")
    s.lp.target_zoom_fov = case[1]
    -- 倍镜版既不构造玩家列表，也不需要视线和摄像机字段。
    s.lp.camera_origin = nil
    game.entities = setmetatable({}, { __index = function() error("不应读取实体") end })
    check(s, "config_" .. case[2])
    s = scenario("combined", { enemy(80) })
    s.lp.target_zoom_fov = case[1]
    check(s, "config_50_100_" .. case[2])
end

local combinations = 0
for _, distance in ipairs(DISTANCES) do
    for _, scope in ipairs(SCOPES) do
        local s = scenario("combined", { enemy(distance[1]) })
        s.lp.target_zoom_fov = scope[1]
        check(s, "config_" .. distance[2] .. "_" .. scope[2])
        combinations = combinations + 1
    end
end
assert(combinations == 28)

for _, kind in ipairs({ "scope", "combined" }) do
    local suffix = kind == "scope" and "" or "0_50_"
    local s = scenario(kind, { enemy(20) })
    s.lp.is_zooming = false
    s.lp.weapon_fields_stale = true
    setmetatable(s.lp, { __index = function(_, key)
        if key == "target_zoom_fov" then error("收镜不应读取视野角") end
    end })
    s.lp.target_zoom_fov = nil
    check(s, "config_" .. suffix .. "1x")

    for _, value in ipairs({ 1.9999, 0, -1, 0 / 0, math.huge, -math.huge, "40" }) do
        s = scenario(kind, { enemy(20) })
        s.lp.target_zoom_fov = value
        s.step()
        assert(#s.switches == 0)
    end
    for _, field in ipairs({ "target_zoom_fov", "is_zooming" }) do
        s = scenario(kind, { enemy(20) })
        s.lp[field] = nil
        s.step()
        assert(#s.switches == 0)
    end
    s = scenario(kind, { enemy(20) })
    s.lp.weapon_fields_stale = true
    s.step()
    assert(#s.switches == 0)
    s.lp.weapon_fields_stale = false
    check(s, "config_" .. suffix .. "2x")
end

for _, kind in ipairs({ "distance", "combined" }) do
    local suffix = kind == "distance" and "" or "_2x"
    local s = scenario(kind, { [9] = enemy(20, 20), [100] = enemy(300, 1) })
    check(s, "config_200_inf" .. suffix)
    s = scenario(kind, { enemy(300, -179), enemy(20, 160) })
    s.lp.view_angle.y = 179
    check(s, "config_200_inf" .. suffix)
    s = scenario(kind, { enemy(300, 30, 80), enemy(20, 0, 70) })
    s.lp.view_angle.x = 80
    check(s, "config_200_inf" .. suffix)
    for _, field in ipairs({ "is_teammate", "is_dead", "is_down" }) do
        local invalid = enemy(20)
        invalid[field] = true
        s = scenario(kind, { invalid, enemy(300, 10) })
        check(s, "config_200_inf" .. suffix)
    end
    local invalid = enemy(20)
    invalid.in_screen = false
    s = scenario(kind, { invalid })
    s.step()
    assert(#s.switches == 0)
    s = scenario(kind, { enemy(20) })
    s.step()
    local previous = s.current
    game.entities.players = {}
    s.step()
    assert(s.current == previous and #s.switches == 1)
end

-- 组合版未知开镜状态时不能读实体；无目标时不能用视野角凭空选距离。
local s = scenario("combined")
s.lp.is_zooming = nil
game.entities = setmetatable({}, { __index = function() error("开镜状态应先判断") end })
s.step()
assert(#s.switches == 0)
s = scenario("combined")
s.lp.target_zoom_fov = nil
setmetatable(s.lp, { __index = function(_, key)
    if key == "target_zoom_fov" then error("距离应先判断") end
end })
s.step()
assert(#s.switches == 0)

for _, kind in ipairs({ "distance", "scope", "combined" }) do
    for _, opts in ipairs({ { plans = {} }, { plans = { "other" } }, { list_error = true } }) do
        s = scenario(kind, { enemy(20) }, opts)
        s.step(120)
        assert(#s.switches == 0 and #s.warnings == 1)
        s.step()
        assert(#s.warnings == 2)
    end
    for _, opts in ipairs({ { fail = true }, { delayed = true }, { switch_error = true } }) do
        s = scenario(kind, { enemy(20) }, opts)
        s.step(120)
        assert(#s.switches == 1)
        s.step()
        assert(#s.switches == 2)
    end
    for _, field in ipairs({ "is_dead", "is_down" }) do
        s = scenario(kind, { enemy(20) })
        s.lp[field] = true
        s.step()
        assert(#s.switches == 0)
    end
    s = scenario(kind, { enemy(20) }, { in_game = false })
    s.step()
    assert(#s.switches == 0)
    s = scenario(kind, { enemy(20) })
    game.localplayer = nil
    s.step()
    assert(#s.switches == 0)
end

-- 连续帧覆盖变距、变倍与收镜回退，确认没有只在初次加载时生效。
local target = enemy(20)
s = scenario("combined", { target })
s.step()
assert(s.current == "config_0_50_2x")
target.distance = 100
s.step()
assert(s.current == "config_100_200_2x")
s.lp.target_zoom_fov = 5
s.step()
assert(s.current == "config_100_200_10x")
s.lp.is_zooming = false
s.step()
assert(s.current == "config_100_200_1x")
target.distance = 200
s.step()
assert(s.current == "config_200_inf_1x")
s.current = "manual"
s.step()
assert(s.current == "config_200_inf_1x" and #s.switches == 6)

print("config auto-switch variants passed: boundaries, 28 combinations, priority and failure handling")
