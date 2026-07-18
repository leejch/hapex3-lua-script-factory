---
name: hapex3-lua
description: Write, edit, review, or debug HApex3.0 / HOOZi Lua scripts with the complete 17-module API (event, gui, esp, net, game, draw, math, file, input, log, script, time, config, json, utils, mem, offsets), globals, lifecycle rules, and official examples. Use whenever a request concerns HApex3.0/HOOZi Lua files or any of these APIs, including low-level memory and offset access; do not use for generic HApex3.0 product questions unrelated to Lua scripting.
---

# HApex3.0 Lua Scripting

This skill assists writing and debugging Lua scripts for HApex3.0. Scripts live in `<app dir>/scripts/<name>.lua` and have access to 17 user-facing modules plus the global runtime surface.

## Scope

Use this pack for HApex3.0/HOOZi Lua work. Generic product questions that do not involve scripting are outside its scope.

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

The foreground draw list resets each frame. Drawing once at script top is invisible. Always draw inside `event.on("frame_update", fn)` or `event.on("render_post", fn)`.

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
- pending `Delay(...)` callbacks
- `esp.add` elements
- `gui.*` containers and controls
- `input.format` formatters
- `net.http` callbacks, `net.ws` connections, and `net.ws_server` listeners/clients
- `file.image:load/svg/create/load_gif` textures

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
    if resp.ok then
        log.info(resp.body)
    else
        log.warn(resp.error)
    end
end, 5)
```

### Low-level memory access is synchronous and writes are dangerous

Prefer typed `game.*` fields. When using `mem` and `offsets`, resolve patterns and dynamic offsets once, cache them, and batch per-frame work with `mem.scatter` / `mem.write_scatter`. A successful `mem.is_valid` check only proves a pointer is in range; it does not prove the field is semantically correct. Treat every `mem.write_*` call as capable of corrupting state or crashing the game.

## Live documentation and local references

Use the official `hapex-lua` MCP server at `https://docs.hoozi.cc/mcp` as the first source for current API facts when its tools are available:

1. Call `list_modules` first to discover the current surface.
2. Call `get_module_api` for the module being used, or `search_api` for a symbol whose module is unknown.
3. Call `get_guide` for lifecycle/timing/pitfalls and `get_examples` for official full scripts.

Use the local files below when MCP is unavailable, when offline work is required, or when the repository's locally adapted guidance is relevant. If MCP, local references, and the website conflict, the current MCP/official website is authoritative.

When the user asks for specifics that go beyond these conventions, load the referenced file:

| User intent | Load |
|---|---|
| Parameter / return / field details for a specific module | `references/api-reference.md` (global surface + all 17 user-facing modules) |
| Complete working example for a use case | `references/examples.md` (8 fully-commented scripts) |
| Project structure, lifecycle, cross-script communication, timing patterns | `references/guide.md` |

Load on demand — each is large. For an API question like "what does `esp.add` accept?", load just `api-reference.md`. For "how do I write a damage logger?", load `examples.md`.

The local references were rebuilt from [the official HOOZi 3.0 Lua documentation](https://docs.hoozi.cc/products/apex/dev/) and re-verified through the official `hapex-lua` MCP server on 2026-07-18.

## Module summary

```
Core 9:
  event   subscriptions + custom event bus
  gui     menu UI + config writes
  esp     ESP elements (text / bar / mixed / free)
  net     async HTTP + WebSocket client/server
  game    real-time read-only data
  draw    primitive drawing (line/rect/circle/triangle/quad/polyline/text/image)
  math    vectors + projection + easing curves
  file    sandboxed file IO + static/animated image resources
  input   hotkey state + formatter + clipboard

Utility 8:
  log     console diagnostics (info/success/warn/error)
  script  load / unload
  time    now / delta / game / curtime / frame_count
  config  plan switching
  json    encode / decode
  utils   encoding + hashing + date/time + script-scoped KV storage
  mem     low-level DMA read/write + pattern scan + scatter batches
  offsets dumper-synchronized named offset table

Globals:
  _SCRIPT_PATH / print / Delay / shared

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
