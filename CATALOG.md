# Script Catalog

| Asset | Category | Path | Status | Notes |
| --- | --- | --- | --- | --- |
| web-radar | net | `scripts/finished/net/web_radar.lua` | stable | User-provided production script imported byte-for-byte unchanged; protocol and lifecycle behavior covered by a mocked regression test. |
| low-level-blacklist | game | `scripts/finished/game/game__low_level_blacklist__v01.lua` | experimental | Applies team-aware grade 500/1000 rules after fail-closed local UID/team identity filtering, with UID range filtering, 4-space JSON, delayed reads, and transactional backups. |
| ads-skeleton-only | draw | `scripts/finished/draw/draw__ads_skeleton_only__v01.lua` | experimental | While ADS is active, preserves native skeleton styling, minimap, and offscreen indicators; suppresses other player, loot, model, and registered ESP elements; restores original state on release or unload. Mock regression test passes; live menu-tree coverage still needs HApex3.0 runtime verification. |
