---
name: hapex3-lua
description: Use when writing or debugging Lua scripts for HApex3.0. Covers the 14-module Lua API (event, gui, esp, net, game, draw, math, file, input, log, script, time, config, json), calling conventions (colon vs dot, 1-based Combobox, no input.is_down on dual-machine setups), automatic resource cleanup on script unload, the 8 reference scripts shipped with the product, and the frame_update timing model. Apply this skill any time the user mentions writing/editing/debugging .lua scripts for HApex3.0 / HOOZi.
---

# HApex3.0 Lua Scripting

This skill assists writing and debugging Lua scripts for HApex3.0. Scripts live in `<app dir>/scripts/<name>.lua` and have access to a 14-module API surface (menu controls, ESP elements, networking, drawing, game state, etc.).

## When to invoke

User signals to apply this skill:
- Any mention of writing / editing / debugging a `.lua` script for HApex3.0 or HOOZi
- Questions about specific API: `gui.find`, `esp.add`, `net.http`, `draw.text`, `game.localplayer`, `event.on`, etc.
- "How do I make an ESP element / watermark / toast / hotkey hint" type asks
- Help porting old patterns to current API

If the user just mentions HApex3.0 generally (not Lua), this skill does not apply.

## Core conventions

These trip people up. Apply when reading user code.

### Colon `:` vs dot `.`

| Syntax | Used for |
|---|---|
| `obj:method(args)` | stateful object methods — `gui.find(p):set(v)`, `tab:group(...)`, `net.http:get(...)`, `net.ws:connect(...)`, `file.image:load(...)`, `gui.notify:success(...)` |
| `obj.field` | read-only data fields — `player.health`, `event.delta_time`, `game.localplayer.weapon` |
| `module.func(args)` | module functions — `gui.set(p, v)`, `esp.add(...)`, `log.info(...)`, `time.now()`, `draw.line(...)` |

Mixing causes `bad self argument`. `net.http:get` and `net.ws:connect` use colon because `net.http` / `net.ws` are objects, not plain tables.

### Combobox indices are 1-based

```lua
group:combobox("kind", "...", { "Default", "A", "B", "C" }, 2)  -- default = "A"
```

`on_change(fn)` callback signature is `fn(idx_1based, name)`. But `gui.get(path)` returns the underlying 0-based int — convert with `+ 1` when feeding it back.

### `draw.*` MUST be called every render frame

The foreground draw list resets each frame. Drawing once at script top is invisible. Always inside `event.on("frame_update", fn)`.

```lua
-- WRONG
draw.text(10, 10, draw.rgba(1,1,1,1), "hi")

-- RIGHT
event.on("frame_update", function(e)
    draw.text(10, 10, draw.rgba(1,1,1,1), "hi")
end)
```

### No `input.is_down(vk)` on dual-machine setups

HApex3.0 runs on a separate machine from the player. OS key APIs read the program-machine's keyboard, not the player's. Query player state via:
- `game.localplayer.*` fields (`is_zooming`, `is_grenade`, `is_down`, ...) — read from game memory
- `input.is_active(menu_path)` — check menu hotkey active state

### Iterating game entities — use `pairs`, not `#`

```lua
-- WRONG
local n = #game.entities.loots

-- RIGHT
local n = 0
for _ in pairs(game.entities.loots) do n = n + 1 end
```

`game.entities.{players,loots,projectiles}` are userdata-backed tables. `pairs` works, `#` returns 0 / undefined.

### Resources are auto-cleaned on script unload

Don't manually subscribe to `script_unloaded` for these — they release automatically:
- `event.on` subscriptions
- `esp.add` elements
- `gui.*` containers and controls
- `input.format` formatters
- `net.http` callbacks and `net.ws` connections
- `file.image:load/svg/create` textures

Only handle `script_unloaded` when the script has external side effects to flush (writing buffer to disk, posting final HTTP).

### `gui.set` then `gui.get` — same-frame visible

```lua
gui.set("aimbot.master", true)
local v = gui.get("aimbot.master")  -- already true, no frame wait
```

Menu-thread reads return the current frame value. Background threads still see the previously published snapshot.

### Weapon config paths

Weapon configuration is accessed by path, no separate object:

```
aimbot.weapon.<weapon_id>.<sub_path>
```

- `<weapon_id>` is a string like `"r301"` or `"default"` (baseline)
- `<sub_path>` follows the SCHEMA on the C++ side: `aim.fov_hip`, `aim.pid.kp`, `aim.max_dist_range[2]` (1-based arrays), `trigger_release`, `filter_tags[3]`, etc.

For the currently held weapon, get the prefix from `gui.get_active_override_path()`. Return value matches the aim thread's actually-effective config:
- Held weapon in armory (or its group is) → `"aimbot.weapon.<id>"`
- Held weapon NOT in armory → `"aimbot.weapon.default"` (the fallback config that's actually driving aim)
- Player not alive / state unavailable → `""`

```lua
local p = gui.get_active_override_path()
if p ~= "" then
    gui.set(p .. ".aim.fov_hip", 12.5)
    gui.set(p .. ".aim.bone_target", 2)
end
```

Field names follow C++ SCHEMA. Failure modes — all silently no-op (`gui.set`) / return nil (`gui.get`):
- Weapon ID not in armory → **not** auto-created, **not** fallback to default
- Unknown field name / OOB index / type mismatch

Writes that fail this validation don't trigger a config snapshot publish.

### No `net.http:get_sync`

Synchronous HTTP would block the menu thread. Always async with callback:

```lua
net.http:get(url, function(resp)
    if resp.ok then ... else log.warn(resp.error) end
end, 5)
```

## When to load references

When the user asks for specifics that go beyond these conventions, load the referenced file:

| User intent | Load |
|---|---|
| Parameter / return / field details for a specific module | `references/api-reference.md` (all 14 user-facing modules concatenated) |
| Complete working example for a use case | `references/examples.md` (8 fully-commented scripts) |
| Project structure, lifecycle, cross-script communication, timing patterns | `references/guide.md` |

Load on demand — each is large. For an API question like "what does `esp.add` accept?", load just `api-reference.md`. For "how do I write a damage logger?", load `examples.md`.

## Module summary

```
Core 9:
  event   subscriptions + custom event bus
  gui     menu UI + config writes
  esp     ESP elements (text / bar / mixed / free)
  net     HTTP + WebSocket (async only)
  game    real-time read-only data
  draw    primitive drawing (line/rect/circle/triangle/quad/polyline/text/image)
  math    vectors + projection + easing curves
  file    sandboxed file IO + image resources
  input   hotkey state + formatter

Utility 5:
  log     console diagnostics (info/success/warn/error)
  script  load / unload
  time    now / delta / game / frame_count
  config  plan switching
  json    encode / decode

Notifications live under gui.notify (4 levels, colon-call):
  gui.notify:info / :success / :warn / :error (text, dur?)
```

## Output preferences when generating scripts

When you write or edit a `.lua` script for the user:

- File header: 4-5 lines of plain comments stating *what the script solves* and *what API it uses*. No "Phase X" / "PR-N" / "v2 rewrite" markers.
- Comments inside the script: explain *why* (non-obvious decisions, threshold rationale), not *what* (well-named identifiers do that).
- Use `log.success("...")` at the end after successful registration, not `print`.
- For user-visible feedback to button clicks etc., use `gui.notify:success/info/warn/error(text, dur?)` (colon call).
- Vec2 / Vec3 operations: prefer operators (`a + b`, `v * scalar`) over methods (`a:add(b)`) — more idiomatic in Lua.
- For repeated frame work, prefer `if time.frame_count() % N == 0 then` over manual accumulators when the cadence doesn't have to be wall-clock accurate.
- Script comments must be written in Simplified Chinese. This applies to file headers, inline explanatory comments, and manual verification notes inside `.lua` files. Code identifiers, API names, module names, and runtime-required strings should stay in the language or format required by HApex3.0 Lua.
