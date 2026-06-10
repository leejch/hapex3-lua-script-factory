# HApex3 Lua Script Factory

A factory-style repository for continuously creating, modifying, organizing, and archiving HApex3.0 / HOOZi Lua scripts.

This repository is not only a normal Lua script project. It is designed as a reusable **script asset factory**:

* Each new Codex conversation can create a new Lua script.
* Existing Lua scripts can be modified, forked, improved, or specialized.
* Finished scripts are treated as reusable assets.
* Old versions are intentionally archived inside the repository, not only recovered through Git history.
* Scripts are organized by their primary HApex3.0 Lua API module or dominant runtime purpose.

English is the native documentation language for this repository.
`README_CN.md` is a Simplified Chinese translation of this file.

## AI entry points

This repository is intended to be used with OpenAI Codex, Codex CLI, Claude Code, opencode, Aider, or other AI coding assistants.

The main AI instruction files are:

```text
AGENTS.md
SKILL.md
```

Use them as follows:

| File           | Main consumer                                                | Purpose                                              |
| -------------- | ------------------------------------------------------------ | ---------------------------------------------------- |
| `AGENTS.md`    | Codex / Codex CLI / opencode / Aider / AGENTS.md-aware tools | Main project instruction file                        |
| `SKILL.md`     | Claude Code                                                  | Skill-style entry file with dispatch metadata        |
| `README.md`    | Humans and AI agents                                         | Repository overview, asset workflow, directory rules |
| `README_CN.md` | Humans and AI agents                                         | Simplified Chinese translation of `README.md`        |

For Codex cloud usage, `AGENTS.md` is the most important instruction file.
Codex should read `AGENTS.md` before generating, editing, or moving Lua scripts.

Do not generate scripts from `README.md` alone.
`README.md` explains the repository workflow; `AGENTS.md` defines coding behavior.

## Core repository purpose

This repository exists to support a repeated workflow:

```text
New Codex conversation
        ↓
User describes a Lua script requirement
        ↓
Codex reads AGENTS.md and references/
        ↓
Codex creates or modifies a script
        ↓
Script is saved into the correct factory directory
        ↓
Stable script becomes a reusable asset
        ↓
Older or alternate versions are archived for future reuse
```

The repository should preserve useful script history even when the user does not want to inspect Git commits.

The archive directory is therefore part of the project design.
It is not a replacement for Git, but it provides a practical human-readable script library of old, alternate, or deprecated versions.

## Recommended repository structure

```text
hapex3-lua-script-factory/
├── README.md
├── README_CN.md
├── AGENTS.md
├── SKILL.md
├── CATALOG.md
├── references/
│   ├── api-reference.md
│   ├── guide.md
│   └── examples.md
├── scripts/
│   ├── _workbench/
│   ├── _templates/
│   ├── finished/
│   │   ├── event/
│   │   ├── gui/
│   │   ├── esp/
│   │   ├── net/
│   │   ├── game/
│   │   ├── draw/
│   │   ├── math/
│   │   ├── file/
│   │   ├── input/
│   │   ├── log/
│   │   ├── script/
│   │   ├── time/
│   │   ├── config/
│   │   ├── json/
│   │   └── mixed/
│   └── archive/
│       └── asset-name/
├── lib/
├── tests/
├── tools/
└── .gitignore
```

## Required top-level files

### `AGENTS.md`

The main instruction file for Codex and other AGENTS.md-aware tools.

It should define:

* when the HApex3.0 / HOOZi Lua scripting context applies
* how to use the reference files
* API calling conventions
* script generation rules
* comment language requirements
* directory placement rules
* archive rules
* validation expectations

When in conflict, `AGENTS.md` has higher priority than `README.md`.

### `SKILL.md`

The Claude Code skill entry file.

It should contain the same core scripting conventions as `AGENTS.md`, but in the skill format expected by Claude Code.

### `CATALOG.md`

A human-readable index of script assets.

This file should list important scripts, their purpose, status, module category, path, and latest known verification state.

Suggested columns:

| Asset            | Category | Path                                                    | Status       | Notes                           |
| ---------------- | -------- | ------------------------------------------------------- | ------------ | ------------------------------- |
| center-crosshair | draw     | `scripts/finished/draw/draw__center_crosshair__v01.lua` | stable       | Draws a center-screen crosshair |
| damage-logger    | game     | `scripts/finished/game/game__damage_logger__v01.lua`    | experimental | Needs runtime validation        |

`CATALOG.md` should be updated when a new finished script is added, renamed, archived, or promoted.

## Reference files

Detailed HApex3.0 Lua knowledge lives in:

```text
references/
├── api-reference.md
├── guide.md
└── examples.md
```

These files should be loaded only when needed.

| Task                                                                  | Read                                                |
| --------------------------------------------------------------------- | --------------------------------------------------- |
| Check API parameters, return values, fields, or module behavior       | `references/api-reference.md`                       |
| Find complete working script examples                                 | `references/examples.md`                            |
| Understand project layout, lifecycle, IPC, timing, or common pitfalls | `references/guide.md`                               |
| Generate or edit a Lua script                                         | `AGENTS.md` first, then the relevant reference file |

Do not copy the full API reference into README files.
Keep large reference material inside `references/`.

## Script factory directories

### `scripts/_workbench/`

Temporary working area.

Use this directory for:

* drafts created during a Codex task
* incomplete scripts
* one-off testing versions
* scripts that are not ready to become assets

A script should not stay in `_workbench/` permanently if it becomes useful.
Once a script is stable or worth keeping as an asset, move it to `scripts/finished/<category>/`.

### `scripts/_templates/`

Reusable script templates.

Use this directory for skeletons such as:

* basic frame update script
* GUI control script
* ESP element script
* notification script
* HTTP callback script
* config switching script

Templates are not finished assets.
They are starting points for future script generation.

### `scripts/finished/`

The finished script asset library.

Scripts in this directory are treated as reusable assets.

Finished scripts must be organized by their primary HApex3.0 Lua API module or dominant runtime purpose.

Required module category directories:

```text
scripts/finished/
├── event/
├── gui/
├── esp/
├── net/
├── game/
├── draw/
├── math/
├── file/
├── input/
├── log/
├── script/
├── time/
├── config/
├── json/
└── mixed/
```

### `scripts/archive/`

Human-readable archive of old, alternate, replaced, or deprecated scripts.

Archive is used because not all useful old scripts should be recovered only through Git history.

Use archive for:

* previous versions before major rewrites
* alternate requirement versions
* scripts that were replaced but may still be useful
* old scripts that can be used as reference material
* scripts that may be forked into a new version later

Recommended archive structure:

```text
scripts/archive/
└── 2026-06/
    └── center-crosshair/
        ├── 20260610-1430__before_gui_options_added__draw__center_crosshair__v01.lua
        └── NOTES.md
```

Each archived script should preserve enough context to understand why it was archived.

A small `NOTES.md` is recommended when the reason is not obvious.

## Finished script category rules

Place each finished script under the directory that best describes its primary purpose.

| Category  | Use when the script mainly focuses on                                            |
| --------- | -------------------------------------------------------------------------------- |
| `event/`  | event subscriptions, custom event bus, event-driven coordination                 |
| `gui/`    | menu controls, UI groups, user-facing controls, notifications                    |
| `esp/`    | ESP elements, labels, bars, entity overlays                                      |
| `net/`    | HTTP, WebSocket, async network communication                                     |
| `game/`   | reading player state, entity state, damage data, weapon state, runtime game data |
| `draw/`   | frame-based primitive drawing, screen overlays, watermark, crosshair             |
| `math/`   | vector logic, projection, easing, geometry helpers                               |
| `file/`   | sandboxed file I/O, image loading, local persistence                             |
| `input/`  | hotkey state, menu hotkeys, input formatting                                     |
| `log/`    | diagnostics, debugging output, logging-focused helpers                           |
| `script/` | script lifecycle, load/unload management                                         |
| `time/`   | frame count, timing cadence, time-based throttling                               |
| `config/` | plan switching, config reads/writes, weapon config helpers                       |
| `json/`   | JSON encode/decode utilities or JSON-heavy scripts                               |
| `mixed/`  | scripts where no single module dominates                                         |

If a script uses many modules, classify it by its user-visible purpose, not by every module it imports.

Examples:

| Script purpose                                               | Category  |
| ------------------------------------------------------------ | --------- |
| Center-screen crosshair using `draw.*`                       | `draw/`   |
| Loot ESP label using `esp.add(...)`                          | `esp/`    |
| Damage logger reading `game.entities.*` and writing logs     | `game/`   |
| Menu panel with buttons and notifications                    | `gui/`    |
| Remote version check using HTTP                              | `net/`    |
| Weapon parameter switcher using config paths                 | `config/` |
| Complex script combining GUI, draw, game, and config equally | `mixed/`  |

## Naming rules for script assets

Finished script filenames should use this pattern:

```text
<category>__<asset_name>__vNN.lua
```

Examples:

```text
draw__center_crosshair__v01.lua
esp__loot_marker__v01.lua
gui__quick_toggle_panel__v02.lua
game__damage_logger__v01.lua
config__weapon_profile_switcher__v03.lua
mixed__combat_overlay_panel__v01.lua
```

Rules:

* Use lowercase English filenames.
* Use `_` inside name parts.
* Use double underscore `__` between filename sections.
* Use `v01`, `v02`, `v03` for asset-level visible versions.
* Do not use spaces.
* Do not use vague names such as `test.lua`, `new.lua`, `final.lua`, or `fixed.lua`.

The category prefix should match the directory name.

Example:

```text
scripts/finished/draw/draw__center_crosshair__v01.lua
```

## Archive naming rules

Archived scripts should keep their original asset filename and add a timestamp plus reason.

Recommended pattern:

```text
YYYYMMDD-HHMM__reason__original_filename.lua
```

Example:

```text
20260610-1430__before_gui_options_added__draw__center_crosshair__v01.lua
```

Use short English reason names in filenames.
Put detailed explanations in `NOTES.md` when needed.

## Workflow for creating a new script

When Codex is asked to create a new HApex3.0 Lua script:

1. Read `AGENTS.md`.
2. Read the relevant files in `references/` only when needed.
3. Identify the script's primary category.
4. Create the script under `scripts/_workbench/` if it is exploratory.
5. Create the script directly under `scripts/finished/<category>/` if the requirement is clear and the output is intended as an asset.
6. Use the required filename pattern.
7. Add a Simplified Chinese file header.
8. Add only useful Simplified Chinese comments inside the script.
9. Update `CATALOG.md` when a new finished asset is created.
10. State what still requires runtime verification if the HApex3.0 environment is unavailable.

## Workflow for modifying an existing finished script

When modifying a script already under `scripts/finished/`:

1. Read the existing script.
2. Understand its current purpose and category.
3. Archive the previous version before major changes.
4. Modify the finished script in place if the asset identity remains the same.
5. Create a new asset file if the new requirement changes the purpose significantly.
6. Update `CATALOG.md`.
7. Mention the archive path in the change summary.

A major change includes:

* changing the main behavior
* changing the primary module category
* replacing the UI model
* changing config path behavior
* rewriting entity iteration logic
* replacing networking or timing logic
* changing a script from single-purpose to multi-purpose

Minor changes do not always require archive copies, but archiving is preferred when the old version may be useful as a future reference.

## Workflow for forking from an old script

When the user asks to create a new script based on an old one:

1. Search `scripts/finished/` and `scripts/archive/`.
2. Use the closest existing script as the base.
3. Create a new asset name if the new behavior is meaningfully different.
4. Do not overwrite the old script unless explicitly requested.
5. Update `CATALOG.md`.
6. Keep the old script available as a reference asset.

## Lua script comment language

Generated Lua script comments must use **Simplified Chinese by default**, unless the user explicitly requests another language.

This applies to:

* file header comments
* inline explanatory comments
* manual verification notes inside Lua files

Code identifiers, API names, module names, and runtime-required strings should stay in the language or format required by HApex3.0 Lua.

Recommended file header style:

```lua
-- 功能：在屏幕中心绘制一个可配置的准星提示。
-- 分类：draw
-- 使用 API：event、draw、gui、log。
-- 时序：draw.* 必须在 frame_update 中逐帧调用。
-- 验证：需要在 HApex3.0 实际运行环境中确认位置、颜色和缩放效果。
```

Internal comments should explain why, not obvious what.

Good:

```lua
-- 双机环境下不能读取玩家侧键盘，因此这里使用菜单热键状态。
```

Avoid:

```lua
-- 设置 x 为 10
local x = 10
```

## Lua script generation rules

When generating or editing `.lua` files, follow the complete rules in `AGENTS.md`.

Important summary:

* Do not invent undocumented HApex3.0 Lua APIs.
* Check `references/api-reference.md` when API details are needed.
* Check `references/examples.md` when a complete working pattern is needed.
* Check `references/guide.md` when lifecycle, timing, IPC, or project structure matters.
* Put `draw.*` calls inside `event.on("frame_update", function(e) ... end)`.
* Use colon calls for stateful object methods such as `net.http:get(...)`, `net.ws:connect(...)`, and `gui.notify:success(...)`.
* Use `pairs` when iterating `game.entities.players`, `game.entities.loots`, or `game.entities.projectiles`.
* Do not use `input.is_down(vk)` for player-side key state in dual-machine setups.
* Use `log.success("...")` after successful script registration instead of `print`.
* Use `gui.notify:info / :success / :warn / :error` for user-visible feedback.
* Do not add unnecessary unload cleanup for resources that HApex3.0 automatically releases.

## Asset status labels

Use these status labels in `CATALOG.md`:

| Status         | Meaning                                               |
| -------------- | ----------------------------------------------------- |
| `draft`        | Created but not reviewed                              |
| `experimental` | Useful but needs runtime testing or more validation   |
| `stable`       | Reviewed and intended for reuse                       |
| `archived`     | Old or replaced version kept for reference            |
| `deprecated`   | Should not be used for new work, but kept for history |

## Codex cloud usage

This repository is designed for Codex cloud.

Expected workflow:

```text
Private GitHub repository
        ↓
Codex cloud checks out the repository
        ↓
Codex reads AGENTS.md
        ↓
Codex reads README.md for asset workflow if needed
        ↓
Codex loads references/ on demand
        ↓
Codex creates, modifies, archives, or catalogs Lua scripts
        ↓
User reviews the diff or pull request
```

Codex cloud should not rely on local machine paths such as:

```text
~/.codex/hapex3-lua/
~/.codex/AGENTS.md
```

All required project context should be committed into this repository.

## Maintenance principles

* `README.md` is the native English repository overview.
* `README_CN.md` is the Simplified Chinese translation of `README.md`.
* `AGENTS.md` is the authoritative instruction file for AI coding behavior.
* `SKILL.md` is the Claude Code-compatible skill entry.
* `references/` stores large API references, guides, and examples.
* `scripts/_workbench/` stores temporary working files.
* `scripts/_templates/` stores reusable starting points.
* `scripts/finished/` stores reusable script assets.
* `scripts/archive/` stores old, alternate, or deprecated versions.
* `CATALOG.md` tracks important assets and their status.
* Do not commit secrets, account data, private machine paths, or personal configuration.
* If reference documentation conflicts with actual runtime behavior, document the discrepancy and prefer verified runtime behavior.

## Scope

This repository is intended for:

* continuously generating HApex3.0 / HOOZi Lua scripts
* modifying existing generated scripts
* maintaining a categorized script asset library
* archiving useful old script versions
* creating ESP, watermark, notification, hotkey hint, damage logger, config helper, network helper, or similar Lua scripts
* porting older scripts to the current HApex3.0 Lua API

This repository is not intended for:

* general HApex3.0 product usage questions
* unrelated generic Lua projects
* using Git history as the only script archive
* installing the original `hapex3-lua-skill.zip` package
