-- 网页雷达数据桥（server 模式）—— cheat 自己在本机起 WebSocket server,
-- 浏览器 / Tauri 前端连过来订阅游戏状态. 不再依赖外部 server 在线.
--
-- 浏览器连法:   const ws = new WebSocket("ws://127.0.0.1:" + PORT)
-- 协议:
--   server → client : { kind="state", ts, map, players, ring }
--   client → server : { kind="ping" }   (可选,server 自动回 {kind="pong"})
--
-- 访问控制: lua server 只 listen 127.0.0.1, 默认只本机可达. 公网暴露 (frp/cloudflared)
-- 需在 HClient 走 WebRTC 转发 + viewer_jwt 鉴权, 不再在 lua 这层加密码.

local PORT     = 9001     -- 跟前端约定的本机端口
local MAP_SIDE = 1000     -- 跟前端 SVG viewBox 边长一致

-- ────────────────────────────────────────────────────────────────────
-- 菜单控件
-- ────────────────────────────────────────────────────────────────────
local tab = gui.tab("misc")
local g   = tab:group("bridge", "网页雷达 (server)", 0, 0, 350, 0)

local cb_enabled  = g:checkbox("enabled", "启用 server", true)
                     :set_hint("浏览器连 ws://127.0.0.1:" .. PORT)
local sl_interval = g:slider("interval", "广播间隔", 16, 500, 30)
                     :set_format("%d ms")
                     :set_hint("30 ms ≈ 33Hz 已够丝滑, 前端会在两帧间补帧到 60fps")

-- ────────────────────────────────────────────────────────────────────
-- 状态
-- ────────────────────────────────────────────────────────────────────

-- WsServer userdata, 不为 nil 表示 listen 成功
local srv = nil

-- listen 失败 (端口占用) 时定期重试,不要每帧都试
local next_retry_s   = 0.0
local retry_backoff  = 0.5
local RETRY_MAX      = 5.0

local last_send_s = 0.0

-- WorldToMapPixel 偶发 ok=false 时, 沿用最近一次有效坐标 (画面不抖)
local last_self_px, last_self_py
local pos_cache     = {}
local POS_CACHE_TTL = 2.0
local SWEEP_EVERY   = 60
local sweep_counter = 0

-- ────────────────────────────────────────────────────────────────────
-- server 生命周期
-- ────────────────────────────────────────────────────────────────────
local function ensure_server()
    if srv and srv:is_open() then return true end
    srv = nil
    local now = time.now()
    if now < next_retry_s then return false end
    next_retry_s = now + retry_backoff
    retry_backoff = math.min(retry_backoff * 1.5, RETRY_MAX)

    srv = net.ws_server:listen(PORT, {
        on_open = function(client)
            log.info(string.format("[WebRadar] client #%d joined (count=%d)",
                client, srv and srv:client_count() or 0))
        end,
        on_message = function(client, msg)
            -- 控制帧: 仅 ping (server 回 pong). 不是 json 就忽略, 防前端写错让 cheat 崩.
            local ok, t = pcall(json.decode, msg)
            if not ok or type(t) ~= "table" then return end
            if t.kind == "ping" then
                pcall(function() srv:send(client, json.encode({ kind = "pong", ts = time.now() })) end)
            end
        end,
        on_close = function(_) end,
        on_error = function(client, err)
            log.info(string.format("[WebRadar] client #%s error: %s", tostring(client), err or "?"))
        end,
    })
    if srv then
        retry_backoff = 0.5
        log.success("[WebRadar] server listening on ws://127.0.0.1:" .. PORT)
        gui.notify:success("网页雷达 server 已启动 :" .. PORT, 1.5)
        return true
    end
    return false
end

-- ────────────────────────────────────────────────────────────────────
-- 快照: 把 game.* 抓成 JSON 友好的 plain table
-- ────────────────────────────────────────────────────────────────────
local function snapshot()
    local lp = game.localplayer
    local now = time.now()
    local lp_index = lp and lp.index or -1

    -- camera_origin 在观战时跟着 spec target,死亡后比 entity origin 可用。
    -- 关键: game.* 每次访问都刷新内部共享快照,会释放上一次访问返回的对象。lp.camera_origin
    -- 是指回该快照的 vec3 引用,一旦下面访问 game.entities.players 触发刷新(且 reader 此刻换了
    -- 缓冲),它就悬空 → 读 lp_co.x 是 use-after-free(0xC0000005,pcall 挡不住)。故此处立刻把
    -- 坐标拷成纯标量,绝不把 vec3 引用跨 game.* 访问持有。
    local lp_cox, lp_coy
    if lp then
        local co = lp.camera_origin or lp.origin
        if co then lp_cox, lp_coy = co.x, co.y end
    end

    local players = {}
    for _, p in pairs(game.entities.players) do
        if not p.is_npc then
            local is_self = (lp_index >= 0 and p.index == lp_index)
            local ox = is_self and (lp_cox or 0) or (p.origin and p.origin.x or 0)
            local oy = is_self and (lp_coy or 0) or (p.origin and p.origin.y or 0)
            local y  = p.yaw or 0
            local has_pos   = (ox ~= 0 or oy ~= 0) and ox > -1e6 and ox < 1e6 and oy > -1e6 and oy < 1e6
            local valid_yaw = y == y and y > -1e6 and y < 1e6   -- NaN: NaN ~= NaN

            -- entity index 一局内稳定,比 uid 可靠 (机器人 / 占位玩家可能没 uid)
            local uid = p.platform_uid
            local stable_id = p.index and ("ix" .. tostring(p.index))
                          or (uid and uid ~= "" and uid ~= "0" and ("uid" .. uid))
                          or ("anon-" .. (p.name or "?"))

            local px, py, ok
            if has_pos and valid_yaw then
                px, py, ok = math.WorldToMapPixel(ox, oy, MAP_SIDE, MAP_SIDE)
            end

            -- sticky cache: 这一帧坐标无效就回退最近 TTL 内的像素值
            if is_self then
                if ok then last_self_px, last_self_py = px, py
                elseif last_self_px then px, py, ok = last_self_px, last_self_py, true
                end
            elseif ok then
                pos_cache[stable_id] = { px, py, now }
            else
                local c = pos_cache[stable_id]
                if c and (now - c[3]) < POS_CACHE_TTL then
                    px, py, ok = c[1], c[2], true
                end
            end

            -- 本机即便 has_pos 失败也要进列表 (前端靠 self 字段判焦点)
            if is_self or ok then
                players[#players + 1] = {
                    id              = stable_id,
                    self            = is_self,
                    name            = p.name or "?",
                    index           = p.index,
                    team            = p.team_num or 0,
                    squad           = p.squad_id or 0,
                    x               = ok and px or nil,
                    y               = ok and py or nil,
                    yaw             = p.yaw or 0,
                    hp              = p.health or 0,
                    max_hp          = 100,
                    shield          = p.shield or 0,
                    max_shield      = p.max_shield or 0,
                    distance        = p.distance or 0,
                    is_dead         = p.is_dead or false,
                    is_down         = p.is_down or false,
                    legend          = p.legend or "",
                    legend_icon_key = p.legend_icon_key or "",
                    uid             = p.platform_uid or "",
                    level           = p.grade or 0,
                    kills           = p.kills or 0,
                    damage          = p.damage or 0,
                    rank            = p.rank or "",
                    rank_icon_key   = p.rank_icon_key or "",
                    rank_color      = p.rank_color or "",
                    roster          = p.roster or 0,
                }
            end
        end
    end

    -- 毒圈半径: cpp 推阶段端点 [r_start,r_end] + [t_start,t_end],必须 lua 端按 curtime 插值,
    -- 否则前端拿到的是"阶段开始时大小"画面卡住,收缩过程看不到
    local ring_data
    local ring = game.world.ring
    if ring and ring.is_active then
        local cur = time.curtime()
        local t_s, t_e = ring.time_start or 0, ring.time_end or 0
        local r_s, r_e = ring.radius_start or 0, ring.radius_end or 0
        local r_world
        if t_e == t_s then
            r_world = r_e
        else
            local f = (cur - t_s) / (t_e - t_s)
            if f < 0 then f = 0 elseif f > 1 then f = 1 end
            r_world = r_s + f * (r_e - r_s)
        end
        local ox = ring.origin and ring.origin.x or 0
        local oy = ring.origin and ring.origin.y or 0
        local px, py, ok_xy = math.WorldToMapPixel(ox, oy, MAP_SIDE, MAP_SIDE)
        local r_px, ok_r    = math.WorldRadiusToMapPixel(r_world, MAP_SIDE)
        if ok_xy and ok_r then
            ring_data = { x = px, y = py, radius = r_px, t_start = t_s, t_end = t_e, t_now = cur }
        end
    end

    sweep_counter = sweep_counter + 1
    if sweep_counter >= SWEEP_EVERY then
        sweep_counter = 0
        for k, v in pairs(pos_cache) do
            if (now - v[3]) > POS_CACHE_TTL then pos_cache[k] = nil end
        end
    end

    return {
        kind    = "state",
        ts      = now,
        map     = game.world.map_name or "",
        players = players,
        ring    = ring_data,
    }
end

-- ────────────────────────────────────────────────────────────────────
-- 每帧调度
-- ────────────────────────────────────────────────────────────────────
event.on("frame_update", function()
    if not cb_enabled:get() then
        if srv then srv:close(); srv = nil end
        return
    end
    if not ensure_server() then return end
    if srv:client_count() == 0 then return end

    local now = time.now()
    local interval_s = (sl_interval:get() or 30) * 0.001
    if (now - last_send_s) < interval_s then return end
    last_send_s = now

    -- snapshot() 必须放进 pcall 闭包里:pcall(json.encode, snapshot()) 会先求值 snapshot()
    -- (作为实参,在 pcall 保护之外),它一旦报错就裸抛——release 下经事件派发以 LuaJIT SEH 崩进程。
    local ok, encoded = pcall(function() return json.encode(snapshot()) end)
    if not ok then return end

    -- 广播全员 — lua 不区分本机/远程 client, 访问控制走外层 (HClient WebRTC + viewer_jwt).
    srv:broadcast(encoded)
end)

event.on("script_unloaded", function()
    pos_cache = {}
    sweep_counter = 0
    last_self_px, last_self_py = nil, nil
    if srv then srv:close(); srv = nil end
end)

log.success("Web Radar Server loaded — ws://127.0.0.1:" .. PORT)
