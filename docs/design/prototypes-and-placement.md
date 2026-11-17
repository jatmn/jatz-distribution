# Prototypes and placement

## Code

- `prototypes/constants.lua`: asset paths, `freighter_scale`.
- `prototypes/depots.lua`, `prototypes/orientation.lua`: depots, facing, loading zone marking.
- `scripts/loading-zone.lua`, `scripts/depot-road.lua`, `prototypes/roads.lua`: loading zone, depot road.
- `prototypes/freighter-art.lua`: the freighter's scale and boxes.
- `prototypes/placement.lua`: the crafting-menu row.

Prototypes load sprites straight from `assets/`; the mod never copies art. `prototypes/depot-definitions.lua` exists only because `depot-pictures.lua` requires that path.

## Depot orientation and the loading zone

Placed unrotated, every depot loads from the south, one tile beyond its 3x3 footprint. Item depots and the Fuel depot are turned half a turn from their artwork, ports included, so their opening faces south; liquid depots keep their pipes north. The loading zone marking is the depot's `integration_patch`, so it rotates with the depot.

Some decoratives draw on `floor` or `object`, above any ground layer, so `scripts/loading-zone.lua` clears decoratives from the loading zone whenever a depot is built by any means or turned, and on `on_init` and `on_configuration_changed`.

## Depot road

Every depot lays `jatz-depot-road` under its loading zone (`scripts/depot-road.lua`), so road a tile away connects. This hidden copy of `jatz-road` mines to nothing, so it can't be farmed; being its own tile marks it as the depot's. Laying and lifting it counts as road laid and removed ([roads and deliveries](roads-and-deliveries.md), [road tunnels](road-tunnels.md)).

- Nothing is laid over existing road, on water, on `out-of-map`, or on space platforms.
- When the depot goes or turns, the covered ground comes back, but only if its road is still there and no other depot loads from that tile. Depots sharing a tile share the road until the last goes.
- A tile placed, mined or set by a script over depot road gives the spot up for good; the road is laid again only when the depot is turned.
- Unowned depot road (from a cloned area) is adopted. A replaced depot passes its record on (`depot_road.replaced`).
- Old records migrate (`storage.depot_roads_version`).

## Freighter size

The freighter is drawn at 60% of the artwork's scale (the owner's choice). One scale serves the drivable and delivering freighters, so they match. The delivering freighter's collision box is a fixed 0.2 tiles each way so it fits a one-tile road. Change the size only via `constants.freighter_scale`, never in the artwork's helper (`assets/quinityn-freighter/factorio/freighter-animation.lua`), which keeps its own scale and checksum.

## The drivable freighter

The freighter item places a drivable car only with the `jatz-freighter-drivable` startup setting ("Place freighters as cars", off by default). Without it, `prototypes/freighter.lua` leaves the item without a `place_result` and hides the car. The car stays defined, so freighters placed while the setting was on survive and can still be driven and picked up.

## Crafting-menu row

The mod's row (subgroup `jatz-distribution`) sits directly above the vanilla `transport` row. `data-final-fixes.lua` runs `prototypes/placement.lua` after every other mod, which takes `transport`'s group and sorts ours just before it; without `transport`, the placeholder from `prototypes/item-groups.lua` stays.

Tests: `tests/lua/depot-road.lua`, `tests/lua/control-events.lua`, `tools/test_mod_setup.py`, the check mod.
