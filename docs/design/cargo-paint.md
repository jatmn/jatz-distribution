# Cargo paint

A delivering freighter's cargo layer (the artwork's `mask-cargo`) is light grey while empty and takes its load's color from loading until its trip ends, like a chemical plant's tank or a pipe window (the owner's request, November 4, 2026).

Units have no per-entity color in 2.1 (`LuaEntity::color` covers characters, rolling stock, cars, spider vehicles and a few others). So every paint is its own unit prototype, and loading swaps the freighter for the unit in its cargo's paint.

## Code

- `scripts/freighter-paint.lua`: the palette and prototype names, shared by the data stage and the runtime (`paint.names`, `paint.is_drone`, `paint.drone_for`, `paint.drone_for_cargo`).
- `prototypes/freighter-drone.lua`: one unit prototype per paint, all drawing the same sprite sheets.
- `prototypes/freighter-colors.lua`, run from `data-final-fixes.lua`: each item's and fluid's paint.
- `scripts/logistics.lua`: `paint_of`, `repaint`, `check_trip` and `repaint_now`.
- `scripts/trip-state.lua`: `rebind`, which moves a trip to its new unit (see [Runtime state](../runtime-state.md)).

## The palette

| Prototype | Paint |
| --- | --- |
| `jatz-freighter-drone` | Empty: light grey. The original name, so older saves keep their freighters |
| `jatz-freighter-drone-loaded` | The artwork's slate blue, for cargo with no color |
| `jatz-freighter-drone-RGB` (216) | Each digit a channel in steps of 0.2 (0 to 5) |
| `jatz-freighter-drone-underground` | Unseen, while going through a road tunnel (see [Road tunnels](road-tunnels.md)) |

The palette is fixed, never derived from the installed mods, so a mod change can't remove a prototype a freighter on the road is using.

## Colors from data

`prototypes/freighter-colors.lua` works out each item's and fluid's paint and stores the drone names in the mod-data prototype `jatz-freighter-colors` (`{ items = { [item] = drone }, fluids = { [fluid] = drone } }`). `paint.drone_for_cargo` reads it once; anything not listed gets the slate blue.

A fluid's paint is its `base_color`. An item's color is the first of:

1. **The color its mod declares**: a mod-data prototype with `data_type = "item-colors"` and `data = { items = { [item] = Color } }`. Prototypes are read by name, and the first to name an item wins. This lets a mod color by-products no recipe makes, such as Yuoki's slag, and items whose recipes mislead (the owner's request, November 6, 2026). Yuoki declares colors read from its icons.
2. **Its entry in `colors.own`**: base game ores and plates, whose recipes overhauls such as Angel's remake, and vanilla and Space Age items no rule colors, such as circuits and wood.
3. **The `map_color` of the resource it is mined from**, with `results` winning over `result`, as in the engine.
4. **The fluid it holds**: a barrel, which a recipe empties into the fluid and the container.
5. **The first recipe making it that gives a color**: recipes named after the item first, then by name. Recycling recipes don't count, and a recipe with several products counts only for its `main_product`. A recipe gives, in order:
   - its `crafting_machine_tint.primary`;
   - its one item ingredient's color;
   - its one fluid ingredient's color, if it has no item ingredients;
   - its main item ingredient's color: a mined one first, then the largest amount, then the first listed.

It must work from data alone for overhaul mods (the owner pairs the mod with Bob's, Angel's and Krastorio 2). Measured with Bob's and Angel's `dev2.1` branches, about 9 in 10 non-placeable items get a color. Buildings matter less (the owner, November 4, 2026).

Icon layer tints were tried and dropped: Angel's tints are mostly tier-number badges, and they colored only 4 more items.

Engine fact: 2.1 recipes have `categories`, not `category`.

## Repainting

When a freighter loads (`arrived_at_provider`), `repaint` swaps it for the drone in its cargo's paint (`paint_of`):

- The new unit is created where the old one stands, facing the same way (made with its nearest of the 16 directions, then set exactly), with the same health, quality and speed.
- `lifecycle.rebind` moves the trip to the new `unit_number` in `storage.trips` and the depot's `trips`.
- The old unit is destroyed; its `on_object_destroyed` finds no trip.
- `show_cargo` draws the alt-mode cargo icon again on the new unit (see [Roads and deliveries](roads-and-deliveries.md)).

Rules:

- **Only swap between commands.** The new unit has none until `drive`.
- **Never swap a freighter with anything stuck to it** (fire, acid, slowdown). A sticker is its own entity, stuck to that unit for good (`sticked_to` is read-only). One made anew on another unit keeps its remaining `time_to_live` but restarts its `damage_interval` cycle, adding or skipping a hit (Pullfrog's review of `14c2d32`). 2.1 exposes no way to carry that over.

Such a freighter keeps its old paint. Its once-a-second check (`check_trip`, then `repaint_now`) paints any freighter whose paint doesn't match its cargo once nothing is stuck to it and it isn't standing to load or unload, then drives it on (`drive(trip, target(trip))`). Painting changes trip ids, so `repaint_now` runs after the loop over trips.

Everything that finds or filters freighters uses `logistics.drones` (`paint.names()`) or `paint.is_drone`, never the one name: clone filters, `add_all`, impact checks, the check mod's `DRONES`.

## Tests

- `tests/lua/freighter-colors.lua` covers the color rules on a small fake of `data.raw`.
- `tests/lua/logistics.lua` covers the swap: empty paint out, the item's paint after loading, a new unit in the old one's place and facing, the same trip.
- The check mod requires the connected pair's freighter to arrive at the provider empty and leave in iron plates' paint. A separate pair's freighter gets a fire-like sticker on arrival (its own `jatz-check-sticker` in the check mod's `data.lua`, hitting every 10 ticks); it must load unswapped with the same sticker still stuck to it, then take iron plates' paint on the road home once the sticker has worn off.
