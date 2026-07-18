# Script Catalog

| Asset | Category | Path | Status | Notes |
| --- | --- | --- | --- | --- |
| web-radar | net | `scripts/finished/net/web_radar.lua` | stable | User-provided production script imported byte-for-byte unchanged; protocol and lifecycle behavior covered by a mocked regression test. |
| low-level-blacklist | game | `scripts/finished/game/game__low_level_blacklist__v01.lua` | experimental | Adds non-NPC players below grade 500 to `conf/rosters.json`; preserves before/after/add audit files and rolls back incomplete transactions. |
