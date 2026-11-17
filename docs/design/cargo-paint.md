# Cargo paint

A loaded freighter's cargo layer takes its load's color until its trip ends; empty, it is light grey (the owner's request, November 4, 2026). Units have no per-entity color in 2.1, so each paint is its own unit prototype and loading swaps the freighter for one.

## Code

- `scripts/freighter-paint.lua`: palette and names (`paint.names`, `paint.is_drone`, `paint.drone_for_cargo`).
- `prototypes/freighter-drone.lua`: one unit per paint.
- `prototypes/freighter-colors.lua` (from `data-final-fixes.lua`): each item's and fluid's paint, in mod data `jatz-freighter-colors`.
- `scripts/logistics.lua`: `paint_of`, `repaint`, `check_trip`, `repaint_now`; `scripts/trip-state.lua`: `rebind` ([Runtime state](../runtime-state.md)).

## Palette

`jatz-freighter-drone` (empty) keeps the original name for old saves. `-loaded` is slate blue for cargo with no color, 216 `-RGB` paints step each channel by 0.2, and `-underground` is unseen in [road tunnels](road-tunnels.md). The palette is fixed, never derived from installed mods, so a mod change can't remove a prototype a freighter on the road uses.

## Colors from data

A fluid's paint is its `base_color`. An item's is the first of: a color a mod declares ([item-colors mod data](../../README.md#for-mod-authors-cargo-colors); the owner's request, November 6, 2026), `colors.own`, its ore's `map_color`, a barrel's fluid, then its first coloring recipe (not recycling; only for its `main_product`).

It must work from data alone for overhauls (Bob's, Angel's, Krastorio 2). Buildings matter less (the owner, November 4, 2026). Icon tints were tried and dropped. Engine fact: 2.1 recipes have `categories`, not `category`.

## Repainting

On loading, `repaint` creates the new unit in place with the same facing, health, quality and speed, `rebind`s the trip, and destroys the old one.

- Only swap between commands.
- Never swap a freighter with a sticker on it: `sticked_to` is read-only, and a remade sticker restarts its `damage_interval`, which 2.1 can't carry over. It keeps its old paint until `check_trip` / `repaint_now` paints it once nothing is stuck and it isn't loading or unloading. `repaint_now` runs after the loop over trips, since painting changes trip ids.
- Find or filter freighters with `logistics.drones` (`paint.names()`) or `paint.is_drone`, never one name.

## Tests

`tests/lua/freighter-colors.lua`, `tests/lua/logistics.lua`, and the check mod's paint and sticker pairs.
