# Prototypes and placement

How the data stage uses the finished artwork, which way depots face when placed, the road each depot lays under its loading zone, the freighter's drawn size, and where the mod's row sits in the crafting menu.

## Code

- `prototypes/constants.lua`: asset paths, `freighter_scale`, `depot_road`.
- `prototypes/depot-definitions.lua`: points `prototypes.depot-definitions` at `assets/depots/factorio/depot-definitions.lua`.
- `prototypes/depots.lua`: the depot prototypes, using `assets/depots/factorio/depot-pictures.lua` and `depot-pipe-pictures.lua`.
- `prototypes/orientation.lua`: unrotated facing, port turning, the loading zone marking.
- `scripts/loading-zone.lua`: the loading zone tile, and clearing decoratives from it.
- `prototypes/roads.lua`, `scripts/depot-road.lua`: `jatz-depot-road` and who owns it.
- `prototypes/freighter-art.lua`: the freighter's drawn scale and boxes.
- `prototypes/item-groups.lua`, `prototypes/placement.lua`, `data-final-fixes.lua`: the crafting-menu row.

## Art comes from `assets/`

The prototypes load the sprite helpers and sheets straight from `assets/` (sheet paths in `prototypes/constants.lua`), so the mod never copies art.

`prototypes/depot-definitions.lua` exists only because `assets/depots/factorio/depot-pictures.lua` loads its data as `prototypes.depot-definitions`, the location its integration guide uses. It returns `assets/depots/factorio/depot-definitions.lua`.

## Depot orientation and the loading zone

Placed unrotated, every depot has its loading zone to the south, one tile beyond its 3x3 footprint (`orientation.loading_zone_shift`).

- Item depots (provider, request, buffer) and the Fuel depot load through an opening at the front. They are shown half a turn from their artwork (`orientation.half_turn`), with their pipe ports turned too (`orientation.ports`), so the opening faces south.
- Liquid depots keep their pipes to the north and load from the opposite, south side.
- Factorio then rotates pictures, ports and the loading zone together with the entity.

The loading zone marking is each depot's `integration_patch` (`prototypes/depots.lua`), so it rotates with the depot. It draws on `ground-patch-higher2` (`orientation.loading_zone_render_layer`): above decoratives such as plants and ground patches, below rails, belts, items, buildings and vehicles.

Some decoratives (medium and big sand rocks) draw on `floor` or `object`, which no ground layer can beat. So `scripts/loading-zone.lua` removes decoratives whose footprint overlaps the loading zone tile, as Factorio does under buildings (`loading_zone.clear`). It does this whenever a depot is built by any means (including cloned) or turned, and for every depot on `on_init` and `on_configuration_changed` (`loading_zone.clear_all`).

`tools/test_mod_setup.py` runs `prototypes/orientation.lua` on the real depot definitions with Lua 5.2 to check the layout (skipped where `lua5.2` isn't installed; the Mod CI job installs it).

## Depot road

Every depot lays `jatz-depot-road` under its loading zone sign when built (`scripts/depot-road.lua`), so road a tile away connects to it.

`jatz-depot-road` is a separate hidden tile (`prototypes/roads.lua`, a copy of `jatz-road`):

- It looks and drives like road: no off-road layer, the `jatz_road` layer, `transition_merges_with_tile = "jatz-road"`.
- It has no item, and mining it gives nothing, so it can't be farmed.
- Being its own tile is what marks road the depot owns.

### Ownership records

`storage.depot_roads[unit_number]` records each depot's road:

- `{ phase = "owned", surface, x, y, tile, hidden, double }`: the tile position, and exactly what it covered (tile, hidden tile and double-hidden tile).
- `{ phase = "released", reason }`: a player took the spot (`reason` is `"mined"` or `"covered"`). The road isn't laid again for that depot on load, only when it is turned.

Older saves' `false` records migrate to `released`, and older owned records gain `phase = "owned"` (`storage.depot_roads_version`).

### Rules

- Nothing is laid over existing road (`jatz-road`), on water, on `out-of-map`, or on space platforms.
- When the depot is removed by any means (`on_object_destroyed`) or turned, the covered ground comes back, but only if the depot's road is still there and no other depot loads from the same tile.
- Two depots loading from one tile share the road: the second copies the first's record exactly, a missing hidden tile included, and the road stays until the last of them goes.
- A tile placed over depot road by a player or robot (`on_*_built_tile`) gives the spot to whoever placed it, and their tile stays.
- Mining depot road (`on_*_mined_tile`) also gives the spot up, and puts back the covered ground, since mining alone would only reveal the hidden tile.
- Any other tile a script sets over a depot's road (`script_raised_set_tiles`) gives the spot up too.
- Depot road with no owner (from a cloned area) is adopted, with its hidden tile as the ground.
- A depot replaced in place (`scripts/legacy-depots.lua`) passes its record to the new entity (`depot_road.replaced`).
- Existing depots without a record get their road on `on_init` and `on_configuration_changed` (`depot_road.lay_all`).

Laying and lifting depot road counts as road laid and removed for deliveries and tunnels (`control.lua`'s `settle` passes the tile to `roads_changed`; see [roads and deliveries](roads-and-deliveries.md) and [road tunnels](road-tunnels.md)).

### Tests

- `tests/lua/depot-road.lua`: laying and restoring hidden tiles, turning, road or water already there, space platforms, sharing (records copied exactly, a missing hidden tile included), covering and mining by hand, adopting unowned road, saves from before depot road and record migration.
- `tests/lua/control-events.lua` loads the real `control.lua` and fires the game's events at its handlers (build, turn, flip, removal, and tiles placed, mined or set by players, robots and scripts), so a broken route fails.
- The check mod (`tests/factorio/jatz-distribution-check_0.1.0`) covers building (`depot_road_laid`, `depot_road_hides`, `road_kept_on_build`, `water_left`), removal (`concrete_restored`, `grass_restored`, `road_kept_on_removal`, `covered_kept`, `shared_kept`, `shared_restored`), and connection (`connected_by_depot_roads`).

## Freighter size

The freighter is drawn at 60% of the artwork's scale (the owner's choice). `constants.freighter_scale` is applied in `prototypes/freighter-art.lua` to both the drivable freighter (`prototypes/freighter.lua`) and the delivering one (`prototypes/freighter-drone.lua`), so they always match. `art.box` scales the drivable freighter's measured collision and selection boxes, and the delivering freighter's selection box. The delivering freighter's collision box is a fixed 0.2 tiles each way so it fits a one-tile road.

The artwork's helper (`assets/quinityn-freighter/factorio/freighter-animation.lua`) keeps its own scale (0.395) and its checksum (`assets/quinityn-freighter/checksums.json`). Change the size in the mod, never in the helper.

## The drivable freighter

The freighter item places a drivable car only with the `jatz-freighter-drivable` startup setting ("Place freighters as cars", off by default). Without it, `prototypes/freighter.lua` leaves the item without a `place_result` and hides the car. The car stays defined, so freighters placed while the setting was on survive and can still be driven and picked up.

## Crafting-menu row

The mod's crafting-menu and Factoriopedia row (item subgroup `jatz-distribution`) sits directly above the vanilla car and tank row (the `transport` subgroup).

- `prototypes/item-groups.lua` creates the subgroup with a placeholder group and order (`logistics`, `"f"`).
- `data-final-fixes.lua` runs `prototypes/placement.lua` after every other mod has loaded. It takes the `transport` subgroup's group and gives ours an order that sorts just before it (`just_before`: lower the last character, append `"~"`). Without a `transport` subgroup, the placeholder stays.

Item order within the row: provider, request, buffer, liquid provider, liquid request and liquid buffer depots, the Fuel depot (`b[depot]-<n>[role]`), the freighter (`c[freighter]`), road (`d[road]`), the road tunnel (`d[road]-b[tunnel]`), then the road network monitor (`e[road-monitor]`). With Space Age, the freighter's carbon recipe (`c[freighter]-b[carbon]`) follows the freighter.
