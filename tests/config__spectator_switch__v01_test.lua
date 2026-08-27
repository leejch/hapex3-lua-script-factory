-- 模拟 HApex3.0 运行时，验证按本人 UID 反向统计观战者并切换参数方案。
-- 覆盖 0、1~2、3~4、5+ 四个区间，确认只统计解码后 spec_index 指向本人的实体。
-- 额外验证 players 表不含本人、UID 不可用、UID 重复和参数方案切换失败时不会误切参。
-- 运行：pnpm --package=fengari-node-cli dlx fengari tests/config__spectator_switch__v01_test.lua

local SCRIPT_PATH = "scripts/finished/config/config__spectator_switch__v01.lua"
local FORMAL_SCRIPT_PATH = "scripts/finished/config/config__spectator_switch__v02.lua"

-- 用截图中观察到的 EHandle 形式构造观战目标值，验证不能直接比较原始句柄。
local function spec_handle(index)
    return 65536 + index
end

local function run_scenario(options)
    local event_handlers = {}
    local switches = {}
    local warnings = {}
    local infos = {}
    local errors = {}
    local esp_callbacks = {}
    local draw_texts = {}
    local frame = 0
    local current_plan = options.current_plan or "manual"
    local available_plans = options.available_plans or {
        config = true,
        config_a = true,
        config_b = true,
        config_c = true,
    }

    game = {
        localplayer = options.localplayer,
        entities = { players = options.players },
    }

    function game:is_in_game()
        return options.is_in_game ~= false
    end

    config = {
        current = function()
            return current_plan
        end,
        list = function()
            local plans = {}
            for plan, enabled in pairs(available_plans) do
                if enabled then
                    plans[#plans + 1] = plan
                end
            end
            return plans
        end,
        switch = function(plan)
            switches[#switches + 1] = plan
            if not available_plans[plan] then
                return false
            end
            current_plan = plan
            if options.switch_return ~= nil then
                return options.switch_return
            end
            return true
        end,
    }

    time = {
        frame_count = function()
            return frame
        end,
    }

    draw = {
        font = function(name)
            return name
        end,
        screen = function()
            return 1920, 1080
        end,
        measure = function(text)
            return #text * 8, 16
        end,
        rgba = function(r, g, b, a)
            return { r, g, b, a }
        end,
        rect = function() end,
        text = function(x, y, color, text)
            draw_texts[#draw_texts + 1] = { x = x, y = y, color = color, text = text }
        end,
    }

    esp = {
        add = function(id, callback, opts)
            local element = {}
            esp_callbacks[id] = {
                callback = callback,
                element = element,
                opts = opts,
            }
            return element
        end,
    }

    event = {
        on = function(name, callback)
            event_handlers[name] = callback
            return #event_handlers
        end,
    }

    log = {
        info = function(message)
            infos[#infos + 1] = message
        end,
        success = function(message)
            infos[#infos + 1] = message
        end,
        warn = function(message)
            warnings[#warnings + 1] = message
        end,
        error = function(message)
            errors[#errors + 1] = message
        end,
    }

    dofile(options.script_path or SCRIPT_PATH)

    local function advance_frames(count)
        for _ = 1, count do
            frame = frame + 1
            assert(type(event_handlers.frame_update) == "function")
            event_handlers.frame_update({ delta_time = 1 / 144 })
        end
    end

    return {
        players = options.players,
        switches = switches,
        warnings = warnings,
        infos = infos,
        errors = errors,
        esp_callbacks = esp_callbacks,
        draw_texts = draw_texts,
        advance_frames = advance_frames,
        render_debug = function()
            local debug_callback = esp_callbacks.spectator_switch_debug
            assert(debug_callback ~= nil)
            debug_callback.callback(options.players[1], {})
        end,
        current_plan = function()
            return current_plan
        end,
    }
end

local players = {
    -- 本人实体是 42；localplayer.index 故意模拟为当前死亡观战目标 9，验证必须使用 UID 找到 42。
    { index = 42, platform_uid = "000111", is_npc = false, spec_index = -1 },
    { index = 9, platform_uid = "999", is_npc = false, spec_index = -1 },
    { index = 100, platform_uid = "100", is_npc = false, spec_index = spec_handle(9) },
    { index = 101, platform_uid = "101", is_npc = false, spec_index = -1 },
    { index = 102, platform_uid = "102", is_npc = false, spec_index = spec_handle(42) },
    { index = 103, platform_uid = "103", is_npc = false, spec_index = spec_handle(42) },
    { index = 104, platform_uid = "104", is_npc = false, spec_index = spec_handle(42) },
    { index = 105, platform_uid = "105", is_npc = false, spec_index = spec_handle(42) },
    { index = 106, platform_uid = "106", is_npc = false, spec_index = spec_handle(42) },
    { index = 107, platform_uid = "107", is_npc = false, spec_index = spec_handle(42) },
}

local normal = run_scenario({
    current_plan = "manual",
    localplayer = { index = 9, platform_uid = "111" },
    players = players,
})

normal.advance_frames(1)
assert(normal.current_plan() == "config_c")
assert(#normal.switches == 1 and normal.switches[1] == "config_c")
assert(#normal.warnings == 0)
assert(normal.esp_callbacks.spectator_switch_debug.opts.kind == "free")
assert(normal.esp_callbacks.spectator_switch_debug.element.enableds[1])
assert(normal.esp_callbacks.spectator_switch_debug.element.enableds[2])
assert(normal.esp_callbacks.spectator_switch_debug.element.enableds[3])
assert(normal.esp_callbacks.spectator_switch_debug.element.enableds[4])

-- index 100 正在观战 9，不应被计入；只有 index 102~107 的 6 人句柄解码后指向本人 42。
assert(normal.infos[#normal.infos]:match("6 名观战者"))

-- 6 人应稳定在 5+ 方案，不应每帧重复切换。
normal.advance_frames(10)
assert(#normal.switches == 1)

-- 变为 4 人，验证 3~4 区间。
normal.players[10].spec_index = -1
normal.players[9].spec_index = -1
normal.advance_frames(1)
assert(normal.current_plan() == "config_b")
assert(#normal.switches == 2 and normal.switches[2] == "config_b")

-- 变为 3 人，仍然是同一方案。
normal.players[8].spec_index = -1
normal.advance_frames(1)
assert(normal.current_plan() == "config_b")
assert(#normal.switches == 2)

-- 变为 2 人，验证 1~2 区间。
normal.players[7].spec_index = -1
normal.advance_frames(1)
assert(normal.current_plan() == "config_a")
assert(#normal.switches == 3 and normal.switches[3] == "config_a")

-- 变为 1 人，仍然是同一方案。
normal.players[6].spec_index = -1
normal.advance_frames(1)
assert(normal.current_plan() == "config_a")
assert(#normal.switches == 3)

-- 变为 0 人，验证基础方案。
normal.players[5].spec_index = -1
normal.advance_frames(1)
assert(normal.current_plan() == "config")
assert(#normal.switches == 4 and normal.switches[4] == "config")

-- 某些运行时的 players 表不包含本人实体；此时使用 localplayer.index 仍应支持 0 -> 1 切换。
local zero_to_one = run_scenario({
    current_plan = "config",
    localplayer = { index = 42, platform_uid = "111" },
    players = {
        { index = 44, platform_uid = "200", is_npc = false, spec_index = -1 },
    },
})
zero_to_one.advance_frames(1)
assert(zero_to_one.current_plan() == "config")
assert(#zero_to_one.switches == 0)
zero_to_one.players[1].spec_index = spec_handle(42)
zero_to_one.advance_frames(1)
assert(zero_to_one.current_plan() == "config_a")
assert(#zero_to_one.switches == 1 and zero_to_one.switches[1] == "config_a")
zero_to_one.render_debug()
local debug_has_count = false
local debug_has_target = false
local debug_has_decoded_ref = false
local debug_has_match = false
for _, draw_call in ipairs(zero_to_one.draw_texts) do
    debug_has_count = debug_has_count or draw_call.text:find("观战人数: 1", 1, true) ~= nil
    debug_has_target = debug_has_target or draw_call.text:find("目标方案: config_a", 1, true) ~= nil
    debug_has_decoded_ref = debug_has_decoded_ref or draw_call.text:find("44->65578(42)", 1, true) ~= nil
    debug_has_match = debug_has_match or draw_call.text:find("指向本人 index: 44", 1, true) ~= nil
end
assert(debug_has_count and debug_has_target and debug_has_decoded_ref and debug_has_match)
assert(math.abs(zero_to_one.draw_texts[1].y - 108.0) < 0.001)

-- 运行时可能返回 false 但已经完成切换；应以 config.current() 为准，不能误报 WARN。
local false_return = run_scenario({
    current_plan = "manual",
    switch_return = false,
    localplayer = { index = 42, platform_uid = "111" },
    players = {
        { index = 42, platform_uid = "111", is_npc = false, spec_index = -1 },
        { index = 44, platform_uid = "200", is_npc = false, spec_index = spec_handle(42) },
    },
})
false_return.advance_frames(1)
assert(false_return.current_plan() == "config_a")
assert(#false_return.warnings == 0)

-- 死亡观战时 self_base 应优先于跟随观战目标的 UID/index，仍只统计指向真实本人的玩家。
local base_identity = run_scenario({
    current_plan = "manual",
    localplayer = { index = 9, platform_uid = "999", self_base = 500 },
    players = {
        { index = 9, platform_uid = "999", base = 900, is_npc = false, spec_index = -1 },
        { index = 42, platform_uid = "111", base = 500, is_npc = false, spec_index = -1 },
        { index = 44, platform_uid = "200", base = 700, is_npc = false, spec_index = spec_handle(42) },
        { index = 45, platform_uid = "201", base = 701, is_npc = false, spec_index = spec_handle(9) },
    },
})
base_identity.advance_frames(1)
assert(base_identity.current_plan() == "config_a")
assert(#base_identity.switches == 1 and base_identity.switches[1] == "config_a")

-- 身份 UID 不可用时保持当前方案，不读取错误的观战目标。
local unavailable = run_scenario({
    current_plan = "manual",
    localplayer = { index = -1, platform_uid = nil },
    players = {
        { index = 9, platform_uid = "999", is_npc = false, spec_index = -1 },
    },
})
unavailable.advance_frames(1)
assert(unavailable.current_plan() == "manual")
assert(#unavailable.switches == 0)
assert(#unavailable.warnings == 1)

-- UID 重复时身份不明确，必须停切。
local duplicate = run_scenario({
    current_plan = "manual",
    localplayer = { platform_uid = "111" },
    players = {
        { index = 42, platform_uid = "111", is_npc = false, spec_index = -1 },
        { index = 43, platform_uid = "111", is_npc = false, spec_index = -1 },
        { index = 44, platform_uid = "200", is_npc = false, spec_index = spec_handle(42) },
    },
})
duplicate.advance_frames(1)
assert(duplicate.current_plan() == "manual")
assert(#duplicate.switches == 0)
assert(#duplicate.warnings == 1)

-- 目标方案不存在时只告警并保留原方案；重试冷却避免每帧调用 config.switch。
local failed_switch = run_scenario({
    current_plan = "manual",
    available_plans = {
        config = true,
        config_a = true,
        config_b = false,
        config_c = true,
    },
    localplayer = { platform_uid = "111" },
    players = {
        { index = 42, platform_uid = "111", is_npc = false, spec_index = -1 },
        { index = 44, platform_uid = "200", is_npc = false, spec_index = spec_handle(42) },
        { index = 45, platform_uid = "201", is_npc = false, spec_index = spec_handle(42) },
        { index = 46, platform_uid = "202", is_npc = false, spec_index = spec_handle(42) },
    },
})
failed_switch.advance_frames(1)
assert(failed_switch.current_plan() == "manual")
assert(#failed_switch.switches == 1 and failed_switch.switches[1] == "config_b")
failed_switch.advance_frames(10)
assert(#failed_switch.switches == 1)
assert(#failed_switch.warnings == 1)

-- 不在对局中时不改动已有方案，也不产生身份告警。
local out_of_game = run_scenario({
    is_in_game = false,
    current_plan = "manual",
    localplayer = { platform_uid = "111" },
    players = {},
})
out_of_game.advance_frames(1)
assert(out_of_game.current_plan() == "manual")
assert(#out_of_game.switches == 0)
assert(#out_of_game.warnings == 0)

-- 正式版使用 0、1、2、3+ 四个精确区间，且不创建任何调试 ESP。
local formal = run_scenario({
    script_path = FORMAL_SCRIPT_PATH,
    current_plan = "config",
    switch_return = false,
    localplayer = { index = 39, platform_uid = "111" },
    players = {
        { index = 39, platform_uid = "000111", is_npc = false, spec_index = -1 },
        { index = 7, platform_uid = "999", is_npc = false, spec_index = -1 },
        { index = 44, platform_uid = "200", is_npc = false, spec_index = -1 },
        { index = 45, platform_uid = "201", is_npc = false, spec_index = -1 },
        { index = 46, platform_uid = "202", is_npc = false, spec_index = -1 },
    },
})
formal.advance_frames(1)
assert(formal.current_plan() == "config")
formal.players[3].spec_index = spec_handle(39)
formal.advance_frames(1)
assert(formal.current_plan() == "config_a")
formal.players[4].spec_index = spec_handle(39)
formal.advance_frames(1)
assert(formal.current_plan() == "config_b")
formal.players[5].spec_index = spec_handle(39)
formal.advance_frames(1)
assert(formal.current_plan() == "config_c")
formal.players[5].spec_index = -1
formal.advance_frames(1)
assert(formal.current_plan() == "config_b")
formal.players[4].spec_index = -1
formal.advance_frames(1)
assert(formal.current_plan() == "config_a")
formal.players[3].spec_index = -1
formal.advance_frames(1)
assert(formal.current_plan() == "config")
assert(next(formal.esp_callbacks) == nil)
assert(#formal.draw_texts == 0)
assert(#formal.warnings == 0)

print("config__spectator_switch__v01 tests passed")
