-- 功能：把 HApex3.0 的实时玩家数据转换为旧版 HOOZi 网页雷达 JSON。
-- 分类：net
-- 使用 API：net.ws、game、event、gui、json、time、log。
-- 协议：输出旧网页雷达需要的 map 与 players 文本 JSON，坐标转换为 1015×1015 旧地图像素区。
-- 验证：HApex3.0 当前 Lua API 只提供 WebSocket 客户端；需要外部中继监听 ws://127.0.0.1:2334/ws 后再转发给网页雷达客户端。

local RAW_OFFSET_LEFT = 454.0
local RAW_OFFSET_TOP = 0.0
local RAW_VISIBLE_WIDTH = 1015.0
local RAW_VISIBLE_HEIGHT = 1015.0
local RADAR_CENTER_X = RAW_OFFSET_LEFT + RAW_VISIBLE_WIDTH * 0.5
local RADAR_CENTER_Y = RAW_OFFSET_TOP + RAW_VISIBLE_HEIGHT * 0.5
local DEFAULT_WORLD_RANGE = 65000.0

local MAP_ALIASES = {
    { id = "1", needle = "canyon", label = "Kings Canyon" },
    { id = "2", needle = "desertlands", label = "World's Edge" },
    { id = "2", needle = "world", label = "World's Edge" },
    { id = "3", needle = "olympus", label = "Olympus" },
    { id = "4", needle = "divided_moon", label = "Broken Moon" },
    { id = "4", needle = "broken", label = "Broken Moon" },
    { id = "5", needle = "tropic", label = "Storm Point" },
    { id = "5", needle = "storm", label = "Storm Point" },
    { id = "6", needle = "district", label = "E-District" },
}

local MAP_CALIBRATION = {
    -- 这些边界是新版世界坐标到旧版图片坐标的核心适配点；实际地图偏移时优先校准这里。
    ["1"] = { min_x = -65000.0, max_x = 65000.0, min_y = -65000.0, max_y = 65000.0 },
    ["2"] = { min_x = -65000.0, max_x = 65000.0, min_y = -65000.0, max_y = 65000.0 },
    ["3"] = { min_x = -65000.0, max_x = 65000.0, min_y = -65000.0, max_y = 65000.0 },
    ["4"] = { min_x = -65000.0, max_x = 65000.0, min_y = -65000.0, max_y = 65000.0 },
    ["5"] = { min_x = -65000.0, max_x = 65000.0, min_y = -65000.0, max_y = 65000.0 },
    ["6"] = { min_x = -65000.0, max_x = 65000.0, min_y = -65000.0, max_y = 65000.0 },
}

local tab = gui.tab("LegacyRadar")
local g_conn = tab:group("conn", "旧版网页雷达中继", 0, 0, 420, 0)
local cb_enabled = g_conn:checkbox("enabled", "启用推送", true)
local input_url = g_conn:input_text("url", "中继 WebSocket", "ws://127.0.0.1:2334/ws")
local sl_interval = g_conn:slider("send_every", "发送间隔", 2, 30, 4):set_format("%d frames")
local cb_teammates = g_conn:checkbox("include_teammates", "发送队友", true)
local cb_enemies = g_conn:checkbox("include_enemies", "发送敌人", true)
local cb_dead = g_conn:checkbox("include_dead", "发送倒地/死亡玩家", false)
local cb_clip = g_conn:checkbox("clip_to_map", "裁剪到地图边界", true)

local g_map = tab:group("map", "地图与坐标", 0, 0, 420, 0)
local input_manual_map = g_map:input_text("manual_map", "手动 map ID（空=自动）", "")
local sl_range = g_map:slider_float("fallback_range", "未知地图半径", 10000.0, 120000.0, DEFAULT_WORLD_RANGE):set_format("%.0f units")
g_map:tips("calibration_tip", "若点位整体偏移，请修改脚本顶部 MAP_CALIBRATION 的 min/max 世界坐标。", "info", { 0.55, 0.75, 1.0, 1.0 })

local g_status = tab:group("status", "状态", 0, 0, 420, 0)

local state = {
    ws_id = 0,
    reconnect_frame = 0,
    last_payload = "",
    last_map = "-1",
    last_players = 0,
    last_error = "",
    sent_count = 0,
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function current_map_id()
    local manual = trim(input_manual_map:get())
    if manual ~= "" then return manual end

    local name = ""
    if game.world and type(game.world.map_name) == "string" then
        name = string.lower(game.world.map_name)
    end
    if name == "" then return "-1" end

    for _, item in ipairs(MAP_ALIASES) do
        if string.find(name, item.needle, 1, true) then
            return item.id
        end
    end
    return "-1"
end

local function map_bounds(map_id, lp_origin)
    local cfg = MAP_CALIBRATION[map_id]
    if cfg then return cfg end

    local range = sl_range:get() or DEFAULT_WORLD_RANGE
    if lp_origin then
        -- 未知地图时让本机处于雷达中心，至少保证相对队形可见，后续再补精确边界。
        return {
            min_x = lp_origin.x - range,
            max_x = lp_origin.x + range,
            min_y = lp_origin.y - range,
            max_y = lp_origin.y + range,
        }
    end

    return { min_x = -range, max_x = range, min_y = -range, max_y = range }
end

local function world_to_legacy_pos(origin, bounds)
    if not origin or not bounds then
        return { x = RADAR_CENTER_X, y = RADAR_CENTER_Y }
    end

    local span_x = bounds.max_x - bounds.min_x
    local span_y = bounds.max_y - bounds.min_y
    if span_x == 0.0 or span_y == 0.0 then
        return { x = RADAR_CENTER_X, y = RADAR_CENTER_Y }
    end

    local nx = (origin.x - bounds.min_x) / span_x
    local ny = (origin.y - bounds.min_y) / span_y
    if cb_clip:get() then
        nx = clamp(nx, 0.0, 1.0)
        ny = clamp(ny, 0.0, 1.0)
    end

    return {
        x = RAW_OFFSET_LEFT + nx * RAW_VISIBLE_WIDTH,
        y = RAW_OFFSET_TOP + ny * RAW_VISIBLE_HEIGHT,
    }
end

local function stable_uid(seed)
    local text = tostring(seed or "0")
    local hash = 5381
    for i = 1, #text do
        -- 使用纯算术哈希，避免不同 Lua 版本的位运算兼容性差异。
        hash = (hash * 33 + string.byte(text, i)) % 4294967296
    end
    return string.format("%.0f", hash)
end

local function player_row(name, team, uid_seed, origin, bounds, hostile)
    return {
        name = name or "?",
        team = tonumber(team) or 0,
        uid = stable_uid(uid_seed),
        pos = world_to_legacy_pos(origin, bounds),
        level = 500,
        rank = "",
        kills = 0,
        pro = false,
        black = false,
        white = false,
        hostile = hostile == true,
    }
end

local function build_payload()
    local lp = game.localplayer
    local map_id = current_map_id()
    if map_id == "-1" or map_id == "0" or not lp or lp.is_dead then
        return json.encode({ map = map_id, players = {} }), map_id, 0
    end

    local bounds = map_bounds(map_id, lp.origin)
    local players = {}
    players[#players + 1] = player_row("<hoozi>", lp.team_num or lp.squad_id or 1, "local:" .. tostring(lp.team_num or 1), lp.origin, bounds, false)

    for key, p in pairs(game.entities.players) do
        local is_dead = p.is_dead or p.is_down
        if (cb_dead:get() or not is_dead) and not p.is_npc then
            local is_team = p.is_teammate == true
            if (is_team and cb_teammates:get()) or ((not is_team) and cb_enemies:get()) then
                players[#players + 1] = player_row(
                    p.name or "?",
                    p.team_num or p.squad_id or 0,
                    (p.name or "?") .. ":" .. tostring(p.team_num or 0) .. ":" .. tostring(key),
                    p.origin,
                    bounds,
                    not is_team
                )
            end
        end
    end

    return json.encode({ map = map_id, players = players }), map_id, #players
end

local function close_ws()
    if state.ws_id ~= 0 then
        net.ws:close(state.ws_id)
        state.ws_id = 0
    end
end

local function connect_ws()
    if not cb_enabled:get() then return end
    if state.ws_id ~= 0 and net.ws:is_open(state.ws_id) then return end

    local url = trim(input_url:get())
    if url == "" then return end

    state.ws_id = net.ws:connect(url, {
        on_open = function(id)
            state.last_error = ""
            gui.notify:success("旧雷达中继已连接", 2.0)
            if state.last_payload ~= "" then net.ws:send(id, state.last_payload) end
        end,
        on_message = function(id, msg)
            -- 旧网页雷达不会发命令；保留接收日志方便兼容外部中继的诊断消息。
            log.info("legacy radar relay: " .. tostring(msg))
        end,
        on_error = function(id, err)
            state.last_error = tostring(err or "unknown")
        end,
        on_close = function(id, code, reason)
            state.last_error = string.format("close %s %s", tostring(code), tostring(reason or ""))
            state.reconnect_frame = time.frame_count() + 180
        end,
    })
end

local function send_payload()
    local payload, map_id, player_count = build_payload()
    state.last_payload = payload
    state.last_map = map_id
    state.last_players = player_count

    if not cb_enabled:get() then return end
    if state.ws_id == 0 or not net.ws:is_open(state.ws_id) then
        connect_ws()
        return
    end

    if net.ws:send(state.ws_id, payload) then
        state.sent_count = state.sent_count + 1
    end
end

g_conn:button("reconnect", "重连中继", function()
    close_ws()
    state.reconnect_frame = 0
    connect_ws()
end)

g_conn:button("disconnect", "断开", function()
    close_ws()
    gui.notify:info("旧雷达中继已断开", 1.5)
end)

g_status:live_table("rows", { "项", "值" }, function()
    local open = (state.ws_id ~= 0) and net.ws:is_open(state.ws_id) or false
    return {
        { cells = { "连接", open and "OPEN" or "CLOSED" }, color = open and { 0.2, 0.55, 0.25, 0.35 } or { 0.55, 0.25, 0.20, 0.35 } },
        { cells = { "map", state.last_map } },
        { cells = { "players", tostring(state.last_players) } },
        { cells = { "sent", tostring(state.sent_count) } },
        { cells = { "error", state.last_error } },
    }
end, 140.0)

event.on("frame_update", function(e)
    if not cb_enabled:get() then return end

    local frame = time.frame_count()
    if state.ws_id ~= 0 and not net.ws:is_open(state.ws_id) and frame >= state.reconnect_frame then
        connect_ws()
    end

    local interval = math.Clamp(sl_interval:get() or 4, 2, 30)
    if frame % interval == 0 then
        send_payload()
    end
end)

log.success("旧版网页雷达 JSON 推送脚本已注册")
