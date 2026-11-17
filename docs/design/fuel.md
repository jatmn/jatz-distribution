# Fuel

Freighters carry their own fuel, burn it by the tile, and fill up by themselves at Fuel depots. Nothing delivers fuel to request depots. Freighters only ever take fuel from Fuel depots: fuel in any other depot is cargo.

## Code

- `scripts/fuel.lua`: tanks, what burns, filling up, the Fuel depot search, the leg check.
- `scripts/logistics.lua`: `burn`, `set_off`, `parked_fuel`, the dry crawl, the hidden tank (`fuel_tank`), the remote interface.
- `scripts/request-gui.lua`: the fuel line and the Fuel depot's flush button.
- Tests: `tests/lua/logistics.lua`; the check mod (`tools/test_mod.py`).

## Tank and burning

- A normal tank holds `jatz-freighter-fuel-capacity` MJ (20); driving burns `jatz-freighter-fuel-per-tile` kJ a tile (10), so a full tank lasts 2,000 tiles. 0 per tile turns fuel off. Better freighters have bigger tanks ([Quality](quality.md)).
- `burn` takes the straight-line distance since the last sample, so checks must be exactly a second apart ([Spreading the work](spreading-the-work.md#trips-one-tick-each)). A tunnel is burned on entry and exit, never as a jump between mouths.

## What burns

Fuel comes from game data, never a list: any item or fluid with `fuel_value > 0`. The base game has no such fluid, so `data-final-fixes.lua` gives petroleum gas 400 kJ a unit, unless another mod has given it one.

## Parked freighters keep their fuel

`depot.fuel` (and `depot.graded_fuel[quality]`) lists the slot's freighters whose tank is not exactly full; the rest are full. `parked_fuel` trims each list when freighters are taken out, so freighters put in come full. Items go in whole, so an item worth more than a tank overfills it, and the freighter keeps that.

## Before each leg

Every leg goes through `set_off`. A tank short of the leg (`FUEL_MARGIN`, plus `FUEL_RESERVE`) searches by road for the nearest Fuel depot with fuel, fills up there, and drives on; the check runs once a leg (`trip.fuel_check`). Filling takes burnable fluid first, then whole items; an item with a `burnt_result` is taken only as far as the depot has room for the result.

## When there is no fuel

- No Fuel depot with fuel reachable: the freighter goes on with what it has (`go_without_fuel`).
- Exception: a freighter still at home that can't reach the provider goes back into the slot, never sent to wait at an empty Fuel depot. Its depot waits with status `no-fuel` (road reaches only empty Fuel depots) or `no-fuel-depot` (none). A freighter at home also searches empty Fuel depots to tell the two apart.

## Running dry

A dry tank (`trip.dry`) slows the unit to `DRY_SPEED` (`LuaEntity::speed`, writable for units in 2.1) and it looks for fuel or crawls on, so a freighter is never stranded.

## Showing fuel

A freighter out shows its fuel on hover (`LuaEntity::custom_status`), written only on change (`trip.fuel_shown`).

## The Fuel depot

- A container for fuel items, with a hidden storage tank under it for liquid fuel, since no entity type has both an item inventory and a fluid box.
- `fuel_tank` keeps the tank's `direction` and `mirroring` the depot's on every change and at each check, since scripts can turn entities without an event. The tank goes with its depot.
- Cloning keeps the liquid: a cloned tank is adopted by its cloned depot, a depot cloned alone gets the fluid, and a tank cloned alone is destroyed.
- The flush button uses `clear_fluid_inside`, which empties connected pipes too, as a vanilla flush does.
