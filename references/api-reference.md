# HApex3.0 Lua API Reference

Field lookup index. One section per module: signatures + parameters + behavior + examples.

---



## Globals + Overview

Quick reference: module structure overview, style conventions, global variables. Each module's detailed fields and signatures are in the corresponding sidebar page.

---

## Module Structure Overview

```
══ Globals ═════════════════════════════════════════════════════════════
_SCRIPT_PATH        Current script path (read-only)
print               Redirected to log.info
shared              Cross-script shared Lua table

══ Primary domain 9 ═══════════════════════════════════════════════════

event                                   Subscribe
├─ on(name, fn) → handle
└─ off(handle)

gui                                     Menu UI + config write (the only write path)
├─ tab / sub_tab / window
├─ find / get / set
├─ show / hide / set_enabled / set_visible
└─ Container methods: group/checkbox/slider/slider_float/dropdown/
              combobox/slider_range/color_edit/input_text/multi_dropdown/
              keybind_control/tips/live_table/button
   Window only: bind_visible

esp                                     ESP elements
├─ add / find / remove
├─ elements / scenario
└─ INV / VIS / DWN / ALLY

net
├─ http: get / post                       Async only (callback dispatched on menu thread)
└─ ws:   connect / send / close / is_open All async (4 callbacks + queued send)

game                                    Live data (read-only, writes raise an error)
├─ localplayer
├─ entities.{players,loots,projectiles}
├─ aimbot
├─ trigger
└─ world.{ring,map_name}

draw                                    Screen drawing
├─ line / rect / circle / text / image
├─ measure / screen
└─ rgba / u8 / hex

math                                    Extends Lua stdlib
├─ Vec2 / Vec3 / Lerp / Clamp
├─ AngleNormalize / CalcAngle
└─ WorldToScreen

file                                    Files + resources
├─ read / write / exists / remove
└─ image: load / svg / create / get / has / list / remove

input                                   Input (includes keybind formatter)
├─ is_active / format / unformat

══ Misc 6 ══════════════════════════════════════════════════════════════

log         info / success / warn / error
notify      info / success / warn / error
script      load / unload
time        now / delta / game / frame_count
config      save / save_as / switch / list / current
json        encode / decode
```

---

## Style Conventions

| Form | Purpose |
|---|---|
| `obj:method(args)` | Stateful object methods (gui.find, network, file resources, esp element) |
| `obj.field` | Read-only data fields (game.* / event parameters / entity attributes) |
| `module.sub.field` or `module.sub:method` | Nested namespace (`net.http` / `game.entities` / `file.image`) |
| `module.func(args)` | Module shortcut function |

**Naming**: modules are all-lowercase single words / functions and fields are snake_case / constants are SCREAMING_CASE / usertypes are CamelCase / event names are snake_case strings.

**Owner-scoped auto cleanup**: When a script is unloaded, the following resources are released automatically; you don't need to hand-write a `script_unloaded` listener.

- `event.on` subscriptions
- `esp.add` elements
- Containers and controls created via `gui.*`
- `input.format` keybind formatters
- `net.http:get/post` callbacks (alive flag)
- `net.ws:connect` connections
- `file.image:load/svg/create` textures

---

## Global Variables

### `_SCRIPT_PATH : string` (read-only)
The path of the currently executing script (relative to `scripts/`). Injected by the runtime before the script is loaded.

### `print(...)`
Redirected to `log.info`.

### `shared : table`
A plain Lua table shared across scripts. Any script can read or write it; its lifetime matches the Lua state. Writes are visible to other scripts immediately — no snapshot, no lock.

**Reload does not clear it**: script reload only unloads the GUI / event / esp resources registered by that script. `shared` itself is created once when the Lua state is built and is never wiped. A script that wants its own namespace reset on reload must do `shared.my_ns = {}` itself at the top.

See Getting Started for usage patterns.


---


## event

Event subscriptions. Subscriptions are revoked automatically when the script is unloaded; no need to hand-write `event.off`.

---

## `event.on(name, fn) → handle`

**Parameters**
- `name : string` — event name, one of the table below
- `fn : function` — callback

**Event names + callback signatures**

| Event name | Callback signature | Fields |
|---|---|---|
| `"frame_update"` | `fn(e)` | `e.delta_time : number` — z-order below ESP |
| `"render_post"` | `fn(e)` | `e.delta_time : number` — z-order above ESP / FOV / menu |
| `"config_changed"` | `fn(e)` | `e.module_name : string` |
| `"script_loaded"` | `fn(e)` | `e.script_path : string`, `e.is_reload : bool` |
| `"script_unloaded"` | `fn(e)` | `e.script_path : string` |
| `"menu_toggled"` | `fn(e)` | `e.visible : bool` |
| `"weapon_changed"` | `fn(e)` | `e.prev_weapon : int`, `e.curr_weapon : int` (sdk::ItemId) |
| `"map_changed"` | `fn(e)` | `e.prev_map : string`, `e.curr_map : string` |
| `"player_knocked"` / `"player_revived"` / `"player_died"` / `"player_respawned"` | `fn(e)` | `e.player_index`, `e.name`, `e.team_num`, `e.is_local`, `e.is_teammate` |

All events share base fields `e.timestamp : int` (millis), `e.source : string`.

> **`frame_update` vs `render_post` z-order**: `frame_update` writes vtx that lands *before* ESP / FOV / menu drawings; `render_post` writes vtx that lands *after*. Both use screen-relative coordinates. HUD-style mods overlaying ESP should use `render_post`; underlying info display should use `frame_update`.
>
> **Both fire once per render frame** (bound to the screen render cadence — at 144Hz / 240Hz it fires 144/240 times per second). `draw.*` must be hooked in `frame_update` or `render_post` and called every frame — the foreground draw list is reset every frame; missing a frame produces a flicker.
>
> Heavy work should be throttled by the script itself by accumulating `e.delta_time`. See Getting Started.

**Returns**: `handle : number` — used for `event.off`.

---

## `event.off(handle)`

Explicitly unsubscribe (usually not needed manually).

---

## Custom Events (cross-script)

Beyond the 4 built-in events above, any **other event name** goes through the Lua custom-event channel.

### `event.on(name, fn) → handle`
Any `name` not in the built-in event list automatically uses the custom channel. The `fn` signature is `function(...)` — it receives all arguments forwarded from `event.emit(name, ...)`.

### `event.emit(name, ...)`
Fires a custom event, dispatching synchronously to all handlers registered under `name`. **Emitting a built-in event name is not allowed** (to prevent scripts from forging system events); attempting to emit `"frame_update"` etc. is rejected.

Handler exceptions are caught and do not interrupt subsequent dispatch. When a script is unloaded, all custom-event subscriptions registered by that script are revoked automatically.

```lua
-- Script A: listener
event.on("hp_changed", function(player_name, new_hp, old_hp)
    print(player_name, "hp:", old_hp, "→", new_hp)
end)

-- Script B: broadcast
event.emit("hp_changed", "alice", 30, 100)
```

---

## Example

```lua
event.on("frame_update", function(e)
    -- Called every render frame; dt is equivalent to time.delta()
    do_something(e.delta_time)
end)

event.on("script_unloaded", function(ue)
    if ue.script_path ~= _SCRIPT_PATH then return end
    -- Only handle our own unload (rare cases: flush buffers)
end)
```


---


## gui

Menu UI + config writes (the **only** write path). After creating a container, keep the returned object reference and mount child elements through its methods.

---

## Top-level Creation + Lookup

### `gui.tab(name) → Tab`
**Parameter**: `name : string` — used as both id and label.

### `gui.sub_tab(parent, id, label) → Tab`
**Parameters**: `parent : Tab`, `id : string`, `label : string`

### `gui.window(id, title, w, h, flags?) → Window`
**Parameters**: `id : string`, `title : string`, `w : number`, `h : number`, `flags? : int = 0`

### `gui.find(path) → GUIElement | nil`
**Parameter**: `path : string` — full path (dot-separated, e.g. `"aimbot.master"`).

**Returns**: a derived-type object (Checkbox / Slider / Combobox / Window / Groupbox / Tab / …). `nil` means the path does not exist.

### `gui.get(path, fallback?) → value | fallback`
**Parameters**: `path : string`, `fallback? : any = nil`

Internally = `gui.find(path):get()` with a nil check.

### `gui.set(path, value)`
**Parameters**: `path : string`, `value : any`

Internally = `gui.find(path):set(value)`.

### `gui.show(paths)` / `gui.hide(paths)`
**Parameter**: `paths : table<string>` — list of control full paths.

### `gui.set_enabled(paths, state)` / `gui.set_visible(paths, state)`
**Parameters**: `paths : table<string>`, `state : bool`

---

## Weapon Configuration Read/Write

Weapon configuration is accessed through `gui.set` / `gui.get`. Two path shapes both edit the same underlying `WeaponConfig`:

| Path shape | Which weapon | When to use |
|---|---|---|
| **Menu path**: `aimbot.legit.fov.dead` | The weapon currently selected in the menu | Matches UI flow; copy directly from the "show component path" tooltip |
| **Storage path**: `aimbot.weapon.<id>.aim.fov_dead` | The specific `<id>` weapon (ignores UI selection) | Batch-edit multiple weapons, run presets, or write while not alive |

> **Menu tooltip**: with "show component path" on, hovering a per-weapon control shows `Storage: aimbot.weapon.<id>.<field>` + `Menu: aimbot.legit.<...>`; right-click copies the storage path. Batch (multi-select) mode adds `(batch: N weapons)`. Global (non-per-weapon) controls show only the single menu path.

### Menu paths (recommended for daily use)

```lua
gui.set("aimbot.legit.fov.dead",  0.5)   -- current selected weapon: dead zone
gui.set("aimbot.legit.fov.hip",   12.0)  -- current selected weapon: hip FOV
gui.set("aimbot.legit.smoothadv.kp", 1.8)
```

Whichever weapon is selected in the menu is the one written. default selected → writes to default; r301 selected → writes to r301.

**Two caveats**:
- **Batch mode writes only the first weapon**: with multiple weapons multi-selected in the UI, a Lua menu-path `gui.set` only writes to the first one in `selected_weapon_ids` — unlike dragging the slider in the UI, which truly batches. To batch from Lua, loop over storage paths instead.
- **`@weapon_id` suffix forces a specific weapon**: `aimbot.legit.fov.dead@r301` bypasses the UI selection by binding the groupbox to `r301` for this call. Closer to the UI mental model than looping over storage paths when you want to touch a handful of weapons.

### Storage paths (specific weapon)

Format: `aimbot.weapon.<weapon_id>.<sub_path>`

- `<weapon_id>`: string weapon ID like `"r301"` / `"flatline"`; `"default"` is the baseline
- `<sub_path>`: WeaponConfig field (dot-nested + 1-based `[n]` for arrays)

```lua
-- Specific weapon: hard-code the ID (unaffected by UI selection)
gui.set("aimbot.weapon.r301.aim.fov_hip", 12.5)
gui.set("aimbot.weapon.flatline.aim.fov_hip", 12.5)
gui.set("aimbot.weapon.default.filter_tags[3]", true)

-- Nested field / array
gui.set("aimbot.weapon.r301.aim.pid.kp", 1.8)
gui.get("aimbot.weapon.r301.aim.max_dist_range[2]")
```

Field names follow the C++ SCHEMA; not enumerated here.

**Write failure semantics**: all three of these silently no-op — no Lua error, no config snapshot publish:
- Weapon ID not added to armory (e.g. `aimbot.weapon.unknown.aim.fov_hip`) — does *not* silently fall back to default
- Unknown field (typo, e.g. `aimbot.weapon.r301.aim.fov_hipx`)
- Array index out of range / type mismatch (e.g. writing a string to a float field)

Reads (`gui.get`) the same: any of the above returns `nil` (or your fallback arg).

### `gui.get_active_override_path() → string`

Returns the storage-path prefix of the **config that actually drives the aimbot right now** for the held weapon. Semantics match the aim thread's internal `resolve_active_weapon`:

| Current state | Returns |
|---|---|
| Held weapon is in a group + group is in armory | `"aimbot.weapon.<group_id>"` |
| Held weapon standalone + in armory | `"aimbot.weapon.<weapon_id>"` |
| Held weapon **not in armory** (armory disabled for it) | `"aimbot.weapon.default"` |
| ClientData snapshot unavailable (DMA disconnected / loading) | `""` |

```lua
local p = gui.get_active_override_path()
if p ~= "" then
    gui.set(p .. ".aim.bone_target", 2)  -- writes to the actually-effective config
end
```

This differs from "menu selected weapon": it looks at the **in-game held** weapon (`lp.weapon_enum` resolved via `enum_to_weapon_id` + armory check), the menu selection doesn't affect it. The empty string is reserved for genuinely-no-state cases (dead, loading) — any alive state returns at least `aimbot.weapon.default`.

---

## Notifications (gui.notify)

`gui.notify` is a sub-table; call its methods with `:`:

### `gui.notify:info(text, dur?)` / `:success` / `:warn` / `:error`
**Parameters**: `text : string`, `dur? : number = 4.0` (lifetime in seconds)

```lua
gui.notify:info("hello")
gui.notify:success("Preset applied", 2.5)
gui.notify:warn("Distance too far", 1.5)
gui.notify:error("HTTP failed: " .. err, 3.0)
```

| level | color | use for |
|---|---|---|
| info | white | normal operation feedback |
| success | green | positive confirmation |
| warn | yellow | soft warning |
| error | red | error alert |

---

## Container Methods (shared by Tab / Window / Groupbox)

### `:group(id, label, x, y, w, h) → Groupbox`
**Parameters**: `id : string`, `label : string`, `x/y/w/h : number`

### `:button(id, label, callback?) → Button`
**Parameters**: `id : string`, `label : string`, `callback? : function()`

### `:checkbox(id, label, default) → Checkbox`
**Parameters**: `id : string`, `label : string`, `default : bool`

### `:slider(id, label, min_v, max_v, def) → Slider` (integer)
**Parameters**: `id : string`, `label : string`, `min_v / max_v / def : int`

### `:slider_float(id, label, min_v, max_v, def) → SliderFloat`
**Parameters**: `id : string`, `label : string`, `min_v / max_v / def : number`

### `:range_slider_float(id, label, min_v, max_v, def_v1, def_v2, min_range?) → RangeSliderFloat`
**Parameters**: 5 numbers + `min_range? : number = 0`

### `:range_slider_int(id, label, min_v, max_v, def_v1, def_v2, min_range?) → RangeSliderInt`
**Parameters**: 5 ints + `min_range? : int = 0`

### `:dropdown(id, label, items, def) → Combobox`
**Parameters**: `id : string`, `label : string`, `items : table<string>`, `def : int` (**1-based** default index; the binding layer converts to 0-based internally. `gui.get/set` reads/writes the internal field directly so that side is 0-based int)

(The usertype is still named `Combobox` — historical naming, used in the control-methods section below. Multi-select variant is `:multi_dropdown`.)

### `:input_text(id, label, def) → InputText`
**Parameters**: `id : string`, `label : string`, `def : string`

### `:color_edit(id, label, r, g, b, a?) → ColorEdit`
**Parameters**: `id : string`, `label : string`, `r / g / b : number`, `a? : number = 1.0`

### `:multi_dropdown(id, label, items, defaults?) → MultiDropdown`
**Parameters**: `id : string`, `label : string`, `items : table`, `defaults? : table<bool>`

### `:keybind_control(id, label, def_key?, def_mode?) → KeybindControl`
**Parameters**: `id : string`, `label : string`, `def_key? : int = 0`, `def_mode? : int = 0`

### `:live_table(id, headers, provider, height?)` (Window / Groupbox only)
**Parameters**: `id : string`, `headers : table<string>`, `provider : function() → table<row>`, `height? : number = 0`

`row` shape: `{cell1, cell2, ...}` array, or `{cells = {...}, color = {r,g,b,a}}` table.

### `:tips(id, text, icon?, color?)` (Window / Groupbox only)
**Parameters**: `id : string`, `text : string`, `icon? : string`, `color? : table<r,g,b,a>`

---

## Window-only Methods

### `Window:is_open() → bool` / `Window:set_open(bool)`

### `Window:bind_visible(checkbox) → Window`
**Parameter**: `checkbox : Checkbox` — reference to any Checkbox object (returned by `:checkbox(...)`).

Each frame auto-syncs `Window.open = checkbox.value`, saving you from writing `set_open` inside a `live_table` provider.

---

## Checkbox / Slider / Combobox Control Methods

### `Checkbox:set_keybind(vk, mode)`
**Parameters**: `vk : int`, `mode : int` (0=Toggle, 1=Hold, 2=Always)

### `Checkbox:set_colors(table)` / `Checkbox:get_colors() → table`
Custom palette for checkboxes that carry keybind state (current/inactive/hover/...).

### `:set_hint(text) → self`
Available on: Checkbox / Slider / SliderFloat / RangeSliderFloat / RangeSliderInt / InputText / KeybindControl. Combobox / MultiDropdown / ColorEdit / Button **do not** have `:set_hint`.

### `Slider:set_format(fmt) → Slider` / `SliderFloat:set_format` / `RangeSliderFloat:set_format` / `RangeSliderInt:set_format`

### `Combobox:on_change(fn) → Combobox`
**Parameter**: `fn : function(idx_1based : int, name : string)` — 1-based index + selected item string.

### `Combobox:add_item(item) → Combobox` / `add_items(items)` / `remove_item(idx_or_name)` / `clear_items()`

### `Combobox:get_selected_name() → string` / `get_items() → table<string>`

### `InputText:set_size(vec2)`

### `Button:set_size(vec2)` / `set_icon(string)`

### `ColorEdit:set_colors(table)` / `set_alpha(bool)`

### `MultiDropdown:add_item(item, default?)` / `add_items(items)` / `remove_item(idx_or_name)` / `clear_items()` / `get_selected_names() → table<string>`

---

## GUIElement Base Methods (inherited by all controls)

### `:get_id() → string` / `:get_owner() → string` / `:get_label() → string` / `:set_label(str)`

### `:is_enabled() → bool` / `:set_enabled(bool)` / `:is_visible() → bool` / `:set_visible(bool)`

### `:get() → value` / `:set(value)` / `:has_value() → bool`
Path-based unified accessor for the control's current value (equivalent to `gui.get` / `gui.set`).

### `:bind_weapon(...)` / `:get_target_weapon(...)`
Control-level weapon binding (advanced).

---

## Example

```lua
local tab = gui.tab("MyTab")
local g   = tab:group("g", "My Group", 0, 0, 0, 0)

local cb = g:checkbox("enable", "Enable", false)
            :set_hint("Tick to turn the feature on")

local sl = g:slider_float("scale", "Scale", 0.0, 5.0, 1.0)
            :set_format("%.2fx")

local cb_theme = g:dropdown("theme", "Theme",
    { "Default", "Dark", "Light" }, 1)
    :on_change(function(idx_1based, name)
        log.info("Theme switched to: " .. name)
    end)

g:button("reset", "Reset", function()
    gui.set("MyTab.g.enable", false)
    gui.set("MyTab.g.scale",  1.0)
end)
```


---


## esp

ESP element registration. Each ESP element has 4 independent palettes (one per scenario: INV / VIS / DWN / ALLY); the system picks one automatically per player state. Scripts read `esp.scenario` for the current preview scenario, use `el:set_color(value, scenario)` to change a single scenario, or `el.colors = {c0,c1,c2,c3}` to batch-set all four in one line.

---

## `esp.add(id, fn, opts?) → ESPElement`

**Parameters**
- `id : string` — unique element identifier
- `fn : function(p : PlayerEntity, ctx : table)` — invoked per player, return value is polymorphic:

| `fn` returns | Behavior |
|---|---|
| `string` | text element |
| `number` 0..1 | bar element |
| `table` `{text=, text_color=, bar=, bar_color=}` | mixed |
| `nil` (already drawn via ctx.dl) | free drawing |
| `nil` (nothing drawn) | the player is not displayed |

- `opts?` — optional table
  - `label : string` — default = id
  - `colors : table` — 4-element `{c_inv, c_vis, c_dwn, c_ally}`, each = `{r,g,b,a}`
  - `dist : table` — `{min_m, max_m}`
  - `settings : function(group : Groupbox)` — callback for adding extra controls to this element
  - `kind : string` — `"text"` (default) / `"bar"` / `"mixed"` / `"free"`, controls slot-drag behavior:
    - `"text"` → 6 slots (top / top-left / bottom-left / top-right / bottom-right / bottom)
    - `"bar"`  → 4 slots (top / middle-left / middle-right / bottom)
    - `"mixed"` → 4 bar slots (strictest constraint; fn returns text + bar simultaneously)
    - `"free"` → not registered in the slot UI (no drag handle); user fully draws via `ctx.dl` / `draw.*`;
      `scenarios` / `dist` / `cleanup` still apply; fn return value is arbitrary (the slot system does not consume it).

    Must match the fn return type: `"text"` pairs with string / `table.text`; `"bar"` pairs with number / `table.bar`; `"mixed"` pairs with `table {text=, bar=}`; `"free"` does not consume the fn return value (user draws). Unrecognized values trigger a LOG_WARN and fall back to `"text"`.

**`ctx` fields**:

| Field | Type | Description |
|---|---|---|
| `ctx.scenario` | int | 0..3, determined by the system from player state |
| `ctx.box` | `{min=Vec2, max=Vec2}` | screen bounding box |
| `ctx.distance` | number | distance (meters) |
| `ctx.dl` | DrawList | current frame's foreground draw list (required when `kind="free"`) |

---

## `esp.find(id) → ESPElement | nil`
## `esp.remove(id)`
## `esp.elements : map<id, ESPElement>` (iterable via `pairs`)
## `esp.scenario : int` (read-only)
## `esp.INV / esp.VIS / esp.DWN / esp.ALLY = 0 / 1 / 2 / 3`

---

## ESPElement Methods / Fields

### `el:get_color(scenario?) → table<r,g,b,a>` / `el:set_color(value, scenario?)`
Omitting `scenario` = current scenario.

### `el:get_enabled(scenario?) → bool` / `el:set_enabled(value, scenario?)`

### `el.colors = {c0, c1, c2, c3}`
Set all 4 scenario colors at once.

### `el.enableds = {b0, b1, b2, b3}`
Set all 4 scenario enabled flags at once.

### `el.dist : table = {min_m, max_m}`

### `el.label : string`

---

## Example

```lua
-- Text element: return a string
esp.add("tag", function(p, ctx)
    if p.is_teammate then return "ALLY" end
    if p.is_visible  then return "VIS"  end
    return "INV"
end, {
    label  = "Tag",
    kind   = "text",
    colors = {
        { 0.85, 0.85, 0.85, 1.0 },  -- INV
        { 1.00, 0.35, 0.35, 1.0 },  -- VIS
        { 1.00, 0.80, 0.20, 1.0 },  -- DWN
        { 0.35, 0.85, 1.00, 1.0 },  -- ALLY
    },
    dist = { 5.0, 300.0 },
})

-- Bar element: return 0..1
esp.add("hp_bar", function(p, ctx)
    local total = (p.health or 0) + (p.shield or 0)
    return total / 200.0
end, { kind = "bar" })

-- Free drawing: draw via ctx.dl, fn returns nil
esp.add("crosshair", function(p, ctx)
    local cx, cy = (ctx.box.min.x + ctx.box.max.x) * 0.5, ctx.box.min.y - 10
    draw.line(cx - 5, cy, cx + 5, cy, draw.rgba(1, 0, 0, 1))
    return nil
end, { kind = "free" })
```


---


## net

HTTP + WebSocket. **Fully async** — callbacks are dispatched on the menu thread, Lua-safe, and may directly call `gui.set / notify.*`. No synchronous API (e.g. `get_sync`) is provided — it would block the menu thread.

When a script is unloaded, pending HTTP callbacks are silently discarded and WebSocket connections are closed automatically.

---

## net.http

### `net.http:get(url, callback, timeout?)`
**Parameters**: `url : string`, `callback : function(resp)`, `timeout? : int = 10` (seconds)

`resp` fields: `status : int`, `body : string`, `error : string`, `ok : bool`

### `net.http:post(url, body, content_type, callback, timeout?)`
**Parameters**: `url : string`, `body : string`, `content_type : string`, `callback : function(resp)`, `timeout? : int = 10`

---

## net.ws

### `net.ws:connect(url, callbacks) → ws_id : int`
**Parameters**: `url : string`, `callbacks : table`

Optional fields in the `callbacks` table (each is a function):

| Field | Signature |
|---|---|
| `on_open` | `function(id : int)` |
| `on_message` | `function(id : int, msg : string)` |
| `on_error` | `function(id : int, err : string)` |
| `on_close` | `function(id : int, code : int, reason : string)` |

### `net.ws:send(id, msg) → bool`
### `net.ws:close(id)`
### `net.ws:is_open(id) → bool`

---

## Example

```lua
-- HTTP GET (async)
net.http:get("https://example.com", function(resp)
    if resp.ok then
        log.info("OK " .. resp.status .. ", body len=" .. #resp.body)
    else
        log.warn("HTTP fail: " .. (resp.error or ""))
    end
end, 3)

-- HTTP POST JSON
net.http:post("https://api.example.com/log",
    [[{"event":"hello"}]], "application/json",
    function(resp) print(resp.status, resp.ok) end, 5)

-- WebSocket with 4 callbacks
local ws_id = net.ws:connect("wss://echo.example.com", {
    on_open    = function(id) net.ws:send(id, "hi") end,
    on_message = function(id, msg) log.info("recv " .. msg) end,
    on_error   = function(id, err) log.warn("err " .. err) end,
    on_close   = function(id, code, reason) log.info("close " .. code) end,
})
```


---


## game

Live data (**read-only**, writes raise a Lua error). Accessing a field = the latest published snapshot for the current frame.

---

## `game.localplayer`

| Field | Type | Description |
|---|---|---|
| `health` | int | |
| `shield` | int | |
| `max_shield` | int | |
| `origin` | Vec3 | Entity position |
| `camera_origin` | Vec3 | Camera position |
| `view_angle` | Vec2 | `{pitch, yaw}` |
| `sway_angle` | Vec2 | Bullet firing direction including breath/sway |
| `abs_velocity` | Vec3 | |
| `team_num` | int | |
| `squad_id` | int | |
| `weapon_id` | int | |
| `weapon` | string | Weapon name shown in ESP |
| `weapon_speed` | number | Fire rate |
| `weapon_scale` | number | Charge-up progress |
| `target_zoom_fov` | number | ADS fov of the current weapon |
| `weapon_next_ready_time` | number | |
| `weap_state` | int | |
| `burst_fire_index` | int | |
| `ammo_in_clip` | int | |
| `is_semi_auto` | bool | |
| `is_zooming` | bool | |
| `is_dead` | bool | |
| `is_down` | bool | |
| `is_skydive` | bool | |
| `is_grenade` | bool | |
| `is_hands` | bool | |
| `is_on_ground` | bool | |
| `time_base` | number | World time base |
| `spec_index` | int | Spectated target |

---

## `game.entities.players` (iterable via `pairs`)

Per-`PlayerEntity` fields:

| Field | Type |
|---|---|
| `name` | string |
| `weapon` | string |
| `legend` | string |
| `distance` | number |
| `origin` | Vec3 |
| `head_pos` | Vec3 |
| `abs_velocity` | Vec3 |
| `yaw` | number |
| `team_num` | int |
| `squad_id` | int |
| `health` | int |
| `shield` | int |
| `max_shield` | int |
| `is_visible` | bool |
| `is_down` | bool |
| `is_dead` | bool |
| `is_teammate` | bool |
| `is_cloak` | bool |
| `is_npc` | bool |

> `#game.entities.players` **does not work** (userdata-backed tables have no `#`) — count with `for _ in pairs(...) do n = n + 1 end`.

---

## `game.entities.loots` (iterable via `pairs`)

Per-`LootEntity` fields:

| Field | Type |
|---|---|
| `origin` | Vec3 |
| `distance` | number |
| `model_name` | string |
| `model_hash` | uint32 |
| `classified_id` | int (ItemId enum) |
| `classified_name` | string |
| `item_id_str` | string |
| `base_name` | string |
| `quality_level` | int |
| `weapon_name_index` | int |
| `custom_script_int` | int |
| `context_id` | int |

---

## `game.entities.projectiles` (iterable via `pairs`)

Per-`ProjectileEntity` fields:

| Field | Type |
|---|---|
| `kind` | string — `"frag"` / `"thermite"` / `"arc_star"` / `"other"` / `"unknown"` |
| `origin` | Vec3 |
| `team_num` | int |
| `dmg_radius` | number |
| `is_throwable` | bool |
| `is_enemy` | bool |
| `is_local` | bool |

---

## `game.aimbot` (read-only)

| Field | Type | Description |
|---|---|---|
| `target_index` | int | Entity index of the current aimbot target (-1 when no target) |
| `target_distance` | number (meters) | Distance to the current target |
| `predict_pos` | Vec3 \| nil | The aimbot's internal predicted target position |
| `trigger_busy` | bool | Whether the trigger decision is currently busy (for custom trigger HUDs) |

---

## `game.world`

| Field | Type | Description |
|---|---|---|
| `ring` | table | `{origin=Vec3, radius_start=N, radius_end=N, time_start=N, time_end=N, is_active=bool}`; radius / origin are in game units (≈ inches), divide by 39.37 for meters |
| `map_name` | string | Current map string |

---

## Example

```lua
local lp = game.localplayer
if lp.is_dead then return end

for _, p in pairs(game.entities.players) do
    if (not p.is_teammate) and p.is_visible and p.distance < 50 then
        log.info("Enemy " .. (p.name or "?") .. " at " .. p.distance .. "m")
    end
end

if game.world.map_name == "mp_rr_arena_skygarden" then
    -- ...
end
```


---


## draw

Screen drawing. **All `draw.*` calls go to the current frame's foreground draw list and must be called every render frame inside `event.on("frame_update")`**. The draw list is reset every frame; missing a frame = a blank flicker on screen. See Getting Started.

> **Color parameter**: throughout this page `color` is a `number` (32-bit packed color), built with `draw.rgba` / `draw.u8` / `draw.hex`; you cannot pass an `{r,g,b,a}` table directly (the table form is only for ESP element palette `opts`).

---

## Color Construction (returns packed uint32)

### `draw.rgba(r, g, b, a) → uint32` — floats 0..1
### `draw.u8(r, g, b, a) → uint32` — ints 0..255
### `draw.hex(packed : int) → uint32` — pass `0xRRGGBBAA` directly

---

## Shapes

### `draw.line(x1, y1, x2, y2, color, opts?)`
**opts**: `{thickness = 1.0}`

### `draw.rect(x1, y1, x2, y2, color, opts?)`
**opts**: `{filled = false, rounding = 0, thickness = 1, flags = 0}`

### `draw.rect_gradient(x1, y1, x2, y2, c_tl, c_tr, c_br, c_bl)`
A rectangle with one color per corner. Typical use: gradient health bars / gradient backgrounds.

### `draw.circle(x, y, r, color, opts?)`
**opts**: `{filled = false, segments = 0, thickness = 1}`

### `draw.triangle(x1, y1, x2, y2, x3, y3, color, opts?)`
**opts**: `{filled = false, thickness = 1}`. Suited for directional arrows, FOV triangle indicators, down arrows.

### `draw.quad(x1, y1, x2, y2, x3, y3, x4, y4, color, opts?)`
**opts**: `{filled = false, thickness = 1}`. The core of projecting a 3D box: the top/bottom face becomes a 4-vertex quad after projecting the player's 8 world-space vertices to screen.

### `draw.polyline(points, color, opts?)`
**points**: a point sequence, both forms are accepted
- flat: `{x1, y1, x2, y2, ...}` (even length)
- nested: `{ {x1, y1}, {x2, y2}, ... }`

**opts**: `{thickness = 1, closed = false, filled = false}`
- `closed = true` → last point connects back to the start
- `filled = true` → uses `AddConvexPolyFilled` (**reliable for convex polygons only**); on the filled path, both `closed` and `thickness` are ignored

A universal fallback — can draw quads / projected box polygonal outlines / radar shapes / FOV arcs.

---

## Text + Image

### `draw.text(x, y, color, text, opts?)`
**opts**:
- `font` — font handle from `draw.font(name)` (default = system font)
- `size` — force font size float; omitted = `ImGui::GetFontSize()` (the currently-active font's size, not the `font` argument's default)
- `outline` —
  - `true` → theme dark-grey outline (project-uniform style)
  - `uint32 color` → custom outline color
  - omitted / `false` → no outline

Outline implementation = 4-direction 1px offset overlay, smooth and aliasing-free; more correct than scripting manual offset `draw.text` calls.

### `draw.image(tex_handle, x, y, w, h, opts?)`
**Parameters**: `tex_handle` comes from `file.image`'s `:load` / `:svg` / `:create`.

**opts**: `{tint = uint32_white, uv0 = {0,0}, uv1 = {1,1}}`

`uv0` / `uv1` must be array-style `{u, v}` tables — the `{u=..., v=...}` named form is not accepted.

---

## Measurement

### `draw.measure(text, opts?) → w, h`
**opts**: `{font, size}` — omitted = use the currently active font + `ImGui::GetFontSize`

### `draw.screen() → w, h`
Current frame's screen resolution.

---

## Fonts

Fonts are loaded at project startup (ImGui font atlas is built once); **adding fonts at runtime is not supported** — user fonts must be placed in `res/fonts/` so they are auto-scanned at startup.

### `draw.fonts() → table<string>`
Returns the list of available font names. 7 built-ins: "default" / "small" / "icon" / "logo" / "esp" / "loot" / "models", plus any `.ttf`/`.otf` files (without extension) scanned from `res/fonts/`.

### `draw.font(name) → Font | nil`
Get a font handle; `nil` means the name does not exist.

> Note: currently `draw.font(name)` only exposes the 7 built-in fonts ("default" / "small" / "icon" / "logo" / "esp" / "loot" / "models"); `draw.fonts()` will list additional `.ttf`/`.otf` filenames under `res/fonts/`, but actual handle lookup follows the built-in names (extra fonts have no handle yet — reserved for future extension).

---

## Example

```lua
event.on("frame_update", function(e)
    local sw, sh = draw.screen()
    local red    = draw.rgba(1.0, 0.2, 0.2, 1.0)
    local trans  = draw.u8(255, 255, 255, 90)

    -- Crosshair at screen center
    draw.line(sw/2 - 8, sh/2, sw/2 + 8, sh/2, red, { thickness = 2 })
    draw.line(sw/2, sh/2 - 8, sw/2, sh/2 + 8, red, { thickness = 2 })

    -- Top-left watermark (gradient background)
    draw.rect_gradient(10, 10, 200, 40,
        draw.rgba(0.1, 0.1, 0.15, 0.7), draw.rgba(0.2, 0.2, 0.3, 0.7),
        draw.rgba(0.2, 0.2, 0.3, 0.7), draw.rgba(0.1, 0.1, 0.15, 0.7))

    -- Outlined text (follows theme automatically)
    local big = draw.font("logo")
    draw.text(15, 18, draw.rgba(1, 1, 1, 1), "HELLO",
              { font = big, size = 24, outline = true })

    -- Directional arrow (pointing at a player)
    local cx, cy = sw/2, sh - 100
    draw.triangle(cx, cy - 12, cx - 10, cy + 8, cx + 10, cy + 8,
                  draw.rgba(1, 0.8, 0.2, 1), { filled = true })
end)
```


---


## math

Extends the Lua stdlib (**does not override** `sin/cos/pi/floor/random/...`); adds extra functions to the `math` table.

---

## Vector Types

### `math.Vec2(x, y) → Vec2`
### `math.Vec3(x, y, z) → Vec3`

> Note: **CamelCase** `Vec2/Vec3`, not `vec2/vec3` (lowercase `vec2` is a different internal type).

### Vec2 / Vec3 Fields and Operators

Fields: `.x` / `.y` / `.z` (Vec3 only)

Supported meta-operators (work in both directions, operand order doesn't matter):

| Operation | Behavior |
|---|---|
| `a + b` | Per-component addition |
| `a - b` | Per-component subtraction |
| `v * scalar` | Scalar multiplication |
| `v / scalar` | Scalar division |
| `-v` | Negate |
| `tostring(v)` | Text form, e.g. `Vec3(1.000, 2.000, 3.000)` |

Instance methods:

| Method | Returns | Description |
|---|---|---|
| `v:length()` | number | Magnitude |
| `v:length_2d()` (Vec3 only) | number | XY-plane magnitude |
| `v:length_sq()` | number | Squared magnitude (avoids sqrt) |
| `v:dot(other)` | number | Dot product |
| `v:cross(other)` (Vec3 only) | Vec3 | Cross product |
| `v:dist(other)` | number | Distance |
| `v:dist_2d(other)` (Vec3 only) | number | XY-plane distance |
| `v:to_2d()` (Vec3 only) | Vec2 | Projects to Vec2 (x, y) |
| `v:normalize()` | new Vec | In-place normalize, but sol2 returns a **copy of the updated value** (not a self reference). Chains like `v:normalize():length()` do not see the original v |
| `v:normalized()` | new Vec | Copy then normalize; original v unchanged |

---

## Scalar Operations

### `math.Lerp(a, b, t) → number`
Linear interpolation. `t` is not clamped; extrapolation is legal (user's responsibility).

### `math.Clamp(x, lo, hi) → number`

### `math.Smoothstep(edge0, edge1, x) → number`
Hermite interpolation; input `x` within `[edge0, edge1]` smoothly transitions to `[0, 1]`, saturating at both ends.

### `math.AngleNormalize(angle_deg) → number`
Normalizes an arbitrary degree value into `[-180, 180)`.

---

## Angles / Projection

### `math.CalcAngle(from_pos, to_pos) → pitch, yaw`
Two Vec3 → `(pitch, yaw)` in degrees; pitch is negative pointing up.

### `math.WorldToScreen(world_pos) → sx, sy, ok`
Three return values; when `ok=false`, `sx/sy` are meaningless (out-of-game / off-screen / view matrix not ready).

---

## Animation Curves

All `ease_*` take `t : number` (auto-clamped to `[0, 1]`) and return `[0, 1]`.

| Function | Curve | Use case |
|---|---|---|
| `math.ease_in(t)` | `t²` slow start, fast finish | Fade in / starting from rest |
| `math.ease_out(t)` | `1-(1-t)²` fast start, slow finish | Deceleration to stop / popup toast |
| `math.ease_in_out(t)` | cosine, bidirectional | General-purpose smoothing |
| `math.ease_in_cubic(t)` | `t³` more dramatic slow start | High-contrast acceleration |
| `math.ease_out_cubic(t)` | `1-(1-t)³` more dramatic fast-then-slow | High-contrast deceleration |
| `math.ease_bounce(t)` | Bounces at the end | Elastic appearance / notification jitter |

---

## Example

```lua
-- Vector arithmetic
local lp = game.localplayer
local p  = game.entities.players  -- assume targets exist
for _, enemy in pairs(p) do
    if not enemy.is_teammate then
        local delta = enemy.origin - lp.origin
        print("Enemy distance:", delta:length(), "meters")
        local angle_deg = math.CalcAngle(lp.camera_origin, enemy.head_pos)
    end
end

-- Screen projection
event.on("frame_update", function(e)
    for _, p in pairs(game.entities.players) do
        if not p.is_teammate and p.head_pos then
            local sx, sy, ok = math.WorldToScreen(p.head_pos)
            if ok then
                draw.circle(sx, sy, 3, draw.rgba(1, 0, 0, 1), { filled = true })
            end
        end
    end
end)

-- Easing animation: notify pops up 0..100% opacity over 0.5s
local start_t = time.now()
event.on("frame_update", function(e)
    local elapsed = time.now() - start_t
    local progress = math.Clamp(elapsed / 0.5, 0, 1)
    local alpha = math.ease_out_cubic(progress)
    -- Use alpha to draw the toast
end)
```


---


## file

File I/O + image assets.

File paths are relative to the application directory. **Any path string containing the substring `..` is rejected** (sandbox); absolute paths are also rejected. Note: substring match — `my..file.txt` is also rejected.

---

## File

### `file.read(path) → string | nil`
**Parameters**: `path : string`

### `file.write(path, content) → bool`
**Parameters**: `path : string`, `content : string`

Parent directories are created automatically.

### `file.exists(path) → bool`

### `file.remove(path) → bool`

### `file.list(dir) → table<string>`
Lists filenames inside `dir` (non-recursive, **files only, not subdirectories**). Empty / missing `dir` returns an empty table.

---

## Image assets (`file.image`)

`handle` is an opaque texture handle, passed to `draw.image` to display.

When the script unloads, all image handles it created are released automatically.

### `file.image:load(path) → handle | nil`
**Parameters**: `path : string`

Also accepts `(path, w, h)` to force a target size.

### `file.image:svg(svg_str, w, h) → handle | nil`
**Parameters**: `svg_str : string`, `w : int`, `h : int`

### `file.image:create(rgba, w, h) → handle | nil`
**Parameters**: `rgba : table` byte array of length `w*h*4`, `w/h : int`

### `file.image:get(name) → handle | nil`
### `file.image:has(name) → bool`
### `file.image:list() → table<string>`
Lists **all texture names in TextureManager** — including project-internal ESP icons and textures created by other scripts, not just the ones owned by the current script. When pairing with `file.image:remove`, filter by owner first or you'll wipe someone else's textures.

### `file.image:remove(name) → bool`

---

## Example

```lua
-- Config persistence
local cfg_path = "scripts/state/my_script.json"
if file.exists(cfg_path) then
    local raw = file.read(cfg_path)
    -- parse JSON / ...
end
file.write(cfg_path, [[{"flag":true}]])

-- Load a logo
local logo = file.image:load("scripts/assets/logo.png")
event.on("frame_update", function(e)
    if logo then draw.image(logo, 10, 10, 64, 64) end
end)

-- Procedurally generated SVG icon
local icon = file.image:svg(
    [[<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="#ff5050"/></svg>]],
    24, 24)
```


---


## input

Input + keybind formatter.

---

## `input.is_active(path) → bool`
**Parameters**: `path : string` — control full path (hotkey control)

Returns whether this hotkey is currently active (depending on mode: Toggle = toggled on / Hold = currently held / Always = always true).

---

## `input.format(path, fn)`

Attaches dynamic text + color hints to a keybind control. The formatter is only invoked while the hotkey is active (i.e. shown in the "active keybinds" overlay).

**Parameters**:
- `path : string` — **menu element full path** or **Pattern B hotkey ID** (both accepted)
- `fn : function(id : string) → string | { text = string, color = {r,g,b,a} }`

### Automatic path resolution

Pass the menu element full path (the natural form) — if that element is a `KeybindControl` that internally remaps its keybind to a stable ID, resolution follows through to that stable ID.

| Call form | Resolution |
|---|---|
| `input.format("settings.display.menu", fn)` | → resolves to `hotkey.menu_open` |
| `input.format("hotkey.menu_open", fn)` | → used directly |
| `input.format("KbHints.g.alarm", fn)` | → user-defined KeybindControl with no remap, uses full path |

### fn return type

| Return | Behavior |
|---|---|
| `string` | Display the text in the theme color |
| `table {text, color={r,g,b,a}}` | Custom text + color |
| other | LOG_ERR + falls back to default display |

> Owner-scoped: automatically unregistered when the script unloads.

---

## `input.unformat(path)`

Path resolution behaves identically to `input.format`.

---

> **Not provided**: `input.is_down(vk)` — on a dual-machine setup, the OS key API reads the machine running the program, not the game player. To query player input, use `game.localplayer.*` fields (e.g. `is_zooming`, `is_grenade`). See Getting Started.

---

## Example

```lua
-- formatter #1: plain string
input.format("KbHints.g.alarm", function(id)
    return alarm_armed and "ARMED" or "OFF"
end)

-- formatter #2: return {text, color} table
input.format("KbHints.g.stopwatch", function(id)
    local sec = os.clock() - start_t
    return {
        text  = string.format("%.1fs", sec),
        color = { 0.55, 0.85, 1.0, 1.0 },
    }
end)

-- formatter #3: dynamic color by threshold
input.format("KbHints.g.counter", function(id)
    local label = string.format("× %d", counter)
    if counter == 0     then return { text = label, color = { 0.6, 0.6, 0.6, 1.0 } } end
    if counter < 10     then return { text = label, color = { 0.3, 1.0, 0.3, 1.0 } } end
    return { text = label, color = { 1.0, 0.45, 0.25, 1.0 } }
end)
```


---


## log

Developer diagnostic log, viewable in the in-menu console.

Difference from `notify.*`:

| Purpose | Use | Who sees it |
|---|---|---|
| Developer diagnostics / debug info / error tracing | `log.*` | In-menu console |
| User-facing messages (action feedback, error warnings) | `gui.notify:*` | Floating toast, auto-dismisses in ~3-5s |

---

## `log.info(...)` / `log.success(...)` / `log.warn(...)` / `log.error(...)`

**Parameters**: variadic (multiple arguments are joined with tabs automatically)

> `log.error` output only contains the Lua-side origin, not internal binding call frames, keeping the console clean.

---

## Example

```lua
log.info("Script loaded")
log.success("Preset applied: " .. preset_name)
log.warn("HTTP fail: " .. (resp.error or ""))
log.error("Failed to read config file")

-- variadic
log.info("FPS:", fps, "loots:", loot_count)
```


---


## script

Script meta-management.

---

## `script.load(path) → bool`
**Parameters**: `path : string` — path relative to `scripts/`

## `script.unload(path) → bool`

---

## Example

```lua
-- Load another script (typically called from an interactive button)
if not script.load("_test_05_net.lua") then
    gui.notify:error("Load failed", 2.0)
end
```


---


## time

Time.

---

## `time.now() → number`
Real seconds (equivalent to `os.clock`).

## `time.delta() → number`
Last-frame delta time.

## `time.game() → number`
In-game time (pauses when the game pauses).

## `time.frame_count() → number`
Render frame count, monotonically increasing, +1 per rendered frame.

---

| Function | Meaning | Use |
|---|---|---|
| `time.now()` | Wall-clock seconds (equivalent to `os.clock()`) | Timers / throttling / any "real-time seconds" |
| `time.delta()` | Duration of the previous frame (seconds) | Rate integration (movement, animation lerp) |
| `time.game()` | In-game time | Synced with in-game time (pauses when the game pauses) |
| `time.frame_count()` | Cumulative render frame count | Modulo scheduling (`% N == 0`), lightweight periodic tasks |

```lua
-- Run a heavy task once every 60 frames (~1s @ 60fps)
event.on("frame_update", function(e)
    if time.frame_count() % 60 == 0 then
        do_heavy_thing()
    end
end)
```

You can also read `e.delta_time` from the first argument `e` of `event.on("frame_update", fn)`'s `fn(e)` — the value is equivalent to `time.delta()` with one fewer function call.


---


## config

Plan-level file management. **Menu values still go through `gui.set` / `gui.get`** — `config.*` only handles plan switching / listing / saving as a new plan.

---

| Method | Description |
|---|---|
| `config.save()` | Save the current plan |
| `config.save_as(plan_name)` | Save as a new plan name |
| `config.switch(plan_name)` | Switch to the given plan |
| `config.list() → table<string>` | List all available plan names |
| `config.current() → string` | Current plan name |

> No `config.load` — it would duplicate `config.switch`.

---

## Example

```lua
log.info("Current plan: " .. config.current())
log.info("Available plans: " .. table.concat(config.list(), ", "))

-- One-shot switch to cqc.preset
if not config.switch("cqc") then
    gui.notify:error("Switch failed", 2.0)
end
```


---


## json

JSON serialization / deserialization.

Type mapping (bidirectional):

| Lua | JSON |
|---|---|
| `nil` | `null` |
| `bool` | `bool` |
| `number` | `number` (integers take the int path) |
| `string` | `string` |
| Contiguous `1..N` integer-indexed table | `array` |
| Other table | `object` |
| function / userdata | (skipped + LOG_WARN) |

---

## `json.encode(value, pretty?) → string`

**Parameters**:
- `value : any` — value to serialize
- `pretty? : bool = false` — true uses 2-space indentation for readability

Returns `"null"` on serialization failure (rare, only when types are unrecoverable).

---

## `json.decode(text) → value | nil, err_msg`

**Parameters**: `text : string`

**Returns**: on success, a single Lua value; on failure, `(nil, error_string)` — check with `if v == nil then ...`.

> A table received in Lua with contiguous `1..N` integer keys = JSON array; other key shapes = JSON object. **An empty table `{}` is encoded as `"[]"` by default** (treated as an empty array); for an empty object, add any string key to force the non-array path.

---

## Example

```lua
-- encode
local cfg = {
    name = "alice",
    age  = 30,
    tags = { "admin", "user" },
    pos  = { x = 1.5, y = 2.5 },
    on   = true,
}
local text = json.encode(cfg)
file.write("conf/my_state.json", text)

-- decode + error handling
local raw = file.read("conf/my_state.json") or ""
local loaded, err = json.decode(raw)
if not loaded then
    log.warn("Config parse failed: " .. err)
    loaded = { age = 0 }  -- fallback
end
print(loaded.name)
```

Pairs well with `net.http` for remote config pushes:

```lua
net.http:post("https://api.example.com/save",
    json.encode({ event = "session_start" }),
    "application/json",
    function(resp)
        local body, err = json.decode(resp.body or "")
        if body and body.ok then
            gui.notify:success("Reported")
        end
    end, 5)
```


---
