# Production Boost - Patch notes

## 1.1.0.3

- Description in GIANTS' ModHub layout (category, price, upkeep or hotkeys at the top).

## 1.1.0.2

- Updated for the current game version: modDesc descVersion 116 (the game build of 2026-10-27; GIANTS TestRunner 0.9.24 accepts only 116).

## 1.1.0.1
- Meets the GIANTS ModHub checks (TestRunner): textures, icon and modDesc brought up to date.
- Errors are no longer hidden: they show in the log.

## 1.1.0.0 (2026-11-14) - Storage boost
- Storage capacities (incoming and outgoing) are multiplied by the boost too. All lines of a production share one
  storage, so it uses the highest boost set on any of its lines (one line at 5x, the rest 1x = 5x storage).
- Lowering the boost leaves stock above the new capacity in place; nothing is deleted, it just can't be filled further.
- Saved boosts are put back before the storage loads, so boosted stock is not cut back on loading.
- Untested.

## 1.0.0.0 (2026-11-13) - First version
- New "PRODUCTION LINE BOOST %" tick boxes in the Production Chains menu, between PRODUCTION and RECIPE: 1x, 2x, 5x, 10x.
- Every product (production line) has its own setting. Works on every production: base game, maps and mods.
- 2x / 5x / 10x multiplies cycles per month and costs per month. The recipe per cycle stays the same, so materials used
  and product made per month go up by the same amount. Example: Paper Factory carton roll at 10x = 240 cycles and
  $1,200 a month instead of 24 cycles and $120.
- Multiplayer: only the farm manager can change it; other players see it greyed out.
- Saved with the savegame (`productionBoost.xml` in the savegame folder). Lines not saved start at 1x.
- Mouse only for now (click a box).
- Works alongside Factory Profit Calculator: if it (or another mod) sets a line's speed, the boost is put back on top
  of the new value within 2 seconds.
- Icon with the DTM Mods badge (shine version) above "PRODUCTION BOOST".
- Untested.
