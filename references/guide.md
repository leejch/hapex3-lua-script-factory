# Getting Started

Read this when you write your first script — from project layout to common pitfalls. API signatures and return values are in the per-module sidebar.

---

## Project layout

Lua scripts live in a `scripts/` directory next to the application and are auto-discovered at startup:

```
<app directory>/
├── <main executable>
└── scripts/
    ├── _test_*.lua         # leading underscore = sample, not auto-loaded
    ├── keybind_hint_pack.lua
    ├── low_health_alert.lua
    └── ...
```

Scripts starting with an underscore are not auto-loaded; load them manually with `script.load("_test_xx.lua")` or via the menu. Regular scripts are auto-loaded based on the script list in your config.

### Load order

```
1. Config system loads      reads default plan + current plan
2. Lua runtime inits        VM + bindings
3. Static menu built        aimbot / visuals / misc etc. attached
4. Startup scripts load     each entry in the config script list loaded sequentially
5. Menu / background threads spin up
```

When your script runs, the static menu is already mounted in the GUI tree, so `gui.set("aimbot.master", true)` can write any existing path. Sub-trees you create via `gui.tab("X")` get appended to the end. Multi-script load order is unstable — don't reference other scripts' paths from yours.

Loading via the menu "Load Script" button follows the same flow as auto-load, but the `script_loaded` event's `is_reload` field reflects whether it was a hot reload.

### `_SCRIPT_PATH` global

Injected before each script executes:

```lua
print(_SCRIPT_PATH)  -- "scripts/damage_logger.lua"
```

Used in `script_unloaded` events to detect whether *your* script is being unloaded:

```lua
event.on("script_unloaded", function(ue)
    if ue.script_path ~= _SCRIPT_PATH then return end
    -- handle only my own unload
end)
```

### `print` redirection

`print(...)` is redirected to `log.info(...)`. Stdlib output (`io.write`, `os.write`) is not redirected — don't use it.

### `log.*` vs `gui.notify`

| Purpose | Use | Visible where |
|---|---|---|
| Developer diagnostics, debug info, error trace | `log.info/success/warn/error` | In-menu console |
| User-facing message (action feedback, error alert) | `gui.notify:info/success/warn/error` | Floating toast, auto-dismisses in ~3-5s |

Rules of thumb:

- Script finished loading → `log.success("... registered")`, no user toast
- User clicked a button to trigger something → `gui.notify:success("Preset applied ...", 2.5)`
- Program error (cloud unreachable, file write failed) → both: `log.warn` for the trace, `gui.notify:error` so the user sees it

---

## Resource lifecycle

The six resource types below are **automatically released** when a script is unloaded (menu close button, `script.unload`, or app shutdown). You don't need to write `event.on("script_unloaded", ...)` cleanup for these:

| Resource | API |
|---|---|
| Event subscription | `event.on("frame_update", fn)` |
| ESP element | `esp.add("tag", fn, opts)` |
| Menu container & control | `gui.tab(...)` / `tab:group(...)` etc. |
| Keybind formatter | `input.format(path, fn)` |
| HTTP / WebSocket | `net.http:get` / `net.ws:connect` |
| Image texture | `file.image:load/svg/create` |

You only need to manually subscribe to the unload event when your script has **external side effects** to flush (write to disk, HTTP report):

```lua
event.on("script_unloaded", function(ue)
    if ue.script_path ~= _SCRIPT_PATH then return end
    flush_buffer_to_disk()
end)
```

---

## Cross-script communication

### `shared` global table

`shared` is a plain Lua table shared across all scripts:

```lua
-- Script A
shared.last_kill_time = os.clock()

-- Script B
event.on("frame_update", function(e)
    if shared.last_kill_time and (os.clock() - shared.last_kill_time) < 5.0 then
        -- a kill happened in the last 5 seconds
    end
end)
```

Properties:

- Writes are immediately visible to other scripts — no locks, no snapshots
- Lifetime is tied to the Lua state; not cleared on script unload
- Starts empty; naming is the script's responsibility

### Recommended: claim a namespace

```lua
shared.damage_logger = shared.damage_logger or {}
shared.damage_logger.last_event_t = os.clock()
shared.damage_logger.total = (shared.damage_logger.total or 0) + 1
```

Reader side:

```lua
local d = shared.damage_logger
if d and d.last_event_t then ... end
```

### Custom event bus

For more structured communication, use `event.emit` / `event.on`:

```lua
-- Script A
event.on("hp_changed", function(name, hp, old) print(name, old, "→", hp) end)

-- Script B
event.emit("hp_changed", "alice", 30, 100)
```

Subscriptions are auto-revoked on script unload.

### Don't use `gui.set/get` as a communication channel

`gui.set("MyTab.g.flag", true)` could be (ab)used to pass data between scripts, but avoid it:

- It goes through the config write path; every write triggers a frame-end snapshot publish to background reader threads
- Control types are constrained (bool/int/float/string)
- Path resolution has overhead

`shared.*` or custom events are the proper path for inter-script communication.

---

## Time & cadence

### `frame_update` cadence

`event.on("frame_update", fn)` fires once per render frame — tied to display refresh. 144 Hz monitor = 144 calls/sec, 240 Hz = 240/sec.

Implications:

- `draw.*` calls **must** go inside `frame_update`. The foreground draw list resets every frame; miss one frame and you get a blank flicker.
- Heavy work (data scans, network I/O) cannot run every frame — throttle (see below)

### Time functions

| Function | Meaning | Use for |
|---|---|---|
| `time.now()` | Wall clock seconds (alias of `os.clock()`) | Timers, throttling, anything "real seconds" |
| `time.delta()` | Last frame duration (seconds) | Speed integration (movement, animation lerp) |
| `time.game()` | In-game time | Sync with in-game clock (pauses when game pauses) |
| `time.frame_count()` | Cumulative render frame count | Modulo scheduling `% N == 0` |

You can also read `e.delta_time` from the `event.on("frame_update", fn)` callback — equivalent to `time.delta()`.

### Accumulator throttle

Doing heavy work every frame (player scan + slow DMA queries) will stutter. Standard template:

```lua
local accum = 0.0
event.on("frame_update", function(e)
    accum = accum + e.delta_time
    if accum < 0.5 then return end   -- once per 0.5s
    accum = 0.0
    do_heavy_work()
end)
```

### Frame modulo scheduling

Simpler "every N frames":

```lua
event.on("frame_update", function(e)
    if time.frame_count() % 60 == 0 then
        do_periodic_thing()
    end
end)
```

### Debounce: at most once per N seconds

```lua
local last_alert = {}

local function should_fire(key)
    local t = os.clock()
    local prev = last_alert[key] or 0.0
    if t - prev < 4.0 then return false end
    last_alert[key] = t
    return true
end
```

Good for suppressing repeated notifications when a player stays in a triggering state.

---

## Example scripts

Full annotated source: Example Scripts. The eight scripts cover:

| Script | What it demonstrates |
|---|---|
| `keybind_hint_pack.lua` | Three return shapes of `input.format` (string / table / threshold colorize) |
| `low_health_alert.lua` | ESP text element + debounced notification + entity field access |
| `tactical_theme.lua` | ESP scenario palette bulk switching + Combobox callback |
| `perf_hud.lua` | Floating window + rolling average + `live_table` |
| `loadout_presets.lua` | Multi-preset one-click switch + sub-tab show/hide |
| `loot_inspector.lua` | Entity iteration + filter + `live_table` |
| `remote_config_push.lua` | WebSocket four callbacks + remote push hot-edit |
| `damage_logger.lua` | ESP polling + frame-pace flush + file + HTTP composite |

---

## Common pitfalls

### No `input.is_down(vk)`

The API does not expose `input.is_down(VK_F1)` / `GetAsyncKeyState` style "is the player holding F1 right now" queries. HApex3.0 is a dual-machine setup — the app runs on one machine, the player on another. OS key APIs read the *app's* keyboard, not the player's. To check player keys, use:

- `game.localplayer.*` fields (e.g. `is_zooming`, `is_grenade`) — read from game memory
- `input.is_active(path)` — checks whether a menu hotkey is in the active state

To react to a menu hotkey the user pressed, bind a `KeybindControl` and use `input.format` to show its state.

### `draw.*` must be called every frame

The foreground draw list resets every frame:

```lua
-- Wrong: called at script top, drawn once and gone
draw.text(10, 10, draw.rgba(1,1,1,1), "Hello")

-- Right: re-drawn every frame via frame_update
event.on("frame_update", function(e)
    draw.text(10, 10, draw.rgba(1,1,1,1), "Hello")
end)
```

Missing a frame = a blank flicker that frame.

### Colon `:` vs dot `.` calling rules

| Syntax | Use case |
|---|---|
| `obj:method(args)` | Stateful object methods: `gui.find(p):set(v)` / `tab:group(...)` / `net.http:get(...)` / `net.ws:connect(...)` / `file.image:load(...)` |
| `obj.field` | Read-only data field: `player.health` / `event.delta_time` / `game.localplayer.weapon` |
| `module.func(args)` | Module function: `gui.set(p, v)` / `esp.add(...)` / `log.info(...)` / `time.now()` |

Mixing them produces a `bad self argument` error. Module functions always use dot. Stateful object methods always use colon.

`net.http:get` / `net.ws:connect` use colon because `net.http` / `net.ws` are objects, not plain tables.

### Weapon config paths

Weapon configuration flows through the same `gui.set/get` path syntax: `aimbot.weapon.<id>.<sub>`. For the currently held weapon, get the prefix from `gui.get_active_override_path()`. See `gui` weapon configuration.

```lua
gui.set("aimbot.weapon.r301.aim.fov_hip", 12.5)
local p = gui.get_active_override_path()
if p ~= "" then gui.set(p .. ".aim.bone_target", 2) end
```

Field names follow the C++ SCHEMA; an invalid path returns nil / silently no-ops.

### Same-frame `set` then `get` is visible

```lua
gui.set("aimbot.master", true)
local v = gui.get("aimbot.master")  -- returns true immediately, no need to wait
```

`gui.get` / `Window:get_open` and other menu-thread read paths go through "current frame latest value" — visible same-frame. Background reader threads always go through the snapshot published at frame end.

### No `net.http:get_sync`

The API does not provide synchronous HTTP — it would block the menu thread and freeze the GUI during script load. Correct pattern:

```lua
net.http:get("https://example.com", function(resp)
    if resp.ok then
        -- handle resp.body
    else
        log.warn("HTTP fail: " .. (resp.error or ""))
    end
end, 3)  -- 3s timeout
```

The callback runs on the menu thread; you can call `gui.set` / `gui.notify:*` directly inside.

### Combobox indices are 1-based

```lua
group:combobox("playstyle", "...", { "Default", "Holder", "Rusher", "Safe" }, 2)
--                                                                          ^ default = "Holder"
```

The `on_change(fn)` callback signature is also `fn(idx_1based, name)`. Combobox defaults and indices in Lua are **always 1-based**.

`gui.get/set` return/accept the underlying stored value, which is still a 0-based int. When converting between Combobox-facing and storage-facing values, remember `+1` / `-1`.

### Iterate entity tables with `pairs`, not `#`

```lua
-- Wrong
local n = #game.entities.loots

-- Right
local n = 0
for _ in pairs(game.entities.loots) do n = n + 1 end
```

`game.entities.{players, loots, projectiles}` are userdata-backed tables; `#` returns 0 or undefined. `pairs` works correctly.
