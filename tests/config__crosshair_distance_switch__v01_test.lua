-- 模拟帧更新，验证角度优先选敌、米制分档和无目标时保持配置。
-- 覆盖边界、视角跨界、无效实体及缺失方案时的安全行为。
-- 验证切换失败的限频重试和接口延迟发布，不依赖真实游戏环境。
-- 运行：pnpm --package=fengari-node-cli dlx fengari tests/config__crosshair_distance_switch__v01_test.lua

local SCRIPT_PATH = "scripts/finished/config/config__crosshair_distance_switch__v01.lua"
local ALL_PLANS = { "config_0_50", "config_50_100", "config_100_200", "config_200_inf" }

local function enemy(distance, yaw, pitch)
    local yaw_rad = math.rad(yaw or 0)
    local pitch_rad = math.rad(pitch or 0)
    return {
        index = 2,
        distance = distance,
        in_screen = true,
        is_teammate = false,
        is_dead = false,
        is_down = false,
        origin = {
            x = 100 * math.cos(pitch_rad) * math.cos(yaw_rad),
            y = 100 * math.cos(pitch_rad) * math.sin(yaw_rad),
            z = -100 * math.sin(pitch_rad),
        },
    }
end

local function scenario(players, options)
    options = options or {}
    local state = { current = "manual", switches = {}, warnings = {}, frame = 0 }
    game = {
        localplayer = {
            index = 1, is_dead = false, is_down = false,
            camera_origin = { x = 0, y = 0, z = 0 },
            view_angle = { x = options.pitch or 0, y = options.yaw or 0 },
        },
        entities = { players = players },
        is_in_game = function() return options.in_game ~= false end,
    }
    local lp = game.localplayer
    local callback
    event = { on = function(name, fn)
        assert(name == "frame_update")
        callback = fn
    end }
    time = { frame_count = function() return state.frame end }
    config = {
        current = function() return state.current end,
        list = function()
            if options.list_error then error("列表不可用") end
            return options.plans or ALL_PLANS
        end,
        switch = function(plan)
            state.switches[#state.switches + 1] = plan
            if options.switch_error then error("切换异常") end
            if not options.fail and not options.delayed then state.current = plan end
            return false
        end,
    }
    log = {
        info = function() end,
        success = function() end,
        warn = function(message) state.warnings[#state.warnings + 1] = message end,
    }
    math.CalcAngle = function(from, to)
        local x, y, z = to.x - from.x, to.y - from.y, to.z - from.z
        return math.deg(math.atan(-z, math.sqrt(x * x + y * y))), math.deg(math.atan(y, x))
    end
    dofile(SCRIPT_PATH)
    state.lp = lp
    state.step = function(count)
        for _ = 1, count or 1 do
            state.frame = state.frame + 1
            callback({})
        end
    end
    return state
end

for _, case in ipairs({
    { 0, ALL_PLANS[1] }, { 49.999, ALL_PLANS[1] },
    { 50, ALL_PLANS[2] }, { 99.999, ALL_PLANS[2] },
    { 100, ALL_PLANS[3] }, { 199.999, ALL_PLANS[3] },
    { 200, ALL_PLANS[4] }, { 2000, ALL_PLANS[4] },
}) do
    local s = scenario({ enemy(case[1]) })
    s.step()
    assert(s.current == case[2], "距离分档错误：" .. case[1])
    s.step(10)
    assert(#s.switches == 1 and #s.warnings == 0)
end

-- 稀疏表仍能遍历；较远但角度更小的敌人应优先。
local s = scenario({ [12] = enemy(20, 20), [99] = enemy(150, 1) })
s.step()
assert(s.current == ALL_PLANS[3])

-- 跨越 ±180° 时仍选择只有两度夹角的敌人。
s = scenario({ enemy(300, -179), enemy(20, 160) }, { yaw = 179 })
s.step()
assert(s.current == ALL_PLANS[4])

-- 高仰角下比较真实三维夹角，不能直接比较俯仰偏差和偏航偏差的平方和。
s = scenario({ enemy(300, 30, 80), enemy(20, 0, 70) }, { pitch = 80 })
s.step()
assert(s.current == ALL_PLANS[4])

for _, field in ipairs({ "is_teammate", "is_dead", "is_down" }) do
    local invalid = enemy(20)
    invalid[field] = true
    s = scenario({ invalid, enemy(300, 10) })
    s.step()
    assert(s.current == ALL_PLANS[4])
end
local offscreen = enemy(20)
offscreen.in_screen = false
local self_entity = enemy(20)
self_entity.index = 1
local invalid_distance = enemy(-1)
local invalid_origin = enemy(20)
invalid_origin.origin.x = 0 / 0
s = scenario({ offscreen, self_entity, invalid_distance, invalid_origin })
s.step()
assert(#s.switches == 0)

s = scenario({ enemy(20) })
s.step()
game.entities.players = {}
s.step()
assert(s.current == ALL_PLANS[1] and #s.switches == 1)
for _, field in ipairs({ "is_dead", "is_down" }) do
    s = scenario({ enemy(20) })
    s.lp[field] = true
    s.step()
    assert(#s.switches == 0)
end
s = scenario({ enemy(20) }, { in_game = false })
s.step()
assert(#s.switches == 0)

-- 缺失、空或异常方案列表都不能调用切换，以免自动创建默认参数。
for _, options in ipairs({ { plans = { "other" } }, { plans = {} }, { list_error = true } }) do
    s = scenario({ enemy(20) }, options)
    s.step(120)
    assert(#s.switches == 0 and #s.warnings == 1)
end
for _, options in ipairs({ { fail = true }, { switch_error = true }, { delayed = true } }) do
    s = scenario({ enemy(20) }, options)
    s.step(120)
    assert(#s.switches == 1)
    s.step()
    assert(#s.switches == 2)
end
s = scenario({ enemy(20) }, { delayed = true })
s.step()
s.current = ALL_PLANS[1]
s.step(120)
assert(#s.switches == 1)

-- 敌人移动、转向选中另一人以及人工切参后，下一帧均应重新判断。
local target = enemy(20)
s = scenario({ target })
s.step()
target.distance = 80
s.step()
assert(s.current == ALL_PLANS[2])
game.entities.players = { enemy(300, 0), enemy(20, 10) }
s.step()
assert(s.current == ALL_PLANS[4])
s.current = "manual"
s.step()
assert(s.current == ALL_PLANS[4] and #s.switches == 4)

print("config__crosshair_distance_switch__v01 tests passed")
