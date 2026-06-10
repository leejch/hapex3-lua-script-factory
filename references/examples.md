# Example scripts

Eight scripts ship with the product; full source lives in the `scripts/` directory next to the application. Each script's top 5 comment lines document its dependencies and load behavior.

---

## keybind_hint_pack

Attaches dynamic text and color hints to keybind controls. Demonstrates the three return shapes of `input.format`: plain string, `{text, color}` table, and threshold-based dynamic colors.

```lua
local tab    = gui.tab("KbHints")
local g_pack = tab:group("g", "三种 formatter 返值演示", 0, 0, 300, 0)

g_pack:keybind_control("alarm",     "警报开关"):set_hint("返字符串：状态文字")
g_pack:keybind_control("stopwatch", "秒表"):set_hint("返 {text, color}：纯色")
g_pack:keybind_control("counter",   "计数器"):set_hint("返 {text, color}：按值变色")

-- Returns a plain string
local alarm_armed = false
g_pack:button("toggle_alarm", "切换警报状态", function()
    alarm_armed = not alarm_armed
    gui.notify:info(alarm_armed and "警报已 ARMED" or "警报 OFF", 1.5)
end)
input.format("KbHints.g.alarm", function(id)
    return alarm_armed and "ARMED" or "OFF"
end)

-- Returns a {text, color} table with a fixed color
local start_t = os.clock()
input.format("KbHints.g.stopwatch", function(id)
    return {
        text  = string.format("%.1fs", os.clock() - start_t),
        color = { 0.55, 0.85, 1.0, 1.0 },
    }
end)

-- Returns a {text, color} table; color picked by threshold
local counter = 0
g_pack:button("tick", "计数 +1", function() counter = counter + 1 end)
g_pack:button("reset", "计数清零", function()
    counter = 0
    gui.notify:warn("计数器已清零", 1.2)
end)
input.format("KbHints.g.counter", function(id)
    local label = string.format("× %d", counter)
    if counter == 0     then return { text = label, color = { 0.6, 0.6, 0.6, 1.0 } } end
    if counter < 10     then return { text = label, color = { 0.3, 1.0, 0.3, 1.0 } } end
    return { text = label, color = { 1.0, 0.45, 0.25, 1.0 } }
end)

log.success("keybind_hint_pack 注册完成")
```

APIs used: `gui.tab`, `input.format`, `gui.notify`, `KeybindControl:set_hint`

---

## low_health_alert

One-shot notification plus red ESP text when a teammate goes down or when you / a teammate are low on HP. Debounced to avoid spam from continuous triggers.

```lua
local tab    = gui.tab("LowHpAlert")
local g_cfg  = tab:group("g_cfg", "提示阈值（百分比）", 0, 0, 0, 0)

local th_self_el  = g_cfg:slider("th_self",     "自己血量低于", 1, 100, 30):set_format("%d%%")
local th_team_el  = g_cfg:slider("th_teammate", "队友血量低于", 1, 100, 25):set_format("%d%%")
local th_enemy_el = g_cfg:slider("th_enemy",    "敌方残血标红", 1, 100, 50):set_format("%d%%")
local notify_el   = g_cfg:checkbox("notify_on", "启用通知提示", true)

-- Debounce
local last_alert = {}
local function should_fire(key)
    local t = os.clock()
    local prev = last_alert[key] or 0.0
    if t - prev < 4.0 then return false end
    last_alert[key] = t
    return true
end

local function hp_pct(p)
    local hp = p.health or 0
    local max_total = 100.0 + math.max(p.max_shield or 0, 1)
    local total = hp + (p.shield or 0)
    return math.max(0, math.min(100, (total / max_total) * 100.0))
end

esp.add("self_hp", function(player, ctx)
    if not (player.is_teammate and (player.distance or 999) < 1.0) then return nil end
    local pct = hp_pct(player)
    if pct < th_self_el:get() then
        if notify_el:get() and should_fire("__self__") then
            gui.notify:error(string.format("自己低血 %.0f%%！", pct), 3.0)
        end
        return { text = string.format("HP %.0f%% ⚠", pct),
                 text_color = { 1.0, 0.25, 0.25, 1.0 } }
    end
end, { label = "Self HP", kind = "text" })

esp.add("teammate_state", function(player, ctx)
    if not player.is_teammate then return nil end
    if (player.distance or 0) < 1.0 then return nil end

    if player.is_down then
        if notify_el:get() and should_fire("DOWN:" .. (player.name or "?")) then
            gui.notify:warn(string.format("队友 %s 倒了！", player.name or "?"), 3.5)
        end
        return { text = "💀 DOWN", text_color = { 1.0, 0.3, 0.3, 1.0 } }
    end

    local pct = hp_pct(player)
    if pct < th_team_el:get() then
        if notify_el:get() and should_fire("LOW:" .. (player.name or "?")) then
            gui.notify:info(string.format("队友 %s 残血 %.0f%%", player.name or "?", pct), 2.5)
        end
        return { text = string.format("%.0f%%", pct),
                 text_color = { 1.0, 0.7, 0.2, 1.0 } }
    end
end, { label = "队友状态", kind = "text" })

esp.add("enemy_lowhp", function(player, ctx)
    if player.is_teammate then return nil end
    local pct = hp_pct(player)
    if pct >= th_enemy_el:get() then return nil end
    local color = pct < 25 and { 1.0, 0.15, 0.15, 1.0 } or { 1.0, 0.4, 0.4, 1.0 }
    return { text = string.format("%.0f%%", pct), text_color = color }
end, {
    label = "敌方残血", kind = "text",
    dist  = { 5.0, 250.0 },
})

log.success("low_health_alert 已注册 3 个 ESP 文本元素")
```

APIs used: `esp.add`, `game.entities.players`, `gui.notify`

---

## tactical_theme

One-click switch between ESP color schemes for different tactical scenarios (Default / HighContrast / Stealth). A single `el.colors = {c0,c1,c2,c3}` line writes all four scenario colors at once.

```lua
local THEMES = {
    {
        name   = "Default",
        colors = {
            { 0.85, 0.85, 0.85, 1.0 },  -- Invisible enemy: white
            { 1.00, 0.35, 0.35, 1.0 },  -- Visible enemy: red
            { 1.00, 0.80, 0.20, 1.0 },  -- Downed: orange
            { 0.35, 0.85, 1.00, 1.0 },  -- Teammate: light blue
        },
    },
    {
        name   = "HighContrast",
        colors = {
            { 0.40, 0.40, 0.40, 1.0 },
            { 1.00, 1.00, 0.20, 1.0 },
            { 1.00, 0.10, 0.10, 1.0 },
            { 0.20, 1.00, 0.40, 1.0 },
        },
    },
    {
        name   = "Stealth",
        colors = {
            { 1.00, 0.60, 1.00, 1.0 },
            { 1.00, 0.40, 0.10, 1.0 },
            { 0.60, 0.60, 0.60, 1.0 },
            { 0.10, 0.60, 1.00, 1.0 },
        },
    },
}

local tac_tag = esp.add("tac_tag", function(p, ctx)
    if p.is_teammate then return "ALLY" end
    if p.is_down     then return "DWN" end
    if p.is_visible  then return "VIS" end
    return "INV"
end, {
    label  = "Tac Tag",
    kind   = "text",
    colors = THEMES[1].colors,
    dist   = { 5.0, 300.0 },
})

local function apply_theme(idx)
    local theme = THEMES[idx]
    if not theme then
        gui.notify:error("主题索引越界：" .. tostring(idx), 2.0)
        return
    end
    tac_tag.colors = theme.colors
    gui.notify:success("已切到主题：" .. theme.name, 2.5)
end

local tab    = gui.tab("TacTheme")
local g_main = tab:group("g_main", "战术配色", 0, 0, 0, 0)

local theme_names = {}
for i, t in ipairs(THEMES) do theme_names[i] = t.name end

g_main:dropdown("theme", "当前主题", theme_names, 1)
      :on_change(function(idx, name) apply_theme(idx) end)

apply_theme(1)
log.success("tactical_theme 已注册 3 个主题")
```

APIs used: `esp.add`, `ESPElement.colors`, `Combobox:on_change`

---

## perf_hud

Floating window displaying FPS, frame time (avg / min / max), and loot count. `win:bind_visible(checkbox)` auto-syncs window visibility with the checkbox.

```lua
local tab     = gui.tab("PerfHud")
local g_ctrl  = tab:group("g_ctrl", "性能 HUD 控制", 0, 0, 350, 0)
local cb_show = g_ctrl:checkbox("show", "显示浮动窗口", false)
local sl_cap  = g_ctrl:slider("smooth_frames", "滑窗帧数", 5, 240, 60):set_format("%d frames")

local win = gui.window("perf_hud_window", "Perf HUD", 240.0, 140.0)
win:bind_visible(cb_show)

local ring, ring_head, ring_size = {}, 1, 0
local last_fps, last_ms, last_max, last_min = 0.0, 0.0, 0.0, 999.0

event.on("frame_update", function(e)
    local dt = e.delta_time
    if dt <= 0.0 then return end

    local cap = math.Clamp(sl_cap:get() or 60, 5, 240)

    ring[ring_head] = dt
    ring_head = ring_head + 1
    if ring_head > cap then ring_head = 1 end
    if ring_size < cap then ring_size = ring_size + 1 end

    local sum, mx, mn = 0.0, 0.0, 9999.0
    for i = 1, ring_size do
        local v = ring[i]
        sum = sum + v
        if v > mx then mx = v end
        if v < mn then mn = v end
    end
    local avg = sum / ring_size
    last_fps = (avg > 0.0) and (1.0 / avg) or 0.0
    last_ms  = avg * 1000.0
    last_max = mx * 1000.0
    last_min = mn * 1000.0
end)

win:live_table("metrics",
    { "指标", "值" },
    function()
        local loots, players = 0, 0
        for _ in pairs(game.entities.loots)   do loots   = loots + 1 end
        for _ in pairs(game.entities.players) do players = players + 1 end

        local rows = {
            { cells = { "FPS",       string.format("%.1f", last_fps) } },
            { cells = { "帧时 avg",  string.format("%.2f ms", last_ms) } },
            { cells = { "帧时 min",  string.format("%.2f ms", last_min) } },
            { cells = { "帧时 max",  string.format("%.2f ms", last_max) } },
            { cells = { "loots",     tostring(loots) } },
            { cells = { "players",   tostring(players) } },
        }

        local lp = game.localplayer
        if lp then
            table.insert(rows, { cells = { "HP/Shield",
                string.format("%d / %d", lp.health or 0, lp.shield or 0) } })
            table.insert(rows, { cells = { "Map", game.world.map_name or "?" } })
        end

        if last_ms > 16.67 then rows[2].color = { 0.55, 0.20, 0.20, 0.35 } end
        if last_max > 33.0 then rows[4].color = { 0.55, 0.45, 0.15, 0.35 } end
        return rows
    end, 180.0)

log.success("perf_hud 已加载")
```

APIs used: `gui.window`, `Window:bind_visible`, `event.on frame_update`, `Window:live_table`

---

## loadout_presets

One-click switch between multiple config presets, with a floating window showing the active preset. Batch `gui.set` writes the controls; `gui.set_visible` toggles sub-tab visibility.

```lua
local tab    = gui.tab("Loadout")
local g_demo = tab:group("g_demo", "演示控件（被预设修改）", 0, 0, 0, 0)

g_demo:checkbox("aggressive",     "开火激进",     false)
g_demo:checkbox("auto_heal_prio", "治疗优先",     true)
g_demo:slider  ("range",          "交战距离上限", 10, 300, 100):set_format("%d m")
g_demo:slider  ("smoothing",      "瞄准平滑",     1,  50,  10)
g_demo:dropdown("playstyle_tag",  "Playstyle 标签",
    { "Default", "Holder", "Rusher", "Safe" }, 2)

local sub_adv = gui.sub_tab(tab, "advanced", "进阶（预设可见性）")
local g_adv   = sub_adv:group("g_adv", "进阶控件", 0, 0, 0, 0)
g_adv:checkbox("rapid_swap",    "快速换弹",     false)
g_adv:slider  ("trigger_delay", "Trigger 延迟", 0, 200, 80):set_format("%d ms")

local advanced_paths = {
    "Loadout.advanced",
    "Loadout.advanced.g_adv.rapid_swap",
    "Loadout.advanced.g_adv.trigger_delay",
}

local PRESETS = {
    ["Holder 守点"] = {
        tag_index = 2,
        values    = {
            ["Loadout.g_demo.aggressive"]     = false,
            ["Loadout.g_demo.auto_heal_prio"] = true,
            ["Loadout.g_demo.range"]          = 250,
            ["Loadout.g_demo.smoothing"]      = 6,
        },
        advanced_visible = false,
    },
    ["Rusher 突袭"] = {
        tag_index = 3,
        values    = {
            ["Loadout.g_demo.aggressive"]     = true,
            ["Loadout.g_demo.auto_heal_prio"] = false,
            ["Loadout.g_demo.range"]          = 60,
            ["Loadout.g_demo.smoothing"]      = 18,
        },
        advanced_visible = true,
    },
    ["Safe 安全运营"] = {
        tag_index = 4,
        values    = {
            ["Loadout.g_demo.aggressive"]     = false,
            ["Loadout.g_demo.auto_heal_prio"] = true,
            ["Loadout.g_demo.range"]          = 180,
            ["Loadout.g_demo.smoothing"]      = 25,
        },
        advanced_visible = false,
    },
}

local preset_order   = { "Holder 守点", "Rusher 突袭", "Safe 安全运营" }
local current_preset = "Holder 守点"

local function apply_preset(name)
    local p = PRESETS[name]
    if not p then return end

    for path, val in pairs(p.values) do gui.set(path, val) end
    gui.set("Loadout.g_demo.playstyle_tag", p.tag_index)
    gui.set_visible(advanced_paths, p.advanced_visible)

    current_preset = name
    gui.notify:success("已应用预设：" .. name, 2.5)
end

local g_pick = tab:group("g_pick", "预设选择", 0, 0, 0, 0)
g_pick:dropdown("preset", "当前预设", preset_order, 1)
      :on_change(function(idx, name) apply_preset(name) end)
g_pick:button("apply_now", "重新应用当前预设", function() apply_preset(current_preset) end)

local win = gui.window("loadout_status", "Loadout", 220.0, 100.0)
win:set_open(true)
win:group("g_win", "当前预设", 0, 0, 0, 0)
   :live_table("status", { "项", "值" }, function()
        return {
            { cells = { "预设",     current_preset } },
            { cells = { "激进开火", tostring(gui.get("Loadout.g_demo.aggressive")) } },
            { cells = { "交战距离", tostring(gui.get("Loadout.g_demo.range")) } },
            { cells = { "瞄准平滑", tostring(gui.get("Loadout.g_demo.smoothing")) } },
        }
   end, 110.0)

apply_preset("Holder 守点")
log.success("loadout_presets 已加载 3 套预设")
```

APIs used: `gui.sub_tab`, `gui.set` / `gui.get`, `gui.set_visible`, `Combobox:on_change`, `Window:set_open`

---

## loot_inspector

Live snapshot of current loot — name, distance, tier. Has a name filter.

```lua
local tab     = gui.tab("LootInspector")
local cb_show = tab:checkbox("show", "显示窗口", false)
local filter  = tab:input_text("filter", "名字过滤", "")

local win = gui.window("loot_inspector_win", "Loot Inspector", 520, 420)
win:bind_visible(cb_show)

win:live_table("loots", { "序号", "名字", "距离", "等级" }, function()
    local rows = {}
    local f = filter:get():lower()
    local idx = 0
    for _, l in pairs(game.entities.loots) do
        idx = idx + 1
        local name = (l.classified_name ~= "" and l.classified_name)
                  or (l.base_name and l.base_name ~= "" and l.base_name)
                  or l.model_name
                  or "?"
        if f == "" or name:lower():find(f, 1, true) then
            table.insert(rows, {
                tostring(idx),
                name,
                string.format("%.0f m", l.distance / 39.37),
                tostring(l.quality_level)
            })
        end
        if #rows >= 200 then break end
    end
    return rows
end)

log.success("loot_inspector 已加载")
```

APIs used: `game.entities.loots`, `Window:bind_visible`, `InputText:get`

---

## remote_config_push

WebSocket receives `path=value` commands and hot-patches menu controls. An HTTP probe doubles as a connectivity test. All four callbacks (open / message / error / close) are wired up.

```lua
local state = {
    ws_id    = 0,
    last_msg = nil,
    log_buf  = {},
}

local function push_log(dir, text)
    if #state.log_buf >= 50 then table.remove(state.log_buf, 1) end
    state.log_buf[#state.log_buf + 1] = { ts = os.clock(), dir = dir, text = text }
end

local function parse_value(s)
    if s == "true"  then return true end
    if s == "false" then return false end
    local n = tonumber(s)
    if n ~= nil then return n end
    return s
end

local function apply_path_value(text)
    local sep = string.find(text, "=", 1, true)
    if not sep then
        push_log("!", "格式错误，缺 '=': " .. text)
        return
    end
    local path = string.sub(text, 1, sep - 1)
    local val  = parse_value(string.sub(text, sep + 1))

    if not gui.find(path) then
        push_log("!", "找不到控件：" .. path)
        return
    end
    gui.set(path, val)
    push_log("<", string.format("apply %s = %s", path, tostring(val)))
end

local tab    = gui.tab("RemoteCfg")
local g_conn = tab:group("g_conn", "连接", 0, 0, 0, 0)

g_conn:input_text("url", "WebSocket URL", "ws://127.0.0.1:9000/cfg")
g_conn:input_text("probe_url", "HTTP 探针 URL", "http://127.0.0.1:9000/health")

g_conn:button("probe", "HTTP 探针", function()
    local url = gui.get("RemoteCfg.g_conn.probe_url", "")
    if type(url) ~= "string" or url == "" then return end
    net.http:get(url, function(resp)
        if resp.ok then
            gui.notify:success(string.format("探针 OK %d", resp.status), 2.0)
            push_log("<", string.format("HTTP %d", resp.status))
        else
            gui.notify:error("探针失败：" .. (resp.error or "unknown"), 3.0)
            push_log("!", "HTTP fail: " .. (resp.error or ""))
        end
    end, 3)
end)

g_conn:button("connect", "Connect", function()
    if state.ws_id ~= 0 and net.ws:is_open(state.ws_id) then
        gui.notify:warn("已连接，请先 Disconnect", 1.5)
        return
    end
    local url = gui.get("RemoteCfg.g_conn.url", "")
    if type(url) ~= "string" or url == "" then return end

    state.ws_id = net.ws:connect(url, {
        on_open = function(id)
            push_log("!", "OPEN id=" .. tostring(id))
            gui.notify:success("WebSocket 已连接", 2.0)
        end,
        on_message = function(id, msg)
            state.last_msg = msg
            push_log("<", msg)
            if string.sub(msg, 1, 4) == "ping" then return end
            apply_path_value(msg)
        end,
        on_error = function(id, err)
            push_log("!", "ERR " .. err)
            gui.notify:error("WebSocket 错误：" .. err, 3.0)
        end,
        on_close = function(id, code, reason)
            push_log("!", string.format("CLOSE code=%d", code))
            gui.notify:info(string.format("连接关闭 (%d)", code), 2.0)
        end,
    })
end)

g_conn:button("disconnect", "Disconnect", function()
    if state.ws_id == 0 then return end
    net.ws:close(state.ws_id)
    state.ws_id = 0
end)

local g_status = tab:group("g_status", "状态", 0, 0, 0, 0)
g_status:live_table("st", { "key", "value" }, function()
    local open = (state.ws_id ~= 0) and net.ws:is_open(state.ws_id) or false
    local row_state = open and "OPEN" or (state.ws_id == 0 and "IDLE" or "CLOSED")
    return {
        { cells = { "ws_id", tostring(state.ws_id) } },
        { cells = { "state", row_state },
          color = open and {0.20, 0.55, 0.30, 0.35} or {0.40, 0.40, 0.40, 0.25} },
        { cells = { "last_msg", state.last_msg or "" } },
    }
end, 80.0)

log.success("remote_config_push 已加载，点 Connect 开始")
```

APIs used: `net.ws`, `net.http:get`, `gui.find`, `gui.set`

---

## damage_logger

Damage logging to a local CSV plus HTTP POST archival. An ESP text callback is used as a polling hook to track HP / shield deltas, frame ticks flush the buffer, and a final flush runs on unload.

One of the few scripts that must explicitly listen for `script_unloaded` — its internal buffer only persists if written to disk explicitly.

```lua
local prev             = {}
local events_buf       = {}
local total_logged     = 0
local last_flush_clock = os.clock()
local recent           = {}

local function cfg_get(suffix, fallback)
    local e = gui.find("DmgLog.g_cfg." .. suffix)
    if not e then return fallback end
    local v = e:get()
    return v == nil and fallback or v
end

local function build_line(ev)
    return string.format("%.3f,%s,%s,%d,%d,%d,%d,%s\n",
        ev.t, (ev.name or ""):gsub(",", ";"), ev.team,
        ev.dmg_hp, ev.dmg_shield, ev.hp_after, ev.shield_after,
        ev.is_down and "1" or "0")
end

local function flush_now(silent)
    if #events_buf == 0 then
        if not silent then gui.notify:info("无待 flush 事件", 1.5) end
        return
    end
    local n = #events_buf
    local lines = {}
    for i = 1, n do lines[i] = build_line(events_buf[i]) end
    local payload = table.concat(lines)

    if cfg_get("to_file", false) then
        local fp = cfg_get("file_path", "logs/damage.csv")
        if type(fp) == "string" and fp ~= "" then
            local existing = file.exists(fp) and (file.read(fp) or "")
                          or "t,name,team,dmg_hp,dmg_shield,hp_after,shield_after,is_down\n"
            if not file.write(fp, existing .. payload) and not silent then
                gui.notify:error("写盘失败：" .. fp, 3.0)
            end
        end
    end

    if cfg_get("to_http", false) then
        local url = cfg_get("http_url", "")
        if type(url) == "string" and url ~= "" then
            net.http:post(url, payload, "text/csv", function(resp)
                if not resp.ok then log.warn("HTTP POST 失败：" .. (resp.error or "")) end
            end, 5)
        end
    end

    events_buf = {}
    total_logged = total_logged + n
    last_flush_clock = os.clock()
    if not silent then gui.notify:success(string.format("已 flush %d 条", n), 2.0) end
end

local tab   = gui.tab("DmgLog")
local g_cfg = tab:group("g_cfg", "归档配置", 0, 0, 0, 0)
g_cfg:checkbox("to_file",  "写本地文件", false)
g_cfg:input_text("file_path", "本地路径", "logs/damage.csv")
g_cfg:checkbox("to_http",  "POST 到远端", false)
g_cfg:input_text("http_url", "远端 URL", "")
g_cfg:slider("flush_sec", "flush 间隔", 1, 60, 5):set_format("%d s")
g_cfg:checkbox("log_teammate", "记录队友伤害", false)

g_cfg:button("flush_now", "立即 flush", function() flush_now(false) end)
g_cfg:button("clear",     "清空缓冲",   function()
    events_buf = {}
    gui.notify:info("缓冲已清空", 1.5)
end)

local g_stat = tab:group("g_stat", "状态", 0, 0, 0, 0)
g_stat:live_table("st", { "key", "value" }, function()
    local tracked = 0
    for _ in pairs(prev) do tracked = tracked + 1 end
    return {
        { cells = { "pending",         tostring(#events_buf) } },
        { cells = { "total flushed",   tostring(total_logged) } },
        { cells = { "since flush",     string.format("%.1f s", os.clock() - last_flush_clock) } },
        { cells = { "tracked players", tostring(tracked) } },
    }
end, 100.0)

local g_log = tab:group("g_log", "最近事件", 0, 0, 0, 0)
g_log:live_table("ev_tbl",
    { "#", "t", "对象", "team", "Δhp", "Δsh", "hp", "sh", "down" },
    function()
        local rows = {}
        local n = #recent
        for i = n, 1, -1 do
            local ev = recent[i]
            local color = ev.is_down and {0.55, 0.20, 0.20, 0.35}
                       or ev.team == "ally" and {0.20, 0.40, 0.55, 0.30}
                       or nil
            rows[#rows + 1] = {
                cells = { tostring(n - i + 1), string.format("%.1f", ev.t),
                          ev.name or "", ev.team,
                          tostring(ev.dmg_hp), tostring(ev.dmg_shield),
                          tostring(ev.hp_after), tostring(ev.shield_after),
                          ev.is_down and "✓" or "·" },
                color = color,
            }
        end
        return rows
    end, 240.0)

esp.add("dmg_watch", function(p, ctx)
    local name = p.name
    if not name or name == "" then return "" end

    local cur_hp = p.health or 0
    local cur_sh = p.shield or 0
    local cur_dn = p.is_down or false
    local is_team = p.is_teammate or false

    local p_prev = prev[name]
    if not p_prev then
        prev[name] = { hp = cur_hp, shield = cur_sh, down = cur_dn }
        return ""
    end

    local dhp = math.max(0, p_prev.hp - cur_hp)
    local dsh = math.max(0, p_prev.shield - cur_sh)
    local down_changed = (cur_dn ~= p_prev.down)

    if dhp > 0 or dsh > 0 or down_changed then
        if (not is_team) or cfg_get("log_teammate", false) then
            local ev = {
                t = os.clock(), name = name,
                team = is_team and "ally" or "enemy",
                dmg_hp = dhp, dmg_shield = dsh,
                hp_after = cur_hp, shield_after = cur_sh,
                is_down = cur_dn,
            }
            events_buf[#events_buf + 1] = ev
            if #recent >= 30 then table.remove(recent, 1) end
            recent[#recent + 1] = ev
        end
    end

    p_prev.hp, p_prev.shield, p_prev.down = cur_hp, cur_sh, cur_dn
    return ""
end, {
    kind = "text",
    label = "Damage Watcher",
    colors = { {0,0,0,0}, {0,0,0,0}, {0,0,0,0}, {0,0,0,0} },
})

event.on("frame_update", function(e)
    local interval = cfg_get("flush_sec", 5)
    if type(interval) ~= "number" then interval = 5 end
    if os.clock() - last_flush_clock >= interval and #events_buf > 0 then
        flush_now(true)
    end
end)

event.on("script_unloaded", function(ue)
    if ue.script_path ~= _SCRIPT_PATH then return end
    flush_now(true)
end)

log.success("damage_logger 已加载")
```

APIs used: `esp.add`, `event.on`, `file.read/write/exists`, `net.http:post`, `gui.find`
