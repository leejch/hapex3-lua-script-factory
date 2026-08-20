# Script Catalog

| Asset | Category | Path | Status | Notes |
| --- | --- | --- | --- | --- |
| web-radar | net | `scripts/finished/net/web_radar.lua` | stable | User-provided production script imported byte-for-byte unchanged; protocol and lifecycle behavior covered by a mocked regression test. |
| low-level-blacklist | game | `scripts/finished/game/game__low_level_blacklist__v01.lua` | experimental | Applies team-aware grade 500/1000 rules after fail-closed local UID/team identity filtering, with UID range filtering, 4-space JSON, delayed reads, and transactional backups. |
| ads-hide-loot-models | draw | `scripts/finished/draw/draw__ads_hide_loot_models__v01.lua` | experimental | While ADS is active, temporarily disables boolean controls under the loot menu tree so ground-loot and entity-model drawing are reliably suppressed; all player visuals remain untouched. Restores original values on release or unload. Mock regression test passes. |
| enemy-aim-warning-screen-only | draw | `scripts/finished/draw/draw__enemy_aim_warning__screen_only__v01.lua` | stable | Screen-only product based on commit `7877458`; displays the 2px bright-pink warning line only for in-screen enemies after 800ms of continuous aiming and hides it immediately when aim stops. Mock regression test included. |
| enemy-aim-warning-full-range | draw | `scripts/finished/draw/draw__enemy_aim_warning__v01.lua` | stable | Full-range product based on commit `229e9f0`; keeps the 2px bright-pink warning line for in-screen enemies and shows a light-yellow, black-outlined warning text at the configured screen position for off-screen enemies after 800ms of continuous aiming. Mock regression test included. |
