# HApex3.0 Lua API Reference

This is the consolidated reference for all 17 user-facing HApex3.0 Lua modules plus the global runtime surface. The official hapex-lua MCP currently exposes 18 module records including globals. This local snapshot was refreshed from the official MCP endpoint on 2026-08-27.

> [HOOZi 3.0 Lua documentation](https://docs.hoozi.cc/products/apex/dev/) and the official [`hapex-lua` MCP endpoint](https://docs.hoozi.cc/mcp) are authoritative. If this local reference and the live documentation disagree, follow the live documentation.

## Source map

| Domain | Surface | Source |
|----|----|----|
| Overview | [Globals + Overview](#globals--overview) | [中文](https://docs.hoozi.cc/products/apex/dev/api/globals) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/globals) |
| Core | [event](#event) | [中文](https://docs.hoozi.cc/products/apex/dev/api/event) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/event) |
| Core | [gui](#gui) | [中文](https://docs.hoozi.cc/products/apex/dev/api/gui) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/gui) |
| Core | [esp](#esp) | [中文](https://docs.hoozi.cc/products/apex/dev/api/esp) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/esp) |
| Core | [net](#net) | [中文](https://docs.hoozi.cc/products/apex/dev/api/net) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/net) |
| Core | [game](#game) | [中文](https://docs.hoozi.cc/products/apex/dev/api/game) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/game) |
| Core | [draw](#draw) | [中文](https://docs.hoozi.cc/products/apex/dev/api/draw) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/draw) |
| Core | [math](#math) | [中文](https://docs.hoozi.cc/products/apex/dev/api/math) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/math) |
| Core | [file](#file) | [中文](https://docs.hoozi.cc/products/apex/dev/api/file) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/file) |
| Core | [input](#input) | [中文](https://docs.hoozi.cc/products/apex/dev/api/input) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/input) |
| Utility | [log](#log) | [中文](https://docs.hoozi.cc/products/apex/dev/api/log) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/log) |
| Utility | [script](#script) | [中文](https://docs.hoozi.cc/products/apex/dev/api/script) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/script) |
| Utility | [time](#time) | [中文](https://docs.hoozi.cc/products/apex/dev/api/time) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/time) |
| Utility | [config](#config) | [中文](https://docs.hoozi.cc/products/apex/dev/api/config) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/config) |
| Utility | [json](#json) | [中文](https://docs.hoozi.cc/products/apex/dev/api/json) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/json) |
| Utility | [utils](#utils) | [中文](https://docs.hoozi.cc/products/apex/dev/api/utils) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/utils) |
| Utility | [mem](#mem) | [中文](https://docs.hoozi.cc/products/apex/dev/api/mem) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/mem) |
| Utility | [offsets](#offsets) | [中文](https://docs.hoozi.cc/products/apex/dev/api/offsets) · [English](https://docs.hoozi.cc/en/products/apex/dev/api/offsets) |

## How to use this file

- Search for the exact API name or field first.
- Treat fields marked read-only as immutable; use gui.set only for supported configuration paths.
- Pay attention to : versus . call syntax and to per-frame requirements for draw.*.
- Use [guide.md](guide.md) for lifecycle, timing, and repository-specific pitfalls; use [examples.md](examples.md) for complete scripts.

---
## event

Official source: [event](https://docs.hoozi.cc/en/products/apex/dev/api/event)


Event subscriptions. Subscriptions are revoked automatically when the script is unloaded; no need to hand-write `event.off`.

---

### `event.on(name, fn) → handle`

**Parameters**
- `name : string` — event name, one of the table below
- `fn : function` — callback

**Event names + callback signatures**

| Event name | Callback signature | Fields |
|---|---|---|
| `"frame_update"` | `fn(e)` | `e.delta_time : number` — z-order below ESP |
| `"render_post"` | `fn(e)` | `e.delta_time : number` — z-order above ESP / FOV / menu |
| `"config_changed"` | `fn(e)` | `e.module_name : string` — fires on config modify |
| `"script_loaded"` | `fn(e)` | `e.script_path : string`, `e.is_reload : bool` |
| `"script_unloaded"` | `fn(e)` | `e.script_path : string` |
| `"menu_toggled"` | `fn(e)` | `e.visible : bool` — fires on MenuOpen hotkey edges |
| `"weapon_changed"` | `fn(e)` | `e.prev_weapon : int`, `e.curr_weapon : int` — local held-weapon edge (sdk::ItemId) |
| `"map_changed"` | `fn(e)` | `e.prev_map : string`, `e.curr_map : string` — map switch (level_name edge) |
| `"player_knocked"`   | `fn(e)` | Knocked down (is_down false→true). Shares player lifecycle fields (below) |
| `"player_revived"`   | `fn(e)` | Revived (is_down true→false, still alive) |
| `"player_died"`      | `fn(e)` | Killed (is_dead false→true) |
| `"player_respawned"` | `fn(e)` | Respawned (is_dead true→false) |

**All events share these base fields**: `e.timestamp : int` (millis unix ts, lazy-computed), `e.source : string`.

**Player lifecycle events share these fields**: `e.player_index : int`, `e.name : string`, `e.team_num : int`, `e.is_local : bool`, `e.is_teammate : bool`.

Why 4 separate player event names (not a single `state` field):
- Handlers skip the `if state == "knocked"` branching boilerplate.
- Subscribing to only what you care about avoids unrelated dispatches — EventBus matches by `type_index` for zero waste.

The render thread diffs every player against last frame's state and only publishes on edges — no per-frame spam. A player seen for the first time does not produce an event (avoids false reports on initialization). `weapon_changed` / `map_changed` use the same edge semantics.

> **`frame_update` vs `render_post` z-order**: `frame_update` writes vtx that lands *before* ESP / FOV / menu drawings; `render_post` writes vtx that lands *after*. Both use screen-relative coordinates (system handles viewport offset uniformly). For HUD-style mods overlaying ESP, use `render_post`; for underlying information display, use `frame_update`.
>
> **Both fire once per render frame** (bound to the screen render cadence — at 144Hz / 240Hz, 144/240 times per second). `draw.*` must be hooked in `frame_update` or `render_post` and called every frame — the foreground draw list is reset every frame; missing a frame produces a flicker.
>
> Heavy work (data computation, networking, etc.) should be throttled by the script itself by accumulating `e.delta_time`. See [Getting Started](/en/products/apex/dev/guide).

**Returns**: `handle : number` — used for `event.off`.

---

### `event.off(handle)`

Explicitly unsubscribe (usually not needed manually).

---

### Custom Events (cross-script)

Beyond the built-in events above, any **other event name** goes through the Lua custom-event channel.

#### `event.on(name, fn) → handle`
Any `name` not in the built-in event list automatically uses the custom channel. The `fn` signature is `function(...)` — it receives all arguments forwarded from `event.emit(name, ...)`.

#### `event.emit(name, ...)`
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

### Example

```lua
event.on("frame_update", function(e)
    -- Called every render frame; dt is equivalent to time.delta()
    do_something(e.delta_time)
end)

event.on("script_unloaded", function(ue)
    if ue.script_path ~= _SCRIPT_PATH then return end
    -- Only handle our own unload (rare cases: flush buffers)
end)

-- Menu visibility: toast follows menu
event.on("menu_toggled", function(e)
    if e.visible then gui.notify:info("menu opened") end
end)

-- Player lifecycle: teammate knocked alert
event.on("player_knocked", function(e)
    if e.is_teammate then gui.notify:warn(e.name .. " knocked!", 3) end
end)

event.on("player_died", function(e)
    if e.is_local then gui.notify:error("You died", 2) end
end)

-- HUD overlays ESP: use render_post, not frame_update
event.on("render_post", function(e)
    draw.text(draw.font("default"), 24, 100, 100, 0xFFFFFFFF, "On top of ESP")
end)

-- Weapon swap: reset per-weapon state
event.on("weapon_changed", function(e)
    print(string.format("weapon: %d → %d", e.prev_weapon, e.curr_weapon))
end)

-- Map change: reset round-local stats
event.on("map_changed", function(e)
    print("map:", e.prev_map, "→", e.curr_map)
end)
```

---

## gui

Official source: [gui](https://docs.hoozi.cc/en/products/apex/dev/api/gui)


Menu UI + config writes (the **only** write path). After creating a container, keep the returned object reference and mount child elements through its methods.

---

### Top-level Creation + Lookup

#### `gui.tab(name) → Tab`
**Parameter**: `name : string` — used as both id and label.

#### `gui.sub_tab(parent, id, label) → Tab`
**Parameters**: `parent : Tab`, `id : string`, `label : string`

#### `gui.window(id, title, w, h, flags?) → Window`
**Parameters**: `id : string`, `title : string`, `w : number`, `h : number`, `flags? : int = 0`

Combine `flags` from `gui.WINDOW.*` (bitwise OR / plain `+`). Common ones:

| Constant | Effect |
|---|---|
| `NoTitleBar` | No title bar |
| `NoResize` | No corner-resize |
| `NoMove` | Not draggable |
| `NoScrollbar` / `NoScrollWithMouse` | No scrollbar / no wheel scroll |
| `NoCollapse` | Not collapsible |
| `NoBackground` | Transparent (no fill/border) |
| `AlwaysAutoResize` | Size to content |
| `NoSavedSettings` | Don't persist pos/size |
| `NoMouseInputs` / `NoInputs` | Mouse passthrough / no input at all |
| `NoFocusOnAppearing` / `NoBringToFrontOnFocus` | Don't steal focus on show/click |
| `NoDecoration` | = NoTitleBar+NoResize+NoScrollbar+NoCollapse (typical borderless HUD) |

Borderless draggable HUD: `gui.window("hud", "", 250, 112, gui.WINDOW.NoDecoration + gui.WINDOW.NoFocusOnAppearing)`.
Draw custom bars/graphics inside via `Window:custom(id, proto, h)` `on_render(self,x,y,w,h)` (window content-region screen coords, moves with the window). **A display-only custom (no mouse hooks) does not capture input, so a borderless window stays draggable by its body.**

#### `gui.find(path) → GUIElement | nil`
**Parameter**: `path : string` — full path (dot-separated, e.g. `"aimbot.master"`).

**Returns**: a derived-type object (Checkbox / Slider / Combobox / Window / Groupbox / Tab / …). `nil` means the path does not exist.

#### `gui.children(path) → table<GUIElement>`
**Parameter**: `path : string` — container full path (Tab / Groupbox / Window / SettingsPopup).

**Returns**: an array of the container's **direct child controls** (type-transparent — each supports `:get()/:set()/:set_hint()`). Returns an empty table `{}` for non-containers or missing paths. Use it to iterate the controls under a container (e.g. for linked show/hide).

#### `gui.get(path, fallback?) → value | fallback`
**Parameters**: `path : string`, `fallback? : any = nil`

Internally = `gui.find(path):get()` with a nil check.

#### `gui.set(path, value)`
**Parameters**: `path : string`, `value : any`

Internally = `gui.find(path):set(value)`.

#### `gui.show(paths)` / `gui.hide(paths)`
**Parameter**: `paths : table<string>` — list of control full paths.

#### `gui.set_enabled(paths, state)` / `gui.set_visible(paths, state)`
**Parameters**: `paths : table<string>`, `state : bool`

---

### Main Menu State

#### `gui.is_visible() → bool`
Whether the menu is currently open (synchronous query — equivalent to `event.on("menu_toggled", fn)` but without maintaining your own bool).

#### `gui.list_hotkeys() → table<GUIElement>`

Returns every Checkbox + KeybindControl that has an actual key bound (controls with vk = 0 are not included). Order matches the internal insert order, which matches the menu display order.

Returned elements are type-transparent (Checkbox / KeybindControl userdata), so you can call subclass methods directly:
- `:get_full_path() → string` — use with `input.is_active(path)` to query current activation
- `:get_label() → string` — display label
- `:get() → bool` — current checkbox value

Pair with `input.format(path)` to get a "Ctrl+F1"-style display string.

```lua
-- Custom hotkey HUD: list every hotkey-bound control + state + key
for _, elem in ipairs(gui.list_hotkeys()) do
    local path = elem:get_full_path()
    local key  = input.format(path)             -- "Ctrl+F1"
    local on   = input.is_active(path)          -- currently active?
    log.info((on and "[ON]  " or "[off] ") .. elem:get_label() .. "  " .. key)
end
```

Aligned with fatality's `gui.GetHotkeyList()`.

---

#### `gui.get_main_window() → table { x, y, w, h, visible }`
Screen position, size, and visibility of the main menu ImGui window.

| Field | Description |
|---|---|
| `x`, `y` | Top-left screen coordinates (pixels, same coord system as `draw.*`) |
| `w`, `h` | Current displayed size (live during the fade animation) |
| `visible` | Equivalent to `gui.is_visible()` |

When the menu is fully closed, `x/y/w/h` keep their last value and `visible=false`. The menu is draggable; `x/y` follow user drags (including across monitors).

```lua
-- A docked floating window that follows the menu's right edge
local win = gui.window("dock", "Toolbar", 200, 400)
event.on("frame_update", function()
    local m = gui.get_main_window()
    if m.visible then
        win:set_pos(m.x + m.w + 10, m.y)
        win:show()
    else
        win:hide()
    end
end)

-- Draw ESP only when the menu is closed (avoids overlap)
event.on("frame_update", function()
    if gui.is_visible() then return end
    draw.text(...)
end)
```

---

### Scenario-aware paths (auto link icon)

Any menu control whose full_path contains one of `.hidden.` / `.visible.` / `.knocked.` / `.teammate.` segments is auto-detected as an ESP scenario field. A link icon (⛓️ linked / ⛓️‍💥 unlinked) appears to the left of the control; toggling it broadcasts the current value to the other 3 scenario paths. The link state persists in `cfg.visual.esp_linked_fields` and is saved per plan.

**Example**:

```lua
local tab = gui.tab("MyESP")
local scenarios = {"hidden", "visible", "knocked", "teammate"}
for _, sc in ipairs(scenarios) do
    local g = tab:group(sc, sc, 0, 0, 0, 0)
    g:color_edit("tint", "Tint", 1, 0, 0, 1)
    g:slider_float("radius", "Radius", 1, 20, 5)
end
-- 4 paths "MyESP.<sc>.tint" / "MyESP.<sc>.radius" automatically get a link icon
-- Clicking ⛓️‍💥 → ⛓️ broadcasts the current scenario's value to the other 3 paths
```

**Reading scenario values — two patterns**:

```lua
-- (A) Inside ESP draw callback: ctx.scenario is per-player (engine-resolved)
esp.add({
    id = "my_module",
    fn = function(ctx)
        local sc_name = ({[0]="hidden",[1]="visible",[2]="knocked",[3]="teammate"})[ctx.scenario]
        local tint = gui.get("MyESP." .. sc_name .. ".tint")
        return { text = "x", text_color = tint }
    end,
})

-- (B) Outside draw context: hardcode which scenario to read
local visible_tint = gui.get("MyESP.visible.tint")
```

**There is NO global "current scenario"** — the 4 scenarios are per-player state classifications, and N players can be in different scenarios simultaneously. `esp.scenario` is the **menu preview** index, not any player's scenario; use `ctx.scenario` (not `esp.scenario`) in draw callbacks.

**Limitation**: Lua-side link propagation only broadcasts at the moment the user toggles unlinked→linked. Subsequent edits to the source value do NOT automatically sync to the other 3 paths (real-time per-frame propagation is TODO). C++ BIND_SCENARIO_FIELD-bound controls don't have this limitation (every write goes through post_write auto-broadcast).

---

### Weapon Configuration Read/Write

Weapon configuration is accessed through `gui.set` / `gui.get`. Two path shapes both edit the same underlying `WeaponConfig`:

| Path shape | Which weapon | When to use |
|---|---|---|
| **Menu path**: `aimbot.legit.fov.dead` | The weapon currently selected in the menu | Matches UI flow; copy directly from the "show component path" tooltip |
| **Storage path**: `aimbot.weapon.<id>.aim.fov_dead` | The specific `<id>` weapon (ignores UI selection) | Batch-edit multiple weapons, run presets, or write while not alive |

> **Menu tooltip**: with "show component path" on, hovering a per-weapon control shows `Storage: aimbot.weapon.<id>.<field>` + `Menu: aimbot.legit.<...>`; right-click copies the storage path. Batch (multi-select) mode adds `(batch: N weapons)`. Global (non-per-weapon) controls show only the single menu path.

#### Menu paths (recommended for daily use)

```lua
gui.set("aimbot.legit.fov.dead",  0.5)   -- current selected weapon: dead zone
gui.set("aimbot.legit.fov.hip",   12.0)  -- current selected weapon: hip FOV
gui.set("aimbot.legit.smoothadv.kp", 1.8)
```

Whichever weapon is selected in the menu is the one written. default selected → writes to default; r301 selected → writes to r301.

**Two caveats**:
- **Batch mode writes only the first weapon**: with multiple weapons multi-selected in the UI, a Lua menu-path `gui.set` only writes to the first one in `selected_weapon_ids` — unlike dragging the slider in the UI, which truly batches. To batch from Lua, loop over storage paths instead.
- **`@weapon_id` suffix forces a specific weapon**: `aimbot.legit.fov.dead@r301` bypasses the UI selection by binding the groupbox to `r301` for this call. Closer to the UI mental model than looping over storage paths when you want to touch a handful of weapons.

#### Storage paths (specific weapon)

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

#### `gui.get_active_override_path() → string`

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

#### `gui.get_selected_weapon() → string`

Returns the weapon id currently **selected for configuration** in the weapon armory (not the held weapon — for that use `gui.get_active_override_path()`). Use it to address per-weapon Lua values via `aimbot.weapon.<wid>.lua.<id>`. Returns `"default"` when nothing is selected.

```lua
local wid = gui.get_selected_weapon()
gui.set("aimbot.weapon." .. wid .. ".lua.my_gain", 1.5)
```

---

### Notifications (gui.notify)

`gui.notify` is a sub-table; call its methods with `:`:

#### `gui.notify:info(text, dur?)` / `:success` / `:warn` / `:error`
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

### Container Methods (shared by Tab / Window / Groupbox)

#### `:group(id, label, x, y, w, h) → Groupbox`
**Parameters**: `id : string`, `label : string`, `x/y/w/h : number`

#### `:button(id, label, callback?) → Button`
**Parameters**: `id : string`, `label : string`, `callback? : function()`

#### `:checkbox(id, label, default) → Checkbox`
**Parameters**: `id : string`, `label : string`, `default : bool`

#### `:slider(id, label, min_v, max_v, def) → Slider` (integer)
**Parameters**: `id : string`, `label : string`, `min_v / max_v / def : int`

#### `:slider_float(id, label, min_v, max_v, def) → SliderFloat`
**Parameters**: `id : string`, `label : string`, `min_v / max_v / def : number`

#### `:range_slider_float(id, label, min_v, max_v, def_v1, def_v2, min_range?) → RangeSliderFloat`
**Parameters**: 5 numbers + `min_range? : number = 0`

#### `:range_slider_int(id, label, min_v, max_v, def_v1, def_v2, min_range?) → RangeSliderInt`
**Parameters**: 5 ints + `min_range? : int = 0`

#### `:dropdown(id, label, items, def) → Combobox`
**Parameters**: `id : string`, `label : string`, `items : table<string>`, `def : int` (**1-based** default index; the binding layer converts to 0-based internally. `gui.get/set` reads/writes the internal field directly so that side is 0-based int)

(The usertype is still named `Combobox` — historical naming, used in the control-methods section below. Multi-select variant is `:multi_dropdown`.)

#### `:input_text(id, label, def) → InputText`
**Parameters**: `id : string`, `label : string`, `def : string`

#### `:color_edit(id, label, r, g, b, a?) → ColorEdit`
**Parameters**: `id : string`, `label : string`, `r / g / b : number`, `a? : number = 1.0`

#### `:multi_dropdown(id, label, items, defaults?) → MultiDropdown`
**Parameters**: `id : string`, `label : string`, `items : table`, `defaults? : table<bool>`

#### `:keybind_control(id, label, def_key?, def_mode?) → KeybindControl`
**Parameters**: `id : string`, `label : string`, `def_key? : int = 0`, `def_mode? : int = 0`

#### `:live_table(id, headers, provider, height?)` (Window / Groupbox only)
**Parameters**: `id : string`, `headers : table<string>`, `provider : function() → table<row>`, `height? : number = 0`

`row` shape: `{cell1, cell2, ...}` array, or `{cells = {...}, color = {r,g,b,a}}` table.

#### `:tips(id, text, icon?, color?)` (Window / Groupbox / SettingsPopup)
**Parameters**: `id : string`, `text : string`, `icon? : string`, `color? : table<r,g,b,a>`

#### `:settings(id, label, icon?) → SettingsPopup`
**Parameters**: `id : string`, `label : string` (text left of the gear, may be empty), `icon? : string` (gear glyph, default ⚙)

A cogwheel/collapsible container (fatality `gui.Settings` equivalent): shows `label ⚙` on the row; clicking the gear opens a popup whose children render inside. See "Settings Gear Container" below.

---

### Custom Controls (LuaControlProto-style)

#### `container:custom(id, proto, height?) → CustomControl`

**Parameters**:
- `id : string` — control id
- `proto : table` — control prototype holding the `on_*` lifecycle callbacks and `initial_data`
- `height? : number = 24` — control height in pixels

Returns a `CustomControl` userdata. The same `proto` may instantiate multiple controls; `initial_data` is deep-copied so instances do not share state.

All `proto` lifecycle fields are optional:

| Field | Signature | Triggered |
|---|---|---|
| `initial_data` | `table` | Initial instance data, deep-copied into `self.data` |
| `on_render` | `fn(self, x, y, w, h)` | Every frame; the box is `(x, y) → (x+w, y+h)` in screen coordinates |
| `on_first_render` | `fn(self)` | First frame (after persisted data has been loaded) |
| `on_mouse_down` | `fn(self, btn)` | Mouse pressed (0=left, 1=right, 2=middle, 3=x1, 4=x2) while hovered |
| `on_mouse_up` | `fn(self, btn)` | Mouse released (hover not required) |
| `on_mouse_move` | `fn(self, dx, dy)` | Hover; mouse position relative to top-left of the control |
| `on_focus` | `fn(self)` | Edge where the control becomes active (holds mouse) |
| `on_blur` | `fn(self)` | Edge where active is released |
| `on_key` | `fn(self, imgui_key)` | Keyboard pressed while hovered (no-repeat) |
| `on_reset` | `fn(self)` | When `self:reset()` is called explicitly |

#### CustomControl instance methods

| Method | Description |
|---|---|
| `self.data : table` | Instance data, read/write. Whole-replace or `self.data.foo = x` both work |
| `self:lock_input()` | Mark input as locked (ImGui auto-locks when holding mouse; this is a hint) |
| `self:unlock_input()` | Release the lock |
| `self:is_hovered() → bool` | Whether the cursor was over the control last frame |
| `self:is_focused() → bool` | Whether the control held the mouse last frame (active) |
| `self:is_input_locked() → bool` | Query the lock_input flag |
| `self:get_height() → number` / `:set_height(h)` | Control height |
| `self:reset()` | Trigger `on_reset` callback |

#### Persistence

`self.data` is automatically saved into cfg.lua.&lt;full_path&gt; (same machinery as Lua-created checkboxes). Script reload / plan switch restores the last `data`. `on_first_render` fires after `data` is loaded so you can initialize from persisted state.

```lua
-- Counter — left-click +1, right-click -1, count survives reload
local Counter = {
    initial_data = { count = 0 },
    on_render = function(self, x, y, w, h)
        local bg = self:is_hovered() and draw.rgba(0.25, 0.30, 0.40, 1)
                                       or draw.rgba(0.15, 0.18, 0.22, 1)
        draw.rect(x, y, x+w, y+h, bg, { filled = true, rounding = 3 })
        draw.text(x + 8, y + 8, draw.rgba(1, 1, 1, 1),
                  "Count: " .. tostring(self.data.count), { outline = true })
    end,
    on_mouse_down = function(self, btn)
        if btn == 0 then self.data.count = self.data.count + 1
        elseif btn == 1 then self.data.count = self.data.count - 1 end
    end,
}

local grp = gui.tab("misc"):group("g", "demo", 0, 0, 350, 0)
grp:custom("counter1", Counter, 28)
```

Full demo at `out/Debug/scripts/custom_control_demo.lua` (Counter / Pulse / Bar).

---

### Settings Gear Container (SettingsPopup)

`container:settings(id, label, icon?) → SettingsPopup` creates a **cogwheel/collapsible container** (fatality `gui.Settings` equivalent): the row shows `label ⚙`; clicking the gear opens a popup whose children render inside. The gear and popup are drawn entirely by the C++ framework — Lua only creates the container and adds children.

Use it to fold "secondary / advanced settings" behind a gear: the main menu stays one row instead of spreading out many params (and you avoid per-frame `set_visible` juggling).

**Child factories** (same set as Groupbox; children get persistence / hotkeys / per-weapon writes automatically):
`button` / `checkbox` / `slider` / `slider_float` / `dropdown` / `input_text` / `color_edit` / `range_slider_float` / `range_slider_int` / `multi_dropdown` / `keybind_control` / `tips` / `custom`

**Instance methods**:

| Method | Description |
|---|---|
| `s:add_child(elem)` / `s:remove_child(elem)` / `s:clear_children()` / `s:remove_children_by_owner(path)` | child add/remove (same as other containers, except `remove_child` / `clear_children` return self for chaining) |
| `s:set_gear_icon(icon) → self` | change the gear glyph |
| `s:set_popup_width(px) → self` | popup logical width (default 260) |

```lua
local grp = gui.tab("misc"):group("g", "demo", 0, 0, 350, 0)
local adv = grp:settings("adv", "Advanced")          -- row shows "Advanced ⚙"
adv:slider("speed", "Speed", 0, 100, 50)
adv:slider_float("ratio", "Ratio", 0.0, 1.0, 0.5):set_format("%.2f")
adv:checkbox("smooth", "Smooth", true)
adv:set_popup_width(220)
```

---

### Container Generic Methods

Shared between `Tab` / `Groupbox` / `Window` for low-level child management. Most scripts don't need these — control creation via `:checkbox` / `:slider` / `:group` is more concise. Use them for dynamic add/remove (hot-reload self-maintenance, conditional control creation at runtime).

#### `:add_child(elem)`
Manually attach a GUI element. No return value.

#### `:remove_child(elem)`
Remove one direct child. Takes the element object (not an id string). No return value.

#### `:remove_children_by_owner(script_path)`
Remove every child created by that owner. No return value. Script unload runs this automatically — manual calls are usually unnecessary.

#### `:clear_children()`
Remove every child.

#### `Tab:is_lua_tab() → bool`
Whether the tab was created by a Lua script via `gui.tab(...)` (as opposed to a built-in C++ tab). Use it when you want to avoid touching built-in tabs.

---

### Window-only Methods

#### `Window:is_open() → bool` / `Window:set_open(bool)`

#### `Window:bind_visible(checkbox) → Window`
**Parameter**: `checkbox : Checkbox` — reference to any Checkbox object (returned by `:checkbox(...)`).

Each frame auto-syncs `Window.open = checkbox.value`, saving you from writing `set_open` inside a `live_table` provider.

---

### Checkbox / Slider / Combobox Control Methods

#### Checkbox / Slider / SliderFloat Multi-hotkey

2026-05-25 UX redesign: **Each Checkbox / Slider supports multiple hotkeys**. Right-click the control to open a popup for managing them. The switch / slider's top-right corner shows the first hotkey plus a count (`Ctrl+F1 +2`). Each row in the popup has `[key][mode][🗑]`; Slider rows have an extra `[⚙]` to set the trigger value (dial slider back to that value).

```lua
-- Checkbox multi-hotkey: any active → checkbox = true
local cb = group:checkbox("aim", "Aimbot", false)
cb:add_hotkey({ vk = 0x70, mode = 1 })                          -- F1 Hold
cb:add_hotkey({ vk = 0x71, mode = 0, modifier = 0x11 })          -- Ctrl+F2 Toggle
cb:clear_hotkeys()                                                -- clear

-- Slider multi-hotkey + per-key value: F3 writes slider to 50
local sl = group:slider("fov", "FOV", 0, 100, 30)
sl:add_hotkey({ vk = 0x72, mode = 0, value = 50 })               -- F3 Toggle → write 50
sl:add_hotkey({ vk = 0x73, mode = 0, value = 80 })               -- F4 Toggle → write 80
```

Modes: `0`=Toggle / `1`=Hold / `2`=Always. Modifiers: `0x10`=Shift / `0x11`=Ctrl / `0x12`=Alt.

#### `Checkbox:set_keybind(vk, mode, modifier?)`
**Parameters**:
- `vk : int` — Main key virtual-key code
- `mode : int` — 0=Toggle / 1=Hold / 2=Always
- `modifier : int?` — Optional modifier key. `VK_CONTROL` (0x11) / `VK_SHIFT` (0x10) / `VK_MENU` (0x12, Alt). Omit or 0 for no modifier.

**Example**:
```lua
cb:set_keybind(0x70, 0)             -- F1 alone, Toggle
cb:set_keybind(0x70, 1, 0x11)       -- Ctrl + F1, Hold
```

#### `Checkbox:set_colors(table)` / `Checkbox:get_colors() → table`
Custom palette for checkboxes that carry keybind state (current/inactive/hover/...).

#### `:set_hint(text) → self`
Puts a `[ ? ]` marker next to the label; hovering it shows the text (line-leading rich-text markers supported: `#` heading / `>` lead / `*` bullet / `!` warning).

Available on: Checkbox / Slider / SliderFloat / RangeSliderFloat / RangeSliderInt / InputText / KeybindControl. Combobox / MultiDropdown / ColorEdit / Button **do not** have `:set_hint`.

::: warning Behavior change, 2026-07-29
On InputText, `:set_hint` used to set the **in-box placeholder** — the opposite of every other control. It is now the `[ ? ]` hint described above; placeholder text moved to `:set_placeholder` below. Old scripts calling `input_text(...):set_hint("...")` still run, but the text moves from inside the box into the `[ ? ]` tooltip — switch those calls to `:set_placeholder` to keep the old look.
:::

#### `InputText:set_placeholder(text) → self`
Grey placeholder text **inside** the box, shown only while the value is empty. InputText only.

```lua
grp:input_text("api_key", "Rank API Key")
   :set_placeholder("leave blank")                  -- grey text inside the box
   :set_hint("# Rank API Key\n> Blank = official service")  -- [ ? ] next to the label
```

#### `:set_width(px) → self` / `:get_width() → number`
**Parameter**: `px : number` — control pixel width; `0` or omitted = auto-fill the row.

A GUIElement base method available on all controls; **only Slider / SliderFloat / Combobox honor it** (others store but ignore). `grp:slider("id","label",0,100,5):set_width(120)`.

#### `:set_per_weapon(enable?) → self` / `:is_per_weapon() → bool`
**Parameter**: `enable? : bool = true`

Store the control's value per weapon (the one currently selected in the weapon armory; Lua controls only). Switching the selected weapon shows that weapon's value; a weapon never set falls back to the `default` weapon's value. Put it last in the chain (returns the base element).

The value is stored at `aimbot.weapon.<wid>.lua.<control id>`; scripts can `gui.get/set` that path to address any specific weapon. Switching weapons shows the selected weapon's value; a weapon never set falls back to the `default` weapon's value.

Value-type controls only (checkbox / slider / slider_float / combobox / input_text); controls with a keybind or colors are not supported per-weapon. Control ids must be unique within the addressing namespace.

```lua
local grp = gui.find("aimbot.legit.smoothadv")
grp:slider_float("lua_gain", "Lua gain", 0, 5, 1):set_format("%.2f"):set_per_weapon(true)
```

#### `Slider:set_format(fmt) → Slider` / `SliderFloat:set_format` / `RangeSliderFloat:set_format` / `RangeSliderInt:set_format`

#### `Combobox:on_change(fn) → Combobox`
**Parameter**: `fn : function(idx_1based : int, name : string)` — 1-based index + selected item string.

#### `Combobox:add_item(item) → Combobox` / `add_items(items)` / `remove_item(idx_or_name)` / `clear_items()`

#### `Combobox:get_selected_name() → string` / `get_items() → table<string>`

#### `InputText:set_size(vec2)`

#### `Button:set_size(vec2)` / `set_icon(string)`

#### `ColorEdit:set_colors(table)` / `set_alpha(bool)`

#### `MultiDropdown:add_item(item, default?)` / `add_items(items)` / `remove_item(idx_or_name)` / `clear_items()` / `get_selected_names() → table<string>`

---

### GUIElement Base Methods (inherited by all controls)

#### `:get_id() → string` / `:get_owner() → string` / `:get_label() → string` / `:set_label(str)`

#### `:is_enabled() → bool` / `:set_enabled(bool)` / `:is_visible() → bool` / `:set_visible(bool)`

#### `:get() → value` / `:set(value)` / `:has_value() → bool`
Path-based unified accessor for the control's current value (equivalent to `gui.get` / `gui.set`).

#### `:bind_weapon(...)` / `:get_target_weapon(...)`
Control-level weapon binding (advanced).

---

### Example

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

Official source: [esp](https://docs.hoozi.cc/en/products/apex/dev/api/esp)


ESP element registration. Each ESP element has 4 independent palettes (one per scenario: INV / VIS / DWN / ALLY); the system picks one automatically per player state. Scripts read `esp.scenario` for the current preview scenario, use `el:set_color(value, scenario)` to change a single scenario, or `el.colors = {c0,c1,c2,c3}` to batch-set all four in one line.

---

### `esp.add(id, fn, opts?) → ESPElement`

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

### `esp.find(id) → ESPElement | nil`
### `esp.remove(id)`
### `esp.elements : map<id, ESPElement>` (iterable via `pairs`)
### `esp.scenario : int` (read-only)
### `esp.INV / esp.VIS / esp.DWN / esp.ALLY = 0 / 1 / 2 / 3`

---

### ESPElement Methods / Fields

#### `el:get_color(scenario?) → table<r,g,b,a>` / `el:set_color(value, scenario?)`
Omitting `scenario` = current scenario.

#### `el:get_enabled(scenario?) → bool` / `el:set_enabled(value, scenario?)`

#### `el.colors = {c0, c1, c2, c3}`
Set all 4 scenario colors at once.

#### `el.enableds = {b0, b1, b2, b3}`
Set all 4 scenario enabled flags at once.

#### `el.dist : table = {min_m, max_m}`

#### `el.label : string`

---

### Example

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

Official source: [net](https://docs.hoozi.cc/en/products/apex/dev/api/net)


HTTP + WebSocket. **Fully async** — callbacks are dispatched on the menu thread, Lua-safe, and may directly call `gui.set / notify.*`. No synchronous API (e.g. `get_sync`) is provided — it would block the menu thread.

### Lifecycle

| Resource | Behavior on script unload |
|---|---|
| HTTP pending callbacks (`net.http:*`) | Queued responses are silently discarded; your callback is not invoked. |
| WebSocket client (`net.ws:connect`) | All connections opened by the script are closed. |
| WebSocket server (`net.ws_server:listen`) | All servers opened by the script are closed; every client is forcibly disconnected. |

When a WS client fails to reach its server (port closed, timeout, bad URL), background resources are cleaned up automatically. Reconnecting in a loop will not leak memory or threads — `net.ws:connect` is fire-and-forget; you do not need to `:close` on failure.

---

### net.http

`resp` fields passed to the callback: `status : int`, `body : string`, `error : string`, `ok : bool`

#### `net.http:get(url, callback, timeout?)`
**Parameters**: `url : string`, `callback : function(resp)`, `timeout? : int = 10` (seconds)

#### `net.http:get(url, options, callback)` — headers / file download
**Parameters**: `url : string`, `options : table`, `callback : function(resp)`

#### `net.http:post(url, body, content_type, callback, timeout?)`
**Parameters**: `url : string`, `body : string`, `content_type : string`, `callback : function(resp)`, `timeout? : int = 10`

#### `net.http:post(url, options, callback)` — headers / custom body
**Parameters**: `url : string`, `options : table`, `callback : function(resp)`

#### `net.http:request(url, method, options, callback)` — any method
**Parameters**: `url : string`, `method : string` (GET / POST / PUT / DELETE / PATCH / ...), `options : table`, `callback : function(resp)`

`options` table (all fields optional):

| Field | Type | Description |
|---|---|---|
| `headers` | `table<string,string>` | Custom request headers |
| `body` | `string` | Request body (may be empty for GET) |
| `content_type` | `string` | Synthesises a `Content-Type` header |
| `save_to_file` | `string` | Non-empty = stream to file instead of `resp.body` (large download) |
| `timeout` | `int` | Seconds, default 10 |

---

### net.ws

#### `net.ws:connect(url, callbacks) → ws_id : int`
**Parameters**: `url : string`, `callbacks : table`

Optional fields in the `callbacks` table (each is a function):

| Field | Signature |
|---|---|
| `on_open` | `function(id : int)` |
| `on_message` | `function(id : int, msg : string)` |
| `on_error` | `function(id : int, err : string)` |
| `on_close` | `function(id : int, code : int, reason : string)` |

#### `net.ws:send(id, msg) → bool`
#### `net.ws:close(id)`
#### `net.ws:is_open(id) → bool`

---

### net.ws_server

WebSocket **server**. Listens only on `127.0.0.1` (local web dashboard / IPC; not exposed externally).
On script unload, every server opened by that script is closed and every client is forcibly disconnected.

#### `net.ws_server:listen(port, callbacks) → WsServer | nil`

**Parameters**:
- `port : int` — local port (returns nil if busy)
- `callbacks : table` — callback table

| Field | Signature | Description |
|---|---|---|
| `on_open` | `fn(client : int)` | New client finished handshake |
| `on_message` | `fn(client : int, msg : string)` | Received text / binary message |
| `on_error` | `fn(client : int, err : string)` | Error |
| `on_close` | `fn(client : int, code : int, reason : string)` | Client disconnected (remote or local) |

Returns a `WsServer` userdata (nil on failure).

#### WsServer methods

| Method | Description |
|---|---|
| `srv:send(client, msg) → bool` | Send a text message to a specific client |
| `srv:broadcast(msg)` | Broadcast to every client on this server |
| `srv:disconnect(client, code?, reason?)` | Disconnect a client; code defaults to 1000, reason defaults to empty |
| `srv:close()` | Close server + all clients; joins internal threads. Idempotent. |
| `srv:is_open() → bool` | Whether the server is still running |
| `srv:client_count() → int` | Number of currently connected clients |
| `srv.id` | Numeric server id (read-only) |

#### Constraints

- 64MB max per message (protects against giant payloads)
- Only sends `text` (opcode 0x1); accepts both `text` and `binary` on receive
- No `wss://` (TLS) — local-only use case
- No fragmented-frame subprotocol
- Auto replies `ping → pong` without invoking user callbacks

```lua
-- Local dashboard on port 8080 (browser connects ws://127.0.0.1:8080/)
local srv = net.ws_server:listen(8080, {
    on_open    = function(c) print("client", c, "joined") end,
    on_message = function(c, msg) print("got from", c, ":", msg) end,
    on_close   = function(c, code, reason) print("client", c, "left", code) end,
})

if not srv then return end

-- Broadcast game state every frame
event.on("frame_update", function(e)
    local lp = game.localplayer
    if lp then
        srv:broadcast(json.encode({hp=lp.health, sh=lp.shield, vel=lp.abs_velocity}))
    end
end)

event.on("script_unloaded", function(ue)
    if ue.script_path == _SCRIPT_PATH then srv:close() end
end)
```

---

### Example

```lua
-- HTTP GET (async)
net.http:get("https://example.com", function(resp)
    if resp.ok then
        log.info("OK " .. resp.status .. ", body len=" .. #resp.body)
    else
        log.warn("HTTP fail: " .. (resp.error or ""))
    end
end, 3)

-- HTTP POST JSON (legacy signature)
net.http:post("https://api.example.com/log",
    [[{"event":"hello"}]], "application/json",
    function(resp) print(resp.status, resp.ok) end, 5)

-- GET with Authorization (options style)
net.http:get("https://api.example.com/me", {
    headers = { ["Authorization"] = "Bearer " .. token, ["X-Trace-Id"] = "abc" },
    timeout = 5,
}, function(resp) log.info(resp.body) end)

-- POST JSON with custom header
net.http:post("https://api.example.com/log", {
    headers = { ["Authorization"] = "Bearer " .. token },
    body = json.encode({ event = "hello" }),
    content_type = "application/json",
}, function(resp) print(resp.status) end)

-- Streaming download (no memory cost)
net.http:get("https://example.com/big.zip", {
    save_to_file = "downloads/big.zip",
    timeout = 60,
}, function(resp) log.info("downloaded, status=" .. resp.status) end)

-- PUT / DELETE
net.http:request("https://api.example.com/item/42", "DELETE", {
    headers = { ["Authorization"] = "Bearer " .. token },
}, function(resp) print(resp.ok) end)

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

Official source: [game](https://docs.hoozi.cc/en/products/apex/dev/api/game)


Live data (**read-only**, writes raise a Lua error). Accessing a field = the latest published snapshot for the current frame.

### Update strategy

The field tables carry an **Update strategy** column — not every field is read from the game each frame. The backend re-paces reads by state, and a skipped frame reuses the previous value. Understanding this column saves the "why does an off-screen enemy's HP update so slowly" / "why are bones zero off-screen" confusion.

- **Enemy players / loot / projectiles down-throttle off-screen**: off-screen, farther away, and non-alive all read slower. Any field marked "on-screen only" does not refresh while off-screen — you read the last value seen while it was on-screen.
- **One exception**: the aimbot's currently locked target is exempt from all throttling and is read every frame (so aiming never depends on ESP toggles).
- **The local player is never throttled** — you're always relevant, so its default is "every frame".
- "Computed each update" = the value is not read from memory directly; it's derived locally each cycle from the freshest other fields, so its freshness follows whatever it depends on.
- "Every frame / every N frames" refers to backend read cycles, not a fixed 60 Hz.

---

### `game.localplayer`

The local player has no on-screen / distance throttling; default is "every frame".

| Field | Type | Update strategy | Description |
|---|---|---|---|
| `index` | int | Every frame | entity_list index |
| `base` / `self_base` | uint64 | Every frame | Entity memory base — combine with [offsets](/en/products/apex/dev/api/offsets) + `mem.read/write` to self-service read/write any attribute. **The two diverge while dead-spectating**: `base` follows the spectated player, `self_base` is always the real local machine — use `self_base` to read "my own" attributes |
| `health` | int | Every frame | Current HP |
| `max_health` | int | Low frequency | Max HP (only changes on armor pickup / gold-knockdown revive) |
| `shield` | int | Every frame | Current shield |
| `max_shield` | int | Low frequency | Max shield (changes on armor swap) |
| `origin` / `camera_origin` | Vec3 | Every frame | Entity / camera position (origin follows the spectated player while dead) |
| `view_angle` | Vec2 | Every frame | `{pitch, yaw}` |
| `sway_angle` | Vec2 | Every frame | Bullet firing direction including breath/sway |
| `view_offset` / `punch_angle` | Vec3 | Every frame, alive & not knocked | View offset / recoil; keeps last value when dead/knocked |
| `abs_velocity` | Vec3 | Every frame | |
| `flags_raw` | uint32 | Every frame | Raw `m_fFlags` bits (FL_ONGROUND etc.) |
| `team_num` / `squad_id` | int | Read once on create | |
| `platform_uid` | string | Read once on create | uint64 → string |
| `weapon_id` | int | Every frame, alive & armed | Weapon string-table index; blank when empty-handed |
| `weapon_enum` | int | Resolved on weapon swap | `sdk::ItemId` value, more reliable than the `weapon` string |
| `weapon` | string | Resolved on weapon swap | Weapon name shown in ESP |
| `weapon_speed` / `weapon_scale` | number | Every frame, alive & armed | Fire rate / charge-up |
| `target_zoom_fov` | number | Every frame, alive & armed | ADS fov of the current weapon |
| `weapon_next_ready_time` | number | Every frame, alive & armed | |
| `weap_state` / `burst_fire_index` / `ammo_in_clip` | int | Every frame, alive & armed | Internal ammo state |
| `is_semi_auto` | bool | Every frame, alive & armed | |
| `is_zooming` | bool | Every frame, alive & not knocked | |
| `is_dead` / `is_down` / `is_on_ground` | bool | Every frame | |
| `is_grenade` / `is_hands` | bool | Resolved on weapon swap | |
| `is_skydive` | bool | Low frequency (~every 6 frames) | |
| `time_base` | number | Every frame | World time base |
| `spec_index` | int | Every frame | Spectated target (only set while dead-spectating; -1 when alive) |
| `backpack_tier` | int | Low frequency (~1 Hz) | 0=None / 1=White / 2=Blue / 3=Purple / 4=Gold |
| `consumables` | table | Low frequency (~every 15 frames) | 16-slot consumable inventory (each slot `{item: uint16, count: uint16}`; count==0 = empty) |

---

### `game.entities.players` (iterable via `pairs`)

Per-`PlayerEntity` fields. The update strategy here stacks two layers: the entity itself is read **every frame on-screen, throttled off-screen**, and a field may add its own gate (bones need on-screen, identity is read once on create). The effective refresh rate is the slower of the two.

| Field | Type | Update strategy | Description |
|---|---|---|---|
| `index` / `base` / `is_npc` | int/uint64/bool | Fixed on create | Not read from memory |
| `name` / `platform_uid` / `xp` | string/string/int | Read once on create | platform_uid retries a few times in-match if the first read fails |
| `team_num` / `squad_id` / `rank_source` | int | Read once on create | |
| `grade` / `rank` / `rank_icon_key` / `rank_color` | int/string | Locked for the match | Computed from score on the first frame, fixed after one cloud-rank resolve |
| `legend` / `legend_icon_key` | string | Resolved on legend change | Model name sampled ~every 64 frames; resolves ~once per match |
| `kills` / `damage` | int | Low frequency (~every 64 frames) | Read on- and off-screen, diluted by entity throttling |
| `weapon_id` | int | Short lag on weapon swap | Weapon pointer refreshes ~every 12 frames on-screen; the underlying handle is sampled very infrequently |
| `weapon` | string | Resolved on weapon swap | |
| `origin` | Vec3 | Every frame on-screen, throttled off-screen | Not read after death |
| `abs_velocity` | Vec3 | On-screen & in valid range only | Falls back to position-delta estimation off-screen |
| `head_pos` | Vec3 | On-screen only | Derived from the head bone each update (needs bones resolved) |
| `yaw` | number | <300m ~every 6 frames, slower beyond | Read on- and off-screen |
| `health` / `shield` / `max_shield` | int | On-screen only (~every 12 frames) | |
| `flags` | int | On-screen only (~every 3 frames) | m_fFlags state bits |
| `is_down` / `cloak_endtime` | bool/number | On-screen only (~every 3 frames) | |
| `is_dead` | bool | Low frequency (~every 8 frames) | |
| `spec_index` | int | Dead players only (~every 8 frames) | Whom this player is spectating; -1 for the living |
| `last_visible_time` | number | On-screen & in valid range only | Visibility timestamp |
| `vec_min` / `vec_max` | Vec3 | On-screen (~every 3 frames), needs dynamic-box/map-ident | Collision AABB; not read if neither is enabled |
| `is_glow` / `is_wall` | bool | On-screen (~every 12 frames), needs glow enabled | |
| `roster` | uint8 | Roster lookup each update | Roster bitmask (pro/star/cheater/friends); not re-queried unless the roster changes |
| `distance` | number | Computed each update | Meters |
| `is_visible` / `is_teammate` / `is_cloak` | bool | Computed each update | Not read from memory |
| `in_screen` / `can_draw` / `is_model_blocked` | bool | Computed each update | Rendering-related state; static occlusion like Gibraltar's bubble |
| `has_bones` / `has_fresh_bones()` | bool | On-screen only; true only when all 17 bones were read this frame | false off-screen; calling it triggers a full-bone read (see below) |

> `#game.entities.players` **does not work** (userdata-backed tables have no `#`) — count with `for _ in pairs(...) do n = n + 1 end`.

#### Skeleton

`PlayerEntity` exposes 17 bone world positions; pair with `game.BONE` (part constants) and `game.BONE_LINKS` (connection table) to draw skeleton ESP.

| Member / constant | Description |
|---|---|
| `player:bone(idx)` | World-space `Vec3` of body part `idx` (0-based body part id); returns a zero vector if out of range or bones not ready |
| `player:has_fresh_bones()` | Whether all 17 bones were actually read this frame (when false, `bone()` is likely zero — skip) |
| `game.BONE` | Named part constants: `head`=0, `upper_chest`, `chest`, `waist`, `hip`, `l_shoulder`, `l_elbow`, `l_hand`, `r_shoulder`, `r_elbow`, `r_hand`, `l_thigh`, `l_knee`, `l_foot`, `r_thigh`, `r_knee`, `r_foot`=16 |
| `game.BONE_LINKS` | Array of `{a, b}` part-id pairs (matches the native skeleton, 16 segments) |

> **Update strategy**: bones are read **on-screen only** (`bone()` returns zero off-screen). By default the backend reads only the head bone; all 17 are read when one of these holds: skeleton ESP is on, the player is the aimbot's locked target, or it's used as a chams far-enemy anchor. **Calling `bone()` or `has_fresh_bones()` makes the backend read all 17 bones for on-screen players for the next ~0.5s** — so drawing your own skeleton does not need the menu's skeleton-ESP toggle; just call it.

> `math.WorldToScreen(world)` returns **3 values** `(sx, sy, ok)`, not a Vec2.

```lua
-- Skeleton ESP: iterate links, project each bone to screen, draw a line
local LINKS = game.BONE_LINKS
event.on("frame_update", function()
    for _, p in pairs(game.entities.players) do
        if p.is_visible and not p.is_dead and not p.is_teammate and p:has_fresh_bones() then
            for _, link in ipairs(LINKS) do
                local ax, ay, ok1 = math.WorldToScreen(p:bone(link[1]))
                local bx, by, ok2 = math.WorldToScreen(p:bone(link[2]))
                if ok1 and ok2 then
                    draw.line(ax, ay, bx, by, draw.u8(255, 255, 255, 200), 1.5)
                end
            end
        end
    end
end)
```

---

### `game.entities.loots` (iterable via `pairs`)

Per-`LootEntity` fields. Loot properties are essentially fixed at create; only `origin` keeps re-pacing by state. A newly dropped item is discovered after ~0.25s (discovery lag, unrelated to field refresh).

| Field | Type | Update strategy | Description |
|---|---|---|---|
| `index` / `base` | int/uint64 | Fixed on create | Entity memory base — combine with [offsets](/en/products/apex/dev/api/offsets) + `mem.read/write` for self-service reads |
| `model_name` | string | Read once on create | |
| `model_hash` | uint32 | Read once on create | hash of model_name |
| `quality_level` | int | Read once on create | 0=unknown, 1..5=COMMON..HEIRLOOM |
| `weapon_name_index` | int | Read once on create | Weapon string-table index |
| `custom_script_int` / `context_id` | int | Read once on create | |
| `classified_id` | int | Computed each update | ItemId enum value |
| `classified_name` / `item_id_str` / `base_name` | string | Computed each update | Classified names |
| `origin` | Vec3 | Low-frequency polling | High when just moved; static on-screen ~4 Hz; static off-screen ~1 Hz; beyond loot display range ~every 4s. Never fully stops |
| `distance` | number | Computed each update | Meters |

---

### `game.entities.projectiles` (iterable via `pairs`)

Per-`ProjectileEntity` fields. The core job is high-frequency trajectory drawing: `origin` is read every frame for nearby local/enemy projectiles. Lifetime-constant fields (owner/team/radius/weapon class) are read once when the projectile appears.

| Field | Type | Update strategy | Description |
|---|---|---|---|
| `index` / `base` | int/uint64 | Fixed on create | Entity memory base — combine with [offsets](/en/products/apex/dev/api/offsets) + `mem.read/write` for self-service reads |
| `owner_handle_raw` | uint32 | Read once on first appearance | Raw EHandle bits of m_hOwnerEntity |
| `team_num` | int | Read once on first appearance | |
| `dmg_radius` | number | Read once on first appearance | m_DmgRadius |
| `weapon_class_index` | uint16 | Read once on first appearance | m_weaponClassIndex; pair with `game.world` to look up weapon name |
| `creation_time` | number | Stamped once on first appearance | Entity birth timestamp |
| `kind` | string | Typed once when weapon name resolves | `"frag"` / `"thermite"` / `"arc_star"` / `"other"` / `"unknown"` |
| `origin` | Vec3 | Every frame (nearby local/enemy) | ~1 Hz beyond trajectory display range; not read for teammate or static map props once confirmed |
| `is_throwable` | bool | Computed each update | Real player grenade (filters static map props) |
| `is_enemy` / `is_local` | bool | Computed each update | |

---

### `game.aimbot` (read-only)

| Field | Type | Description |
|---|---|---|
| `target_index` | int | Entity index of the current aimbot target (-1 when no target) |
| `target_distance` | number (meters) | Distance to the current target |
| `predict_pos` | Vec3 \| nil | The aimbot's internal predicted target position |
| `trigger_busy` | bool | Whether the trigger decision is currently in a busy state (for custom trigger HUDs) |
| `trigger` | table | Detailed trigger state snapshot (see below, for trigger HUDs) |

> `weapon_next_ready_time` is on `game.localplayer`; trigger state is not its own namespace to avoid duplicate paths.

#### `game.aimbot.trigger`

All timestamps are **engine-clock seconds (QPC, `base::get_time`)**, **not** `time.game()`/`time.now()`. The table includes a same-clock `now`; use it for countdowns (e.g. `ready_in = t.weapon_ready_at - t.now`).

| Field | Type | Description |
|---|---|---|
| `now` | number | Current engine clock (QPC seconds), same clock as the timestamps below; use it for countdowns |
| `busy` | bool | In a hold/release-window countdown |
| `target_index` | int | Target being evaluated (`0` = none) |
| `pressed` | bool | Already mouse_down |
| `last_hit` | bool | Whether the last evaluation hit |
| `snapshot_time` | number | Game time of this snapshot |
| `release_at` / `again_at` | number | Planned mouse_up / next-allowed-fire time |
| `visible_at` | number | Target visible start (react timing origin) |
| `weapon_ready_at` | number | Weapon ready time |
| `react_window_ms` / `again_window_ms` / `release_window_ms` | int | React / re-fire / hold-duration windows, in **milliseconds** (same unit as the menu) |
| `radscale` | number | Hit-radius multiplier |
| `aim_offset` | Vec3 | Offset of the aim part relative to spine_head |

```lua
event.on("frame_update", function()
    local t = game.aimbot.trigger
    if t.target_index ~= 0 then
        local ready_in = math.max(0, t.weapon_ready_at - t.now)
        draw.text(20, 200, draw.u8(255,255,255,255),
                  string.format("trigger: tgt=%d hit=%s ready_in=%.2f",
                                t.target_index, tostring(t.last_hit), ready_in))
    end
end)
```

#### Custom aim algorithms (movement/smoothing + prediction override)

Scripts can register their own **movement algorithm** (added to the dropdown) and **prediction algorithm** (global override). Execution model: callbacks run on the **render thread** (same thread as the Lua VM — **no lock**). Smoothing cadence = min(aim publish rate, render FPS) (uncapped render → high rate); prediction is slow-changing, so the render thread computes the aim point and the aim thread consumes it at **500Hz** with no cadence loss. The native Normal/PID paths are unaffected.

##### `game.aimbot.solve(shooter, target_pos, target_vel, v0, gravity)` → `{pitch, yaw, time}` | `nil`

Native ballistic solver (stateless, callable anywhere). `pitch`/`yaw` are Source angles (degrees, pitch +down), `time` is flight time (seconds). `v0 ≤ 1` is treated as hitscan (`time=0`); out of range returns `nil`. Coordinates are world-space Vec3, velocity u/s, gravity u/s².

##### `game.aimbot.register_algorithm(name, fn)`

Register a movement algorithm. `name` is appended to the aim / trigger **Movement Algorithm dropdown**; when selected, this algorithm drives mouse smoothing. `fn(state)` returns `dx, dy` (mickey delta; the engine accumulates sub-pixel residue). Auto-unregistered on script unload.

> **Must be called from the script's top-level load body** — deferred callbacks (`event.on("frame_update", ...)`, `Delay()`, `gui.Button` callbacks, etc.) are rejected with a throttled log warning, because the owner identity is cleared after load completion and cannot be reliably attributed (would silently leak across scripts). For lazy enable, keep `register_algorithm` in the body and gate behavior with a Lua-side flag.

`state` fields:

| field | type | meaning |
|---|---|---|
| `err_pitch` / `err_yaw` | number (deg) | current aim error (prediction-compensated + dead-zoned) |
| `dt` | number (s) | time since this algorithm was last called |
| `distance` | number (m) | target distance |
| `zooming` | bool | ADS or not |
| `mouse_sens` | number | in-game sensitivity (for screen-consistent scaling: `err/0.022/mouse_sens` → mickey) |
| `target_index` | int | target entity index |
| `shooter` / `sway` | Vec3 / Vec2 | shooter origin / current reference view |
| `target` / `velocity` | Vec3 | world hit point / target velocity (u/s) |

> Sign convention matches native: `dx = -err_yaw·k`, `dy = err_pitch·k`.

##### `game.aimbot.set_predictor(fn)`

Globally **override the prediction algorithm**. `fn(target)` returns a world aim point `Vec3`; the aim thread consumes it at 500Hz in place of native `solve`. Pass `nil` to clear (fall back to native). `target` fields: `index`, `shooter`, `aim_point`, `head`, `origin`, `velocity` (Vec3), `distance`, `v0`, `gravity`.

> **`aim_point` vs `head`**: `aim_point` is the current actual aim point — in upper-body / full-body modes it rides the body part nearest the crosshair and moves with it, so compute the lead against it. `head` is the stable real head-bone world point, only for head-specific logic (e.g. fixed head-aim compensation). Always lead with `aim_point`, not `head` (otherwise the aim point gets pulled back to the head and cancels the tracking).

> Same as `register_algorithm` — **load-body-only**. Also one-predictor-per-process: if another script already owns the predictor, calls are rejected silently to Lua (throttled log only). Convention: one predictor per process, or unload the holding script first.

```lua
local tab  = gui.tab("AimAlgo")
local g    = tab:group("g", "Lua Aim Algo", 0, 0, 300, 0)
local gain = g:slider_float("gain", "Strength (mickey/deg)", 0.55, 0.05, 2.0)
local lead = g:checkbox("lead", "Prediction override", true)

-- Adaptive easing smoother: appears in the dropdown, active when selected
game.aimbot.register_algorithm("Lua Adaptive", function(s)
    local mag = math.sqrt(s.err_pitch^2 + s.err_yaw^2)
    local f   = gain:get() * (1.0 - 0.4 * math.exp(-mag))   -- soft near target, full far
    return -s.err_yaw * f, s.err_pitch * f
end)

-- Prediction override: reuse native solve for flight time, extrapolate by velocity
game.aimbot.set_predictor(function(t)
    if not lead:get() then return t.aim_point end
    local sol = game.aimbot.solve(t.shooter, t.aim_point, t.velocity, t.v0, t.gravity)
    if not sol then return t.aim_point end
    return Vec3(t.aim_point.x + t.velocity.x * sol.time,
                t.aim_point.y + t.velocity.y * sol.time,
                t.aim_point.z + t.velocity.z * sol.time)
end)
```

---

### `game.world`

| Field | Type | Description |
|---|---|---|
| `ring` | table | `{origin=Vec3, radius_start=N, radius_end=N, time_start=N, time_end=N, is_active=bool}`; radius / origin are in game units (≈ inches), divide by 39.37 for meters |
| `map_name` | string | Current map string |

---

### `game` top-level methods

| Method | Returns | Description |
|---|---|---|
| `game:is_in_game()` | bool | Whether currently in a match (signon_state + not in lobby/match-making) |
| `game:signon_state()` | int | Raw `client_state.signon_state` |
| `game:smart_filter()` | table \| nil | Internals of the smart item/attachment filter, see below |

---

### `game:smart_filter()`

Diagnostics: exposes the intermediate state of the smart item filter — which attachment slots the game offers for the held weapon, what each one was recognized as, and which items ended up selected. This is what answers "why isn't this attachment showing up".

**Built on demand**: each call renews a 1-second lease; with no script reading, nothing is built at all. So the **very first call always returns `nil`** (the background pass only produces data on its next recompute) — calling it every frame makes that a non-issue. One second after the last call it goes back to zero cost. Also `nil` when not in a match.

Returned table:

| Field | Type | Description |
|---|---|---|
| `recompute` | int | Recompute counter. Not moving = loadout/inventory unchanged, not a stalled feed |
| `weapons` | table | The two primary weapon slots, see below (empty slot has `weapon == ""`) |
| `desired` | table | Array of the finally selected items, each `{name, id, group, checked}` |

`weapons[i]`:

| Field | Type | Description |
|---|---|---|
| `slot` | int | 1 / 2 |
| `weapon` / `weapon_id` | string | Debug short name / item-list key; `""` for an empty slot |
| `weapon_icon` / `ammo_icon` | string | Icon resource names, feed straight into `file.image:get()` (see Icons below) |
| `ammo` | string | Ammo key from the item spec table (e.g. `ammo_energy`). **Magazines are filtered by this** |
| `mods_read` | bool | Whether the attachment list was read. false = neither attachments nor ammo will be suggested for this weapon |
| `care_package` | bool | Care-package weapon (fully kitted; nothing is suggested) |
| `dual_ammo` | bool | Dual-ammo weapon (C.A.R.) |
| `mag_offered` | table | Magazine series the game offers for this weapon (`"light"/"heavy"/"energy"/"sniper"`) |
| `mag_equipped` | table | Of those, the ones currently equipped |
| `mag_mismatch` | bool | **true = the spec table's ammo is not among `mag_offered`, so no magazine will ever be shown for this weapon** (spec table needs fixing) |
| `wanted` | table | Attachments contributed by this weapon, same shape as `desired`. This is the value **before** the global optic rules run — don't diff it against `desired` |
| `mods` | table | Per-slot attachment rows, see below |

`weapons[i].mods[k]`:

| Field | Type | Description |
|---|---|---|
| `index` | int | Index in the game's attachment list (0-based) |
| `name` | string | Raw attachment name from the game, e.g. `stock_sniper_l3` |
| `item` / `item_id` | string | Recognition result (debug short name / item key); `""` = not recognized |
| `icon` / `tier` | string / int | Icon resource name / rarity tier (0=single 1 white 2 blue 3 purple 4 gold 5 red) |
| `equipped` | bool | Currently equipped |
| `marker` | string | `""` / `"dual_ammo"` / `"care_package"` — the latter two are markers, not real attachments |

`desired[k]` / `wanted[k]`:

| Field | Type | Description |
|---|---|---|
| `name` / `id` | string | Debug short name / item-list key |
| `icon` | string | Icon resource name (see below); `""` when the item has no icon |
| `tier` | int | Rarity: 0=single tier / 1 white / 2 blue / 3 purple / 4 gold / 5 red. All tiers of one attachment share a single icon — use this to color them apart |
| `group` | string | `weapon` / `weapon_mod` / `optic` / `ammo` / `heal` / `gear` … |
| `checked` | bool | Whether it is checked in the item list. **Being checked is a hard prerequisite for drawing**: selected but unchecked still draws nothing |

#### Icons

`icon` / `weapon_icon` / `ammo_icon` are **resource names** (e.g. `icon_attachments/Extended_Energy_Mag`), not file paths. The app preloads the whole `resources/icon_*` tree into the texture table at startup, so scripts just fetch them — no file lookup, no re-rasterizing the SVG:

```lua
local tex = file.image:get(item.icon)
if tex then draw.image(tex, x, y, 28, 28) end
```

Returns nil when that item has no icon. **Don't use `file.image:load()`** for these — it re-reads and rasterizes a second copy, wasting VRAM.

```lua
-- Find weapons the spec table got wrong: ammo mismatch, or two stock series offered at once
local sf = game:smart_filter()
if sf then
    for _, w in ipairs(sf.weapons) do
        if w.mag_mismatch then
            log.warn(w.weapon .. ": wrong ammo in the spec table, its magazines will never show")
        end
    end
end
```

A full example ships with the app: `scripts/_test_16_smart_filter.lua` (window + console dump + automatic flagging).

---

### Example

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

Official source: [draw](https://docs.hoozi.cc/en/products/apex/dev/api/draw)


Screen drawing. **All `draw.*` calls go to the current frame's foreground draw list and must be called every render frame inside `event.on("frame_update")`**. The draw list is reset every frame; missing a frame = a blank flicker on screen. See [Getting Started](/en/products/apex/dev/guide).

> **Color parameter**: throughout this page `color` is a `number` (32-bit packed color), built with `draw.rgba` / `draw.u8` / `draw.hex`; you cannot pass an `{r,g,b,a}` table directly (the table form is only for ESP element palette `opts`).

---

### Color Construction (returns packed uint32)

#### `draw.rgba(r, g, b, a) → uint32` — floats 0..1
#### `draw.u8(r, g, b, a) → uint32` — ints 0..255
#### `draw.hex(packed : int) → uint32` — pass `0xRRGGBBAA` directly

---

### Color Transforms (in/out are packed uint32)

No new type; fully interoperable with `rgba/u8/hex`.

#### `draw.color_mod_a(col, v) → uint32`
**Multiplies** current alpha by `v` (0..1). Not an override — stacks well for fade-out animations.
```lua
local half = draw.color_mod_a(red, 0.5)  -- alpha halved
```

#### `draw.color_lerp(a, b, t) → uint32`
Per-channel linear interpolation (alpha included). `t` is saturated to 0..1.
```lua
-- Low health fades green → red
local hp_col = draw.color_lerp(draw.rgba(1,0,0,1), draw.rgba(0,1,0,1), hp / 100)
```

#### `draw.color_darken(col, v) → uint32`
RGB `× (1-v)`, alpha preserved. `v=0.5` → 50% darker.

#### `draw.color_lighten(col, v) → uint32`
RGB lerped toward 255 by `v`, alpha preserved. `v=0.5` → halfway to white.

#### `draw.color_hsv(h, s, v, a?) → uint32`
HSV constructor. `h` ∈ [0,360) degrees (wraps via mod), `s/v/a` ∈ [0,1]. `a` defaults to 1.0.
```lua
-- Rainbow cycle
local hue = (time.now() * 60) % 360
local rainbow = draw.color_hsv(hue, 1.0, 1.0)
```

---

### Shapes

#### `draw.line(x1, y1, x2, y2, color, opts?)`
**opts**: `{thickness = 1.0}`

#### `draw.rect(x1, y1, x2, y2, color, opts?)`
**opts**: `{filled = false, rounding = 0, thickness = 1, flags = 0}`

#### `draw.rect_gradient(x1, y1, x2, y2, c_tl, c_tr, c_br, c_bl)`
A rectangle with one color per corner. Typical use: gradient health bars / gradient backgrounds.

#### `draw.triangle_multicolor(x1, y1, c1, x2, y2, c2, x3, y3, c3)`
Triangle with a different color per vertex; the GPU interpolates the fill. Useful for fade arrows and gradient hit markers.

#### `draw.circle_multicolor(x, y, r, center_col, edge_col, opts?)`
Radial gradient from center to edge (center one color, edge another, GPU interpolates).
**opts**: `{segments = 36}`. Typical use: energy orbs, radar marker glows, minimap edge fades.

```lua
-- A glowing orb: bright white center, transparent edge
local cy = draw.rgba(1, 0.9, 0.4, 0.9)
local cx = draw.rgba(1, 0.9, 0.4, 0)
draw.circle_multicolor(x, y, 30, cy, cx)
```

#### `draw.circle(x, y, r, color, opts?)`
**opts**: `{filled = false, segments = 0, thickness = 1, fill = 1.0}`

- `fill` ∈ [0,1] — clockwise arc starting from 12 o'clock. `fill = 1.0` (default) = full circle.
  - `filled = true` + `fill < 1.0` → draws a pie (center → arc → center)
  - `filled = false` + `fill < 1.0` → draws an open arc
  - Use for CD progress rings / loading spinners / radar sectors. `fill = 1.0` takes ImGui's fast path with zero overhead.

```lua
-- 75% progress ring
draw.circle(cx, cy, 30, draw.rgba(0.3,0.9,0.4,1),
            { fill = 0.75, thickness = 4 })

-- Filled pie wedge
draw.circle(cx, cy, 30, draw.rgba(1,0.6,0,0.4),
            { filled = true, fill = 0.5 })
```

#### `draw.triangle(x1, y1, x2, y2, x3, y3, color, opts?)`
**opts**: `{filled = false, thickness = 1}`. Suited for directional arrows, FOV triangle indicators, down arrows.

#### `draw.quad(x1, y1, x2, y2, x3, y3, x4, y4, color, opts?)`
**opts**: `{filled = false, thickness = 1}`. The core of projecting a 3D box: the top/bottom face becomes a 4-vertex quad after projecting the player's 8 world-space vertices to screen.

#### `draw.polyline(points, color, opts?)`
**points**: a point sequence, both forms are accepted
- flat: `{x1, y1, x2, y2, ...}` (even length)
- nested: `{ {x1, y1}, {x2, y2}, ... }`

**opts**: `{thickness = 1, closed = false, filled = false}`
- `closed = true` → last point connects back to the start
- `filled = true` → uses `AddConvexPolyFilled` (**reliable for convex polygons only**); on the filled path, both `closed` and `thickness` are ignored

A universal fallback — can draw quads / projected box polygonal outlines / radar shapes / FOV arcs.

---

### Shadow + Glow (composite helpers)

Pure pixel helpers — multiple stacked rings approximating soft blur, no shader required. The alpha channel of `col` is the baseline intensity; `opts.alpha` is a multiplier (0..1).

#### `draw.shadow_line(x1, y1, x2, y2, color, opts?)`
A projected shadow line.
**opts**: `{offset_x = 0, offset_y = 2, blur = 3, layers = 3, alpha = 1.0}`

Larger `blur` → softer; more `layers` → smoother but more batches. `offset_x/y` is the shadow's offset relative to the original (mimics a light direction).

```lua
-- A dark shadow under outlined text
draw.shadow_line(x, y + 12, x + w, y + 12,
                 draw.rgba(0, 0, 0, 0.6),
                 { offset_y = 1, blur = 2 })
```

#### `draw.shadow_rect(x1, y1, x2, y2, color, opts?)`
Rectangle outer shadow.
**opts**: `{spread = 6, rounding = 0, layers = 3, alpha = 1.0}`

Spreads outward by `spread` pixels split into `layers` rings; inner ring almost opaque, outer rings fade out. Match `rounding` to your main rect's rounding. **Higher `layers` = softer but more batches** — default 3 is sufficient; keep it (or lower to 2) when batching ESP across many players.

```lua
-- Drop shadow below an HP bar to improve contrast over menus
draw.shadow_rect(x, y, x + w, y + h,
                 draw.rgba(0, 0, 0, 0.5),
                 { spread = 4, rounding = 2 })
draw.rect(x, y, x + w, y + h, hp_col,
          { filled = true, rounding = 2 })
```

#### `draw.glow_circle(x, y, r, color, opts?)`
Circular outer glow.
**opts**: `{spread = 8, layers = 4, alpha = 1.0}`

Spreads outward by `spread` pixels with a quadratic radial falloff (bright center, faded edge). Pairs well with `circle` for focus markers / warning lights. **`layers` is the perf knob** — default 4 with quadratic falloff keeps the batch count tractable across many player markers.

```lua
-- Radar marker highlight: glow + filled core
draw.glow_circle(mx, my, 6, draw.rgba(1, 0.3, 0.3, 0.7))
draw.circle(mx, my, 4, draw.rgba(1, 0.3, 0.3, 1), { filled = true })
```

---

### Text + Image

#### `draw.text(x, y, color, text, opts?)`
**opts**:
- `font` — font handle from `draw.font(name)` (default = system font)
- `size` — force font size float; omitted = `ImGui::GetFontSize()` (the currently-active font's size, not the `font` argument's default)
- `outline` —
  - `true` → theme dark-grey outline (project-uniform style)
  - `uint32 color` → custom outline color
  - omitted / `false` → no outline

Outline implementation = 4-direction 1px offset overlay, smooth and aliasing-free; more correct than scripting manual offset `draw.text` calls.

#### `draw.image(tex_handle, x, y, w, h, opts?)`
**Parameters**: `tex_handle` comes from [`file.image`](/en/products/apex/dev/api/file)'s `:load` / `:svg` / `:create`.

**opts**: `{tint = uint32_white, uv0 = {0,0}, uv1 = {1,1}}`

`uv0` / `uv1` must be array-style `{u, v}` tables — the `{u=..., v=...}` named form is not accepted.

#### `draw.image_rotated(tex_handle, cx, cy, w, h, angle_deg, opts?)`
Image rotated by `angle_deg` around `(cx, cy)`. `w/h` are pre-rotation dimensions.
**opts**: same as `draw.image` (`tint / uv0 / uv1`).

```lua
-- Compass arrow follows player yaw
draw.image_rotated(arrow_tex, sw/2, sh/2, 32, 32, yaw_deg)
```

---

### Clip Stack

#### `draw.push_clip(x1, y1, x2, y2, intersect?)`
Push a rectangular clip; subsequent draws are visible only inside the rect.

- `intersect` defaults to `true` (intersect with current clip — safer for nested clipping)
- Must be paired with `pop_clip` inside `frame_update`; the stack does not persist across frames.

#### `draw.pop_clip()`
Pop the most recently pushed clip rect.

```lua
-- Progress bar mask (clip image to a fraction)
draw.push_clip(x, y, x + w * progress, y + h)
draw.image(icon, x, y, w, h)
draw.pop_clip()
```

---

### Measurement

#### `draw.measure(text, opts?) → w, h`
**opts**: `{font, size}` — omitted = use the currently active font + `ImGui::GetFontSize`

#### `draw.screen() → w, h`
Current frame's screen resolution.

---

### Fonts

Fonts are loaded at project startup (ImGui font atlas is built once); **adding fonts at runtime is not supported** — user fonts must be placed in `res/fonts/` so they are auto-scanned at startup.

#### `draw.fonts() → table<string>`
Returns the list of available font names. 7 built-ins: "default" / "small" / "icon" / "logo" / "esp" / "loot" / "models", plus any `.ttf`/`.otf` files (without extension) scanned from `res/fonts/`.

#### `draw.font(name) → Font | nil`
Get a font handle; `nil` means the name does not exist.

> Note: currently `draw.font(name)` only exposes the 7 built-in fonts ("default" / "small" / "icon" / "logo" / "esp" / "loot" / "models"); `draw.fonts()` will list additional `.ttf`/`.otf` filenames under `res/fonts/`, but actual handle lookup follows the built-in names (extra fonts have no handle yet — reserved for future extension).

---

### Example

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

#### Animation composite (CD ring + color lerp + clip progress bar + rotated icon)

```lua
local start_t = time.now()
event.on("frame_update", function(e)
    local t = (time.now() - start_t) % 4.0
    local progress = t / 4.0
    local sw, sh = draw.screen()

    -- CD ring (clockwise fill)
    local ring_col = draw.color_lerp(draw.rgba(0,0.9,1,1), draw.rgba(0.2,1,0.4,1), progress)
    draw.circle(120, 120, 36, ring_col, { fill = progress, thickness = 5 })

    -- Progress bar via clip mask
    local bar_x, bar_y, bar_w, bar_h = 80, 200, 240, 14
    draw.rect(bar_x, bar_y, bar_x + bar_w, bar_y + bar_h,
              draw.color_darken(ring_col, 0.7), { filled = true, rounding = 6 })
    draw.push_clip(bar_x, bar_y, bar_x + bar_w * progress, bar_y + bar_h)
    draw.rect(bar_x, bar_y, bar_x + bar_w, bar_y + bar_h,
              ring_col, { filled = true, rounding = 6 })
    draw.pop_clip()

    -- Rotated icon (requires a file.image:load handle)
    -- draw.image_rotated(spinner_tex, 300, 120, 32, 32, progress * 360)
end)
```

---

## math

Official source: [math](https://docs.hoozi.cc/en/products/apex/dev/api/math)


Extends the Lua stdlib (**does not override** `sin/cos/pi/floor/random/...`); adds extra functions to the `math` table.

---

### Vector Types

#### `math.Vec2(x, y) → Vec2`
#### `math.Vec3(x, y, z) → Vec3`

> Note: **CamelCase** `Vec2/Vec3`, not `vec2/vec3` (lowercase `vec2` is a different internal type).

#### Vec2 / Vec3 Fields and Operators

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

### Scalar Operations

#### `math.Lerp(a, b, t) → number`
Linear interpolation. `t` is not clamped; extrapolation is legal (user's responsibility).

#### `math.Clamp(x, lo, hi) → number`

#### `math.Smoothstep(edge0, edge1, x) → number`
Hermite interpolation; input `x` within `[edge0, edge1]` smoothly transitions to `[0, 1]`, saturating at both ends.

#### `math.RemapVal(val, a, b, c, d) → number`
Linear remap: `val` is mapped from `[a, b]` onto `[c, d]`. **No clamping** (values outside `[a, b]` extrapolate).

#### `math.RemapValClamped(val, a, b, c, d) → number`
Same as `RemapVal`, but `val` is saturated to `[a, b]` first (out-of-range inputs clamp to the endpoints).

```lua
-- Map hp 0..100 to saturation 0.2..1.0
local sat = math.RemapValClamped(hp, 0, 100, 0.2, 1.0)
```

#### `math.AngleNormalize(angle_deg) → number`
Normalizes an arbitrary degree value into `[-180, 180)`.

---

### Angles / Projection

#### `math.CalcAngle(from_pos, to_pos) → pitch, yaw`
Two Vec3 → `(pitch, yaw)` in degrees; pitch is negative pointing up.

#### `math.WorldToScreen(world_pos) → sx, sy, ok`
Three return values; when `ok=false`, `sx/sy` are meaningless (out-of-game / off-screen / view matrix not ready).

#### `math.WorldRadiusToScreen(world_pos, r_world) → r_pixel, ok`
World radius → on-screen pixel radius of that world point in the 3D view. Use it when drawing circles/capsules that should match the player's body scale — don't hand-roll `r_world * half_screen_width / depth`, which assumes a 90° FOV and drifts off the target once the FOV changes. Internally it projects two world points ("center" and "center + r_world") and takes the screen distance, so it stays correct at any FOV / resolution.
- `ok = false` returns `0` (out-of-game / point behind camera)
- Not the same as `WorldRadiusToMapPixel` below: this is the 3D perspective view, that one is the top-down big map

```lua
event.on("frame_update", function()
    for _, p in pairs(game.entities.players) do
        if p.is_visible then
            local sx, sy, ok = math.WorldToScreen(p.head_pos)
            local r, ok2 = math.WorldRadiusToScreen(p.head_pos, 12)  -- head ≈ 12 inch
            if ok and ok2 then
                draw.circle(sx, sy, r, draw.rgba(1, 0.2, 0.2, 1), { thickness = 2 })
            end
        end
    end
end)
```

---

### Big-map coordinates

Built-in calibration table covers every official map (Storm Point / World's Edge / Kings Canyon / Olympus / Broken Moon ...). Scripts don't need to maintain their own scale tables.

#### `math.WorldToMapPixel(wx, wy, disp_w, disp_h) → px, py, ok`
World `(wx, wy)` → big-map PNG pixel position on a `(disp_w, disp_h)` canvas.
- `ok = false`: lobby / unknown map / not in-game → `(px, py)` falls back to canvas center
- Scale-independent (uses 4-corner calibration); disp scaling follows the canvas size

#### `math.WorldRadiusToMapPixel(r_world, disp_size) → r_pixel, ok`
World-inch radius → big-map pixel radius. `disp_size` is typically the canvas **short edge** (same-direction scaling avoids ellipse distortion).
- For death rings, blast radii, marker circles, etc.
- `ok = false` returns `0`

```lua
event.on("frame_update", function()
    -- Custom mini radar canvas: top-left 200x200
    for _, p in pairs(game.entities.players) do
        if not p.is_teammate then
            local px, py, ok = math.WorldToMapPixel(p.origin.x, p.origin.y, 200, 200)
            if ok then
                draw.circle(px, py, 3, draw.rgba(1, 0.2, 0.2, 1), { filled = true })
            end
        end
    end

    -- Death-ring radius
    local rp, ok = math.WorldRadiusToMapPixel(ring_radius_world, 200)
    if ok then
        draw.circle(100, 100, rp, draw.rgba(0.4, 0.7, 1, 0.6), { thickness = 2 })
    end
end)
```

---

### Animation Curves

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

### Example

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

Official source: [file](https://docs.hoozi.cc/en/products/apex/dev/api/file)


File I/O + image assets.

File paths are relative to the application directory. **Any path string containing the substring `..` is rejected** (sandbox); absolute paths are also rejected. Note: substring match — `my..file.txt` is also rejected.

---

### File

#### `file.read(path) → string | nil`
**Parameters**: `path : string`

#### `file.write(path, content) → bool`
**Parameters**: `path : string`, `content : string`

Parent directories are created automatically.

#### `file.exists(path) → bool`

#### `file.remove(path) → bool`

#### `file.rename(old, new) → bool`
Sandboxed rename / move. The target parent directory is created automatically. Both endpoints pass the sandbox check (no `..`, no absolute paths).

#### `file.list(dir) → table<string>`
Lists filenames inside `dir` (non-recursive, **files only, not subdirectories**). Empty / missing `dir` returns an empty table.

#### `file.scan(pattern) → table<string>`
Glob match returning full relative paths (non-recursive). Supports `*` (any sequence) and `?` (single char).

```lua
local logs = file.scan("logs/*.log")           -- {"logs/a.log", "logs/b.log", ...}
local cfgs = file.scan("scripts/state/*.json")
local r24  = file.scan("logs/2024-??-??.log")  -- single-char wildcard
```

---

### Image assets (`file.image`)

`handle` is an opaque texture handle, passed to [`draw.image`](/en/products/apex/dev/api/draw#draw-image-tex-handle-x-y-w-h-opts) to display.

When the script unloads, all image handles it created are released automatically.

#### `file.image:load(path) → handle | nil`
**Parameters**: `path : string`

Also accepts `(path, w, h)` to force a target size.

#### `file.image:svg(svg_str, w, h) → handle | nil`
**Parameters**: `svg_str : string`, `w : int`, `h : int`

#### `file.image:create(rgba, w, h) → handle | nil`
**Parameters**: `rgba : table` byte array of length `w*h*4`, `w/h : int`

#### `file.image:get(name) → handle | nil`
#### `file.image:has(name) → bool`
#### `file.image:list() → table<string>`
Lists **all texture names in TextureManager** — including project-internal ESP icons and textures created by other scripts, not just the ones owned by the current script. When pairing with `file.image:remove`, filter by owner first or you'll wipe someone else's textures.

#### `file.image:remove(name) → bool`

#### `file.image:load_gif(path) → AnimatedTexture | nil`
**Parameters**: `path : string` — GIF file path (sandboxed relative path)

Returns an `AnimatedTexture` userdata containing all frames + per-frame delays (ms). Frame SRVs are owned by the AnimatedTexture and released as a unit when the script unloads.

**AnimatedTexture methods / fields**

| Name | Description |
|---|---|
| `:advance(dt_sec) → handle` | Advance by `dt_sec`. Returns the current-frame handle — feed directly to `draw.image`. Skips frames if dt is large, never drops frames. |
| `:current_frame() → handle` | Returns current-frame handle without advancing |
| `:reset()` | Reset to frame 0 |
| `.frame_count` | int — total frames |
| `.width` / `.height` | int — GIF dimensions (consistent across frames) |
| `.current_index` | int — current frame index (0-based) |
| `.current_delay_ms` | int — current frame's delay in milliseconds |

```lua
local gif = file.image:load_gif("scripts/assets/loading.gif")
event.on("frame_update", function(e)
    if gif then
        local frame = gif:advance(e.delta_time)
        draw.image(frame, 100, 100, gif.width, gif.height)
    end
end)
```

---

### Example

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

Official source: [input](https://docs.hoozi.cc/en/products/apex/dev/api/input)


Input queries + keybind formatter + clipboard + hardware device output.

---

### `input.is_active(path) → bool`
**Parameters**: `path : string` — control full path (hotkey control)

Returns whether this hotkey is currently active (depending on mode: Toggle = toggled on / Hold = currently held / Always = always true).

---

### `input.format(path, fn)`

Attaches dynamic text + color hints to a keybind control. The formatter is only invoked while the hotkey is active (i.e. shown in the "active keybinds" overlay).

**Parameters**:
- `path : string` — **menu element full path** or **Pattern B hotkey ID** (both accepted)
- `fn : function(id : string) → string | { text = string, color = {r,g,b,a} }`

#### Automatic path resolution

Pass the menu element full path (the natural form) — if that element is a `KeybindControl` that internally remaps its keybind to a stable ID, resolution follows through to that stable ID.

| Call form | Resolution |
|---|---|
| `input.format("settings.display.menu", fn)` | → resolves to `hotkey.menu_open` |
| `input.format("hotkey.menu_open", fn)` | → used directly |
| `input.format("KbHints.g.alarm", fn)` | → user-defined KeybindControl with no remap, uses full path |

#### fn return type

| Return | Behavior |
|---|---|
| `string` | Display the text in the theme color |
| `table {text, color={r,g,b,a}}` | Custom text + color |
| other | LOG_ERR + falls back to default display |

> Owner-scoped: automatically unregistered when the script unloads.

---

### `input.unformat(path)`

Path resolution behaves identically to `input.format`.

---

### `input.clipboard_get() → string`
Reads the system clipboard. Returns an empty string when empty.

### `input.clipboard_set(text)`
Writes the system clipboard.

```lua
local key = input.clipboard_get()
if key ~= "" then gui.notify:info("read: " .. key) end

input.clipboard_set("hello")
```

---

> **Not provided**: `input.is_down(vk)` — on a dual-machine setup, the OS key API reads the machine running the program, not the game player. To query player input, use `game.localplayer.*` fields (e.g. `is_zooming`, `is_grenade`). See [Getting Started](/en/products/apex/dev/guide#no-input-is-down-vk).

---

### Formatter examples

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

### Hardware device output

Sends real mouse and keyboard input to the game machine through an external input device (KMBOX Net / KMBOX B+ / MAKCU).

**With no device connected everything is a no-op returning `false`** — no error is raised, and no alternate path is taken. Check `input.device_connected()` before relying on any of these.

::: warning Relative movement only
`input.move` is a **relative** displacement. There is no `input.move_to(x, y)`.

MAKCU firmware does have a `moveto(x, y)` command (KMBOX Net / B+ do not), but per the official API it "internally calculates the needed x,y movement to reach the requested position on the screen" — the wire format is still a relative report, and it needs a trustworthy notion of *where the cursor currently is*.

**In an FPS that reference point does not exist**: the game consumes raw input deltas with the system cursor locked to the window center, so screen coordinates have no correspondence to the in-game view angle. In a dual-machine setup this program cannot read the game machine's cursor position either. `moveto` is therefore useless for aiming, and the facade does not expose it.

To aim at a world position, use [`game.aimbot.set_predictor`](/en/products/apex/dev/api/game#game-aimbot-set-predictor) and let the aim pipeline read `view_angle` and solve for the required delta.
:::

---

#### `input.backend() → string`

Name of the current input device backend. Use it to branch on capability — backends support different actions (see the table below).

| Value | Meaning |
|---|---|
| `"disable"` | No device selected |
| `"write_view"` | Memory takeover (no hardware; everything in this section is inert) |
| `"kmboxnet"` | KMBOX Net (ethernet) |
| `"kmboxb+"` | KMBOX B+ (serial) |
| `"makcu"` | MAKCU (serial) |

#### `input.device_connected() → bool`

Whether a device is connected and usable.

#### Backend capability matrix

| Action | kmboxnet | kmboxb+ | makcu |
|---|:---:|:---:|:---:|
| `move` / `click` / `button` (left) | ✅ | ✅ | ✅ |
| `button` right / middle / side | ✅ | ⚠️ | ✅ |
| `wheel` | ✅ | ⚠️ | ✅ |
| `move_curve` (firmware-side interpolation) | ✅ | ↩︎ falls back to `move` | ✅ |
| `key_down` / `key_up` / `key_press` | ✅ | ✅ | ❌ |
| `mask` left mouse button | ✅ | ✅ | ✅ |
| `mask` other mouse buttons / `"x"` / `"y"` | ✅ | ❌ | ✅ |
| `mask "wheel"` | ✅ | ❌ | ❌ |
| `mask` keyboard keys | ✅ | ❌ | ❌ |

- ⚠️ = these KMBOX B+ command names were **extrapolated** from the naming pattern of commands that are known to work; they are unverified on real hardware. When the firmware does not recognize a command the serial write still succeeds, so `true` does not guarantee anything happened.
- ❌ = the backend lacks the capability and returns `false`. **Do not read every `false` as "no device"** — check this table first.
- MAKCU firmware has no keyboard HID channel, so the three keyboard functions are always `false` on it.

---

#### `input.move(dx, dy) → bool`
**Parameters**: `dx : int`, `dy : int` — relative displacement (mickeys; positive = right / down)

#### `input.move_curve(dx, dy, ms?) → bool`
**Parameters**: `dx : int`, `dy : int`, `ms : int` (optional, default `20`, capped at 2000)

Hands a large displacement to the firmware to push out in segments, producing a more hand-like path than small per-frame `move` calls.

::: warning Blocking push
The firmware holds the device for the whole `ms` window, stalling any aim `move` queued behind it. Keep it out of per-frame loops.
:::

#### `input.button(name, down) → bool`
**Parameters**: `name : string`, `down : bool`

| `name` | Aliases |
|---|---|
| `"left"` | `"lmb"` |
| `"right"` | `"rmb"` |
| `"middle"` | `"mmb"` / `"wheel_click"` |
| `"side1"` | `"mouse4"` / `"x1"` |
| `"side2"` | `"mouse5"` / `"x2"` |

#### `input.click(name?) → bool`
Press + release once. Omitting `name` means left button.

#### `input.wheel(delta) → bool`
**Parameters**: `delta : int` — detents (positive = scroll forward)

---

#### `input.key_down(key)` / `input.key_up(key)` / `input.key_press(key)` → bool
**Parameters**: `key : string` — a single character (`"r"`) or a key name (`"shift"` / `"enter"` / `"f1"` / `"space"` / `"lctrl"`, arrow keys such as `"up"`, …)

`key_press` = press + release once.

> The MAKCU backend has no keyboard channel; these three are always `false` there.

---

#### `input.mask(what, enable) → bool`

Blocks the player's **physical** input from reaching the game. Useful for taking over a key — the box swallows the player's own press, and the script decides when to actually emit it.

**Parameters**:
- `what : string` — a mouse button name (same as `input.button`) / `"x"` / `"y"` / `"wheel"` / a keyboard key name
- `enable : bool`

::: warning Precondition for keyboard masking
Keyboard masks only take effect when the **physical keyboard is plugged into the box**. If the keyboard is connected directly to the game machine the box cannot intercept it, and the call returns `true` with no actual effect.
:::

> All masks are released automatically when the script unloads — see "Automatic cleanup" below.

---

#### Automatic cleanup

**Stateful** device operations are tracked per owning script and reverted automatically when the script unloads (hot reload / config switch / manual unload):

| Operation | On unload |
|---|---|
| `input.button(name, true)` held | Released |
| `input.key_down(key)` held | Released |
| `input.mask(what, true)` | Cleared |

Without this layer, a script unloaded while holding the left button would leave that button **stuck in the box firmware permanently** — in game it reads as continuous fire that the user cannot stop by clicking their own mouse.

`click` / `move` / `wheel` / `key_press` are instantaneous and need no cleanup.

---

#### Interaction with the trigger

The trigger decides whether to yield based on whether this machine is firing, and a left click sent through the box looks exactly like the player firing manually. `input.click("left")` and `input.button("left", false)` notify the trigger that the shot came from a script — **scripts do not need to handle this themselves**.

While a script **holds** the left button the trigger yields and does not fire. That is the correct behavior: fire is already sustained, so an extra trigger shot would be meaningless.

---

#### Device output examples

```lua
-- Capability branching: backends differ in what they can do
local backend = input.backend()
if not input.device_connected() then
    gui.notify:warn("no input device connected")
    return
end

-- Trace a square slowly (firmware interpolation looks better than per-frame move)
for _, d in ipairs({ {200,0}, {0,200}, {-200,0}, {0,-200} }) do
    input.move_curve(d[1], d[2], 150)
end

-- Side-button tap: press -> 60ms -> release
input.button("side1", true)
Delay(0.06, function() input.button("side1", false) end)

-- Take over the R key: swallow the player's physical R, emit it on our terms
-- (only works on kmboxnet with the keyboard plugged into the box)
if backend == "kmboxnet" then
    input.mask("r", true)
    event.on("frame_update", function()
        if should_reload_now() then
            input.mask("r", false)
            input.key_press("r")
            input.mask("r", true)
        end
    end)
end
```

---

## log

Official source: [log](https://docs.hoozi.cc/en/products/apex/dev/api/log)


Developer diagnostic log, viewable in the in-menu console.

Difference from `notify.*`:

| Purpose | Use | Who sees it |
|---|---|---|
| Developer diagnostics / debug info / error tracing | `log.*` | In-menu console |
| User-facing messages (action feedback, error warnings) | [`gui.notify:*`](/en/products/apex/dev/api/gui#notifications-gui-notify) | Floating toast, auto-dismisses in ~3-5s |

---

### `log.info(...)` / `log.success(...)` / `log.warn(...)` / `log.error(...)`

**Parameters**: variadic (multiple arguments are joined with tabs automatically)

> `log.error` output only contains the Lua-side origin, not internal binding call frames, keeping the console clean.

---

### Example

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

Official source: [script](https://docs.hoozi.cc/en/products/apex/dev/api/script)


Script meta-management.

---

### `script.load(path) → bool`
**Parameters**: `path : string` — path relative to `scripts/`

### `script.unload(path) → bool`

---

### Example

```lua
-- Load another script (typically called from an interactive button)
if not script.load("_test_05_net.lua") then
    gui.notify:error("Load failed", 2.0)
end
```

---

## time

Official source: [time](https://docs.hoozi.cc/en/products/apex/dev/api/time)


Time.

---

### `time.now() → number`
Real seconds (equivalent to `os.clock`).

### `time.delta() → number`
Last-frame delta time.

### `time.game() → number`
In-game time, sourced from `LocalPlayer.time_base` (pauses when the game pauses).

### `time.curtime() → number`
Server-authoritative time (reads `client_state.curtime` directly). Usually agrees with `time.game()`, but **`curtime` is the only authoritative source for server-side state such as death-ring countdowns and bullet time** — use it when you care about server-side ring shrink / tick sync. Returns `0` when no game state is available.

### `time.frame_count() → number`
Render frame count, monotonically increasing, +1 per rendered frame.

---

| Function | Meaning | Use |
|---|---|---|
| `time.now()` | Wall-clock seconds (equivalent to `os.clock()`) | Timers / throttling / any "real-time seconds" |
| `time.delta()` | Duration of the previous frame (seconds) | Rate integration (movement, animation lerp) |
| `time.game()` | In-game time (local-side) | Synced with in-game time (pauses when the game pauses) |
| `time.curtime()` | Server-authoritative time | Death rings / bullet time / server-side countdowns |
| `time.frame_count()` | Cumulative render frame count | Modulo scheduling (`% N == 0`), lightweight periodic tasks |

```lua
-- Run a heavy task once every 60 frames (~1s @ 60fps)
event.on("frame_update", function(e)
    if time.frame_count() % 60 == 0 then
        do_heavy_thing()
    end
end)
```

You can also read `e.delta_time` from the first argument `e` of [`event.on("frame_update", fn)`](/en/products/apex/dev/api/event)'s `fn(e)` — the value is equivalent to `time.delta()` with one fewer function call.

---

## config

Official source: [config](https://docs.hoozi.cc/en/products/apex/dev/api/config)


Plan-level file management. **Menu values still go through [`gui.set` / `gui.get`](/en/products/apex/dev/api/gui#top-level-creation-lookup)** — `config.*` only handles plan switching / listing / saving as a new plan.

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

### Example

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

Official source: [json](https://docs.hoozi.cc/en/products/apex/dev/api/json)


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

### `json.encode(value, pretty?) → string`

**Parameters**:
- `value : any` — value to serialize
- `pretty? : bool = false` — true uses 2-space indentation for readability

Returns `"null"` on serialization failure (rare, only when types are unrecoverable).

---

### `json.decode(text) → value | nil, err_msg`

**Parameters**: `text : string`

**Returns**: on success, a single Lua value; on failure, `(nil, error_string)` — check with `if v == nil then ...`.

> A table received in Lua with contiguous `1..N` integer keys = JSON array; other key shapes = JSON object. **An empty table `{}` is encoded as `"[]"` by default** (treated as an empty array); for an empty object, add any string key to force the non-array path.

---

### Example

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

Pairs well with [`net.http`](/en/products/apex/dev/api/net) for remote config pushes:

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

## utils

Official source: [utils](https://docs.hoozi.cc/en/products/apex/dev/api/utils)


String / encoding / hashing / time / persistence utilities. **Domain-agnostic** — does not overlap with `file` / `input` / `json` etc.

---

### Encoding

#### `utils.base64_encode(text) → string`
Standard RFC 4648 base64 with `=` padding. Input is treated as a byte stream (may contain `\0` etc).

#### `utils.base64_decode(text) → string`
Decodes base64. `\n` / `\r` / space are skipped; invalid characters are tolerated (no error). `=` padding handled.

#### `utils.array_to_string(bytes) → string`
1-based byte table → string (elements 0–255). Useful for hand-rolling binary protocols; `file.read` already returns a string and does not need this.

#### `utils.string_to_array(text) → table<int>`
String → 1-based byte table.

---

### Hashing

#### `utils.murmur2(text) → int`
MurmurHash2 32-bit (Austin Appleby original, seed=0). Returns a uint32 (LuaJIT integer-safe up to 2^53).

#### `utils.fnv1a(text) → int`
FNV-1a 32-bit.

---

### Time

#### `utils.unix_time() → int`
Current Unix timestamp (seconds). **Different from `time.now()`** — `time.now()` is a monotonic steady_clock, not a wall clock. Use `unix_time()` for log timestamps or server sync.

#### `utils.get_date() → table`
Current local date/time as `{year, month, day, hour, minute, second, dst}`.

---

### Clipboard

Clipboard has moved out of `utils.*`. Use [`input.clipboard_get`](/en/products/apex/dev/api/input) / [`input.clipboard_set`](/en/products/apex/dev/api/input).

---

### Script-scoped KV persistence

`db_save` / `db_load` store data scoped to the calling script (as opposed to `config.*` which is global). Files land in `conf/lua_db/<owner-hash>__<key>.json`; owner is automatically the current `_SCRIPT_PATH`, so **the same key in different scripts does not collide**.

Values pass through `json.encode/decode`, so any combination of `table` / `string` / `number` / `bool` / `nil` works (functions and userdata do not).

#### `utils.db_save(key, value) → bool`
- `key`: `[a-zA-Z0-9_.-]+` and ≤64 chars; invalid keys return `false`.
- Returns `true` on success; failures are logged.

#### `utils.db_load(key, default?) → value`
- Same key rules as above.
- Missing key or parse failure returns `default` (default `nil`).

---

### Example

```lua
-- HTTP Basic Auth
local cred = utils.base64_encode("user:pass")
net.http:get("https://api.example.com/private", {
    headers = { ["Authorization"] = "Basic " .. cred }
}, function(r) end)

-- Hash a config id to dedupe
local id = utils.fnv1a(json.encode(cfg))

-- Log with timestamp
log.info(("[%d] %s"):format(utils.unix_time(), msg))

-- Run once per day
local d = utils.get_date()
local today = ("%04d-%02d-%02d"):format(d.year, d.month, d.day)
if utils.db_load("last_day") ~= today then
    log.info("new day: " .. today)
    utils.db_save("last_day", today)
end

-- Persist UI state across sessions
local saved = utils.db_load("ui_pos", { x = 100, y = 100 })
event.on("frame_update", function()
    -- ... on drag end:
    utils.db_save("ui_pos", { x = win.x, y = win.y })
end)
```

---

## mem

Official source: [mem](https://docs.hoozi.cc/en/products/apex/dev/api/mem)


DMA memory read + write + pattern scanning. Combined with entity `.base` (see [game](/en/products/apex/dev/api/game)) and the [offsets](/en/products/apex/dev/api/offsets) table, scripts can self-service read/write any unwrapped game attribute.

> **Writes are risky — on you**: `write_*` is raw memory write with no guardrails. A wrong address or value can corrupt game state, crash the game, and in the worst case draw anti-cheat attention. Reads never corrupt state; all the danger is on the write side. Invalid addr is silently skipped (same as reads), but **whether the address/value is correct is nobody's job but yours**.
>
> **Performance**: a single `read_*` / `write_*` blocks ~200-500µs (synchronous DMA round-trip). Per-frame multi-field read/write **must** use `mem.scatter` / `mem.write_scatter` to batch — otherwise `frame_update` stalls.

---

### Module info

#### `mem.get_module_base(name) → uint64`
Module base address. Returns `0` on failure.

#### `mem.get_module_size(name) → uint64`
Module code-segment size. Returns `0` on failure.

#### `mem.is_valid(addr) → bool`
Fast pointer sanity check (non-zero, non-sentinel, in user-mode range). **Does not access memory** — purely local validation.

```lua
local base = mem.get_module_base("r5apex.exe")
print(string.format("base = 0x%X", base))
```

---

### Pattern scan

#### `mem.find_pattern(module_name, pattern) → uint64`

IDA-style byte-pattern scan. `?` matches any byte; bytes separated by spaces. Returns `0` on miss.

> **Each call scans the entire module code segment (several MB), costing tens of milliseconds**. Always cache the resolved addr — **never call per-frame**. Typical pattern: resolve once at script load, then use the cached addr with `read_*` / `scatter`.

```lua
local addr = mem.find_pattern("r5apex.exe", "48 8B 05 ? ? ? ? 48 8B 88")
if addr ~= 0 then
    -- RIP-relative resolve: disp32 at addr+3, target = addr+7+disp
    local disp = mem.read_i32(addr + 3)
    local target = addr + 7 + disp
    print(string.format("target = 0x%X", target))
end
```

---

### Single reads (synchronous, for cold paths / debugging)

| Function | Return | Notes |
|---|---|---|
| `mem.read_i8(addr)` | int | -128..127 |
| `mem.read_u8(addr)` | int | 0..255 |
| `mem.read_i16(addr)` | int | |
| `mem.read_u16(addr)` | int | |
| `mem.read_i32(addr)` | int | |
| `mem.read_u32(addr)` | int (unsigned) | |
| `mem.read_i64(addr)` | int64 | |
| `mem.read_u64(addr)` | uint64 | typical for pointers |
| `mem.read_float(addr)` | number | f32 |
| `mem.read_double(addr)` | number | f64 |
| `mem.read_vec2(addr)` | Vec2 | 8 bytes |
| `mem.read_vec3(addr)` | Vec3 | 12 bytes |
| `mem.read_bytes(addr, len) → table<byte>` | array | empty table when len > 1MB |
| `mem.read_string(addr, max_len?) → string` | string | null-terminated, default max 256, cap 4096 |

Invalid addr / read failure → returns default value (0 / "" / zero vec). **Never throws**.

#### `mem.read_chain(base, {off1, off2, ...}) → uint64`

Multi-level pointer dereference: `Read<u64>(base + off1) → Read<u64>(prev + off2) → ...`. Returns `0` as soon as any step reads zero.

```lua
local lp_ptr = mem.read_chain(base, { 0x1F12345, 0x80, 0x18 })
```

---

### Single writes (synchronous, **dangerous**)

Naming / type set mirror `read_*` 1:1 — the signature is the read plus one `value` argument.

| Function | value type | Notes |
|---|---|---|
| `mem.write_i8(addr, v)` | int | truncated to 8-bit |
| `mem.write_u8(addr, v)` | int | |
| `mem.write_i16(addr, v)` / `mem.write_u16(addr, v)` | int | |
| `mem.write_i32(addr, v)` / `mem.write_u32(addr, v)` | int | |
| `mem.write_i64(addr, v)` / `mem.write_u64(addr, v)` | int64 / uint64 | |
| `mem.write_float(addr, v)` | number | f32 |
| `mem.write_double(addr, v)` | number | f64 |
| `mem.write_vec2(addr, v)` | Vec2 | 8 bytes |
| `mem.write_vec3(addr, v)` | Vec3 | 12 bytes |
| `mem.write_bytes(addr, {0x12, 0x34, ...})` | byte table | cap 1MB |
| `mem.write_string(addr, str)` | string | no trailing NUL; include it yourself if needed (`"foo\0"`) |

Invalid addr → silently skipped, never throws. Address / value correctness is the author's responsibility.

```lua
local lp  = game.localplayer
local off = offsets.RecvTable.DT_Player.m_iHealth   -- named offset, see the offsets page
mem.write_i32(lp.self_base + off, 100)               -- set own health (demo, on you)
```

---

### Batch reads (scatter, **mandatory for per-frame multi-field**)

#### `mem.scatter(reqs_table) → results_table`

Single DMA round-trip processes N read requests. Each req is `{ type, addr [, size] }`. Returns 1-based result table in request order.

| type | meaning | 3rd arg |
|---|---|---|
| `"i8"` / `"u8"` / ... `"i64"` / `"u64"` | integers | none |
| `"f32"` / `"float"` | 32-bit float | none |
| `"f64"` / `"double"` | 64-bit float | none |
| `"vec2"` / `"vec3"` | vectors | none |
| `"bytes"` | byte table | **size required** |
| `"string"` | null-terminated string | **size = max_len required** |

```lua
-- Batch 3 fields in one frame
local r = mem.scatter({
    { "u32", lp_ptr + 0x0238 },         -- health
    { "vec3", lp_ptr + 0x014C },        -- origin
    { "string", lp_ptr + 0x500, 32 },   -- name
})

local health, origin, name = r[1], r[2], r[3]
print(health, origin.x, name)
```

**Performance** (60 players × 4 fields per frame = 240 reads):
- Single `mem.read_u32 × 240` → ~96ms / frame (frame-killing)
- `mem.scatter(...240 reqs)` → one round-trip, ~2ms / frame

Invalid addr / failed entry returns default — **does not abort subsequent entries**.

**Error signals**:
- Wrong type (e.g. `"u9"`) → that slot returns `nil` + console `LOG_WARN` (distinguishable from reading 0)
- Non-table entry (passed a string / number) → that slot returns `nil` + `LOG_WARN`

---

### Batch writes (write_scatter)

#### `mem.write_scatter(reqs_table) → count actually written`

Single DMA round-trip writes N addresses. Each req is `{ type, addr, value }` — mirrors `mem.scatter`, only the 3rd element changes from size (read) to value (write). Type set is identical to scatter reads.

```lua
mem.write_scatter({
    { "i32",   base + off_a, 100 },
    { "float", base + off_b, 1.5 },
    { "vec3",  base + off_c, vec3(x, y, z) },
})
```

Entries with invalid addr / encode failure (value type mismatch) are skipped — no whole-batch failure + `LOG_WARN`; returns the count actually written.

---

### Safety / Limits

- **Writes have no guardrails**: address / value correctness is entirely on the author; a wrong write can crash the game. Offsets drift across game updates (use the [offsets](/en/products/apex/dev/api/offsets) table, which auto-syncs with the dumper).
- All reads/writes target the currently-attached game process; no pid parameter.
- When DMA has not attached / process is gone, `get_module_base` returns 0, `read_*` returns defaults, `write_*` skips. Guard with `mem.is_valid`.
- A `mem.scatter` / `mem.write_scatter` reqs table with 1000+ entries can visibly stall the current frame — split very large batches across frames.

---

## offsets

Official source: [offsets](https://docs.hoozi.cc/en/products/apex/dev/api/offsets)


Named game-offset table. The dumper's full offset output is loaded into one nested global table — combine it with entity `.base` (see [game](/en/products/apex/dev/api/game)) and [mem](/en/products/apex/dev/api/mem) `read/write` to self-service read/write any attribute, without hardcoding magic numbers, and it **auto-syncs with game updates** (re-dump on an offset change and the table follows).

```lua
local lp  = game.localplayer
local off = offsets.RecvTable.DT_Player.m_iHealth   -- 0x324, named lookup, not hardcoded
local hp  = mem.read_i32(lp.self_base + off)
```

---

### Access shape

Grouped by the dumper's two levels of section / subsection:

```lua
offsets[section][key]              -- subsection empty (e.g. Buttons / Mics / Globals)
offsets[section][subsection][key]  -- subsection present (e.g. RecvTable / dataMap / ClientClass)
```

Examples:

```lua
offsets.RecvTable.DT_Player.m_iHealth     -- entity network field
offsets.dataMap.CBaseGrenade.m_flDamage   -- dataMap field
offsets.Mics["CPlayer!camera_angles"]     -- bracket form for keys with special chars
offsets.Buttons["+attack"]                -- button command address
```

Values are `uint64` (addresses or in-class offsets). All values fit within Lua's exact-integer range — no precision loss.

#### `offsets.find(section, subsection, key) → uint64 | nil`

Dynamic lookup, for when the key is built at runtime (the nested table only takes literal paths). Pass `""` for an empty subsection. Returns `nil` on miss.

> **Don't call it per-frame** — `find` is a full linear scan (9551 entries). When you can write a literal path, use the nested table `offsets[section][sub][key]` (O(1)); reserve `find` for cold paths where the key is built at runtime and resolved once at init.

```lua
local function health_off(dt)            -- dt decided at runtime
    return offsets.find("RecvTable", dt, "m_iHealth")
end
```

---

### Section overview

The dumper's main groups (entry counts drift across versions):

| section | Contents | Direct `base + off` read? |
|---|---|---|
| `RecvTable` | Entity network fields (`DT_Player` / `DT_AI_BaseNPC` / ...) | Mostly yes — see caveat below |
| `dataMap` | Server datamap fields (`CBaseGrenade` / ...) | Mostly yes |
| `Mics` | Hand-maintained misc offsets (camera_angles / studio hdr / ...) | **Verified** — safe to use |
| `Buttons` | Button command (`+attack` / `+jump` / ...) addresses | Absolute addresses, read directly |
| `Convars` / `ConCommands` | convar / command object addresses | Absolute addresses |
| `WeaponSettings` / `Globals` / `ClientClass` etc. | Other engine structures | Field-dependent |

---

### The catch: offsets are not guaranteed to equal real memory layout

- The `RecvTable` section holds network-packet field offsets. **Most** equal the real in-class memory offset and read fine via `base + off`, but **not every one is guaranteed** — same rule as the internal C++ side verifying before relying on an offset. When a read returns nonsense, first suspect that the offset isn't a memory-layout offset.
- The `Mics` section is the hand-verified batch — most reliable.
- Offsets drift across major game updates. This table syncs with the dumper, but your hardcoded "`base + some offset` means this semantic" logic can break when the structure changes.
- Double caution on writes: a wrong read offset just yields a garbage value; a wrong write can crash the game (see the write warning in [mem](/en/products/apex/dev/api/mem)).

---

### Auto-cleanup

`offsets` is a read-only static table holding no resources — nothing to clean up.

---

## Globals + Overview

Official source: [Globals + Overview](https://docs.hoozi.cc/en/products/apex/dev/api/globals)


Quick reference: module structure overview, style conventions, global variables. Each module's detailed fields and signatures are in the corresponding sidebar page.

---

### Module Structure Overview

```
══ Globals ═════════════════════════════════════════════════════════════
_SCRIPT_PATH        Current script path (read-only)
print               Redirected to log.info
Delay(sec, fn)      Run fn after sec seconds (auto-cancelled on unload)
shared              Cross-script shared Lua table

══ Primary domain 9 ═══════════════════════════════════════════════════

event                                   Subscribe
├─ on(name, fn) → handle
└─ off(handle)

gui                                     Menu UI + config write (the only write path)
├─ tab / sub_tab / window
├─ find / get / set / children       children(path) returns a container's direct child controls
├─ show / hide / set_enabled / set_visible
├─ is_visible / get_main_window      Menu state + geometry
├─ list_hotkeys                       Every hotkey-bound control (Checkbox + KeybindControl)
├─ get_selected_weapon               Currently selected weapon ID in the weapon library
├─ Container methods: group/checkbox/slider/slider_float/dropdown/
│             combobox/slider_range/color_edit/input_text/multi_dropdown/
│             keybind_control/tips/live_table/button/settings
│             settings(id,label,icon?) gear-collapsed container
├─ custom(id, proto, height?)        Lua-driven custom control (LuaControlProto-style)
└─ Window only: bind_visible

esp                                     ESP elements
├─ add / find / remove
├─ elements / scenario
└─ INV / VIS / DWN / ALLY

game                                    Live data (read-only, writes raise an error)
├─ localplayer
├─ entities.{players,loots,projectiles}
├─ aimbot                               trigger / solve / register_algorithm / set_predictor
└─ world.{ring,map_name}

net
├─ http: get / post / request             Async only (callback dispatched on menu thread)
├─ ws:   connect / send / close / is_open Client, all async with 4 callbacks
└─ ws_server: listen → :send / :broadcast / :disconnect / :close

draw                                    Screen drawing
├─ line / rect / rect_gradient
├─ triangle_multicolor / circle_multicolor
├─ circle / triangle / quad / polyline
├─ shadow_line / shadow_rect / glow_circle  Shadow + outer glow
├─ text / image / image_rotated
├─ push_clip / pop_clip                 Rectangular clip stack
├─ measure / screen / fonts / font
└─ rgba / u8 / hex / color_mod_a / color_lerp
   color_darken / color_lighten / color_hsv

math                                    Extends Lua stdlib
├─ Vec2 / Vec3
├─ Lerp / Clamp / Smoothstep
├─ RemapVal / RemapValClamped
├─ AngleNormalize / CalcAngle
├─ WorldToScreen / WorldRadiusToScreen / WorldToMapPixel / WorldRadiusToMapPixel
└─ ease_in / ease_out / ease_in_out / ease_in_cubic
   ease_out_cubic / ease_bounce

file                                    Files + resources
├─ read / write / exists / remove / rename
├─ list / scan(glob)
└─ image: load / svg / create / get / has / list / remove
   load_gif / animated multi-frame

input                                   Input + keybind formatter + clipboard + device output
├─ is_active / format / unformat
├─ clipboard_get / clipboard_set
├─ backend / device_connected        backend name + link state (capabilities differ; check the matrix)
├─ move / move_curve                 relative only (FPS locks the cursor; no reference for absolute)
├─ button / click / wheel            left/right/middle/side1/side2
├─ key_down / key_up / key_press     MAKCU has no keyboard channel
└─ mask(what, enable)                block physical input (mouse button / x / y / wheel / key name)

══ Misc 8 ══════════════════════════════════════════════════════════════

log         info / success / warn / error
notify      info / success / warn / error
script      load / unload
time        now / delta / curtime / game / frame_count
config      save / save_as / switch / list / current
json        encode / decode
utils       base64_encode / base64_decode / array_to_string / string_to_array
            murmur2 / fnv1a / unix_time / get_date
            db_save / db_load  (script-scoped KV persistence)
            (clipboard moved → input.clipboard_get / clipboard_set)
mem         get_module_base / get_module_size / is_valid / find_pattern
            read_* / scatter / write_* / write_scatter  (DMA read+write; writes are dangerous, see the mem page)
offsets     named offset table offsets[section][sub][key] / offsets.find  (dumper-synced, pairs with .base for self-service)
```

---

### Style Conventions

| Form | Purpose |
|---|---|
| `obj:method(args)` | Stateful object methods (gui.find, network, file resources, esp element) |
| `obj.field` | Read-only data fields (game.* / event parameters / entity attributes) |
| `module.sub.field` or `module.sub:method` | Nested namespace (`net.http` / `game.entities` / `file.image`) |
| `module.func(args)` | Module shortcut function |

**Naming**: modules are all-lowercase single words / functions and fields are snake_case / constants are SCREAMING_CASE / usertypes are CamelCase / event names are snake_case strings.

**Owner-scoped auto cleanup**: When a script is unloaded, the following resources are released automatically; you don't need to hand-write a `script_unloaded` listener.

- `event.on` subscriptions (including custom event handlers)
- `Delay()` pending entries (un-fired entries are cancelled)
- `esp.add` elements
- Containers and controls created via `gui.*`
- `input.format` keybind formatters
- `net.http` callbacks (alive flag — queued callbacks are dropped silently)
- `net.ws:connect` connections + `net.ws_server:listen` listeners (including all clients)
- `file.image:load/svg/create/load_gif` textures

---

### Global Variables

#### `_SCRIPT_PATH : string` (read-only)
The path of the currently executing script (relative to `scripts/`). Injected by the runtime before the script is loaded.

#### `print(...)`
Redirected to `log.info`.

#### `Delay(sec : number, fn : function)`
Calls `fn` once after `sec` seconds. Fires on the render thread, in sync with `event.on("frame_update", ...)`. Pending entries are auto-cancelled when the script is unloaded — no manual cleanup needed.

```lua
Delay(0.5, function() print("printed after 0.5s") end)

-- Pair with Delay for polling / retries
local function retry(n)
    if n <= 0 then return end
    net.http:get("https://api/heartbeat", function(resp)
        if not resp.ok then Delay(1, function() retry(n - 1) end) end
    end)
end
retry(3)
```

#### `shared : table`
A plain Lua table shared across scripts. Any script can read or write it; its lifetime matches the Lua state. Writes are visible to other scripts immediately — no snapshot, no lock.

**Reload does not clear it**: script reload only unloads the GUI / event / esp resources registered by that script. `shared` itself is created once when the Lua state is built and is never wiped. A script that wants its own namespace reset on reload must do `shared.my_ns = {}` itself at the top.

See [Getting Started](/en/products/apex/dev/guide) for usage patterns.
