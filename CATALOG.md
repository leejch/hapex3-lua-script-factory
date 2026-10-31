# Script Catalog

| Asset | Category | Path | Status | Notes |
| --- | --- | --- | --- | --- |
| distance-switch | config | `scripts/finished/config/config__distance_switch__v01.lua` | experimental | Standalone distance-only variant derived from commit `67f44d2`, without debug drawing. Selects the on-screen enemy with the smallest view angle and switches at 50/100/200 meters. Mock boundary and selection regression tests included. |
| scope-switch | config | `scripts/finished/config/config__scope_switch__v01.lua` | experimental | Standalone optic variant derived from commit `bf1292b`, without debug drawing or enemy dependency. ADS FOV thresholds select 1x/2x/3x/4x/6x/8x/10x plans; hip fire selects 1x. Mock boundary and failure regression tests included. |
| distance-scope-switch | config | `scripts/finished/config/config__distance_scope_switch__v01.lua` | experimental | Standalone combined variant with 28 distance/optic plans. Evaluates ADS state, then nearest-angle enemy distance, then ADS FOV; hip fire selects the distance-specific 1x plan. No debug drawing; all 28 combinations and boundary cases covered by mocked regression tests. |
| spectator-switch | config | `scripts/finished/config/config__spectator_switch__v02.lua` | stable | Production version using the local platform UID with self_base/index fallbacks, decoding runtime `spec_index` handles, and switching exact 0/1/2/3+ spectator ranges without drawing a diagnostic ESP; mock regression test included. |
| spectator-switch-debug | config | `scripts/finished/config/config__spectator_switch__v01.lua` | experimental | Diagnostic version with the earlier editable range table and centered free-ESP output showing raw/decoded `spec_index` values and switch state; mock regression test included. |
| web-radar | net | `scripts/finished/net/web_radar.lua` | stable | User-provided production script imported byte-for-byte unchanged; protocol and lifecycle behavior covered by a mocked regression test. |
| ads-fov-declutter | esp | `scripts/finished/esp/esp__ads_fov_declutter__v01.lua` | experimental | External finished script with executable behavior preserved; suppresses enemy name/rank/level inside the computed ADS FOV cone and draws an independent custom skeleton. Repository-style comments and a mock regression test were added; real HApex3.0 visual runtime confirmation remains open. |
| low-level-blacklist | game | `scripts/finished/game/game__low_level_blacklist__v01.lua` | experimental | Applies team-aware grade 500/1000 rules after fail-closed local UID/team identity filtering, with UID range filtering, 4-space JSON, delayed reads, and transactional backups. |
| ads-hide-loot-models | draw | `scripts/finished/draw/draw__ads_hide_loot_models__v01.lua` | experimental | While ADS is active, temporarily disables boolean controls under the loot menu tree so ground-loot and entity-model drawing are reliably suppressed; all player visuals remain untouched. Restores original values on release or unload. Mock regression test passes. |
| enemy-aim-warning-screen-only-v01 | draw | `scripts/finished/draw/draw__enemy_aim_warning__screen_only__v01.lua` | stable | Snapshot of commit `7d79a24`; displays the 2px red warning line only for in-screen enemies after 800ms of continuous aiming and hides it immediately when aim stops. Mock regression test included. |
| enemy-aim-warning-full-range-v01 | draw | `scripts/finished/draw/draw__enemy_aim_warning__v01.lua` | stable | Snapshot of commit `7d79a24`; displays the 2px red warning line for in-screen enemies and the corresponding screen-edge line for off-screen enemies after 800ms of continuous aiming. Mock regression test included. |
| enemy-aim-warning-screen-only-v02 | draw | `scripts/finished/draw/draw__enemy_aim_warning__screen_only__v02.lua` | stable | Current screen-only product; displays the 2px bright-pink warning line only for in-screen enemies after 800ms of continuous aiming and hides it immediately when aim stops. Mock regression test included. |
| enemy-aim-warning-full-range-v02 | draw | `scripts/finished/draw/draw__enemy_aim_warning__v02.lua` | stable | Current full-range product; keeps the 2px bright-pink warning line for in-screen enemies and shows light-yellow, black-outlined warning text for off-screen enemies after 800ms of continuous aiming, keeping it visible until 2s of continuous loss of aim. Mock regression test included. |

## 修改记录：距离与倍镜切参调试字段（2026-10-31）

删除旧调试脚本 `scripts/finished/config/config__crosshair_distance_switch__v01.lua` 及其专用测试。现由上表的 `distance-switch`、`scope-switch`、`distance-scope-switch` 三个 v01 成品分别承担距离、倍镜及组合切参功能，均不绘制调试文字。三者每次仅启用一个，并在其所有目标配置中启用对应脚本。

旧调试实现可从提交 `67f44d2108f6111e9fdaf57f42f08ef06f03f7ff`（目标距离、名称）和 `bf1292b7bdf1d88e189670f9230025903eead341`（追加倍镜诊断）追溯。原文字起点为屏幕宽度的 85%、高度的 25%，第一行是目标距离，第二行是玩家名，后续每行一个诊断字段。为便于今后恢复调试，在此保留字段对应关系。

### 目标与本人武器字段

| 原显示内容 | API 字段 | 用途与解释 |
| --- | --- | --- |
| `xx m` | 选中敌人的 `player.distance` | 单位为米；原显示四舍五入至整数，切参使用未取整的原值。先按准星夹角选敌，再读取其距离，不是选择物理距离最近的敌人。 |
| 玩家名 | 同一敌人的 `player.name` | 用于确认画面显示与切参所依据的敌人为同一人；空名称显示“未知玩家”。 |
| `ADS` | `game.localplayer.is_zooming` | 本人是否开镜。`false` 优先使用一倍档，不依赖 FOV；组合版仍需有效敌人来确定距离档。 |
| `target_zoom_fov` | `game.localplayer.target_zoom_fov` | 本人当前武器的开镜视野角原值，不是直接倍率。根据下方用户实测区间映射倍率；不读取敌人的开镜状态或倍镜。 |
| `weapon` | `game.localplayer.weapon` | 本人当前武器名称，用于对照切枪。 |
| `weapon_enum` | `game.localplayer.weapon_enum` | 当前武器类型编号，用于与武器列表对照；相同武器双持时不能单凭类型编号唯一确定槽位。 |
| `weapon_fields_stale` | `game.localplayer.weapon_fields_stale` | `true` 表示切枪后武器字段仍可能是上一把武器的数据；成品在开镜时暂缓倍率切参，收镜仍使用一倍档。 |

### 两把主武器的已装备倍镜字段

原调试每帧读取一次 `local weapons = game.localplayer.weapons`，遍历两把武器，以 `weapon.slot` 显示 `S1` / `S2` 前缀。配件来自 `weapon.mods`，仅显示 `mod.group == "optic" and mod.equipped == true` 的记录，避免把可安装但未装备的倍镜误认为当前倍镜。

| 原显示后缀 | API 字段 | 用途与解释 |
| --- | --- | --- |
| `name` | `weapon.name` | 该槽位的武器名称。 |
| `enum` | `weapon.weapon_enum` | 该槽位的武器类型编号。 |
| `mods_read` | `weapon.mods_read` | 配件表是否已读到；切枪后可能暂时为 `false`，此时配件表为空。 |
| `mods_cached` | `weapon.mods_cached` | `true` 表示使用缓存配件数据，不能据此保证配件为当前实时状态。 |
| `optic.item` | `mod.item` | 已识别倍镜的物品标识。 |
| `optic.label` | `mod.item_name` | 已识别倍镜的名称。 |
| `optic.raw` | `mod.name` | 游戏中的原始配件名称，用于对照未识别或命名不同的倍镜。 |

旧调试中，字段缺失或空字符串显示 `N/A`，数值诊断保留两位小数；`target_zoom_fov` 的显示精度不用于区间判断。没有已装备倍镜记录时显示“无已装备记录”，不能直接当作裸镜或一倍镜，需结合配件读取及缓存状态判断。配件名称可用于辨认倍镜类型，但不作为可变倍镜当前档位的判断依据；成品使用 `target_zoom_fov` 实测区间。

### 用户实测倍率映射

当 `ADS == true` 且武器字段非旧值时，使用以下左闭右开区间；边界值归属于包含该下界的档位。

| `target_zoom_fov` 原值区间 | 倍率档 | 倍镜版配置 |
| --- | --- | --- |
| `[46.4, +∞)` | `1x` | `config_1x` |
| `[32.14, 46.4)` | `2x` | `config_2x` |
| `[22.95, 32.14)` | `3x` | `config_3x` |
| `[16.42, 22.95)` | `4x` | `config_4x` |
| `[11.59, 16.42)` | `6x` | `config_6x` |
| `[8.98, 11.59)` | `8x` | `config_8x` |
| `[2, 8.98)` | `10x` | `config_10x` |

`ADS == false` 时，倍镜版使用 `config_1x`，组合版使用 `config_<距离档>_1x`。组合版判断顺序为 ADS 状态 → 距离 → 倍率；距离档为 `[0,50)` → `0_50`、`[50,100)` → `50_100`、`[100,200)` → `100_200`、`[200,+∞)` → `200_inf`，组合方案命名为 `config_<距离档>_<倍率档>`，共 28 种。

开镜时 FOV 小于 2、缺失、非数值或非有限值，均保持当前配置；不在对局、本人死亡或倒地时暂停自动切参。距离版和组合版无有效目标时保持当前配置；倍镜版不依赖敌人。目标筛选沿用原调试脚本：屏幕内、非队友、非本人、未死亡且未倒地；按摄像机视线至敌人实体原点的三维夹角排序，夹角相同时优先更近者。

现有回归测试 `tests/config__auto_switch_variants__v01_test.lua` 覆盖三个成品的距离与 FOV 边界、全部 28 种组合、优先级以及缺失配置和失败重试行为。
