# Fuel

Freighters carry their own fuel, burn it by the tile as they drive, and fill up by themselves at Fuel depots.
Unlike Transport Drones, nothing delivers fuel to request depots.
Freighters only ever take fuel from Fuel depots: fuel in any other depot is cargo.

## Code

- `scripts/fuel.lua`: tank size, what burns, filling up, the hover status, finding a Fuel depot or going without, and the leg check.
- `scripts/logistics.lua`: burning (`burn`), the leg start (`set_off`), parked fuel (`parked_fuel`), the dry crawl, the hidden tank (`fuel_tank`), the end of a Fuel depot search (`finish_search`), and the remote interface.
- `scripts/request-gui.lua`: the fuel line under a requesting depot's freighter slot; the Fuel depot's liquid fuel and flush button.
- `prototypes/depots.lua`: the Fuel depot and its hidden tank. `data-final-fixes.lua`: petroleum gas as fuel.
- `settings.lua`: `jatz-freighter-fuel-capacity`, `jatz-freighter-fuel-per-tile` (runtime-global); `jatz-fuel-depot-slots`, `jatz-fuel-depot-capacity` (startup).

## Tank and burning

- Fuel is energy in joules (`trip.energy`).
- A normal tank holds `jatz-freighter-fuel-capacity` MJ (default 20). Driving burns `jatz-freighter-fuel-per-tile` kJ a tile (default 10), so a normal full tank lasts 2,000 tiles, Transport Drones' default per drone. 0 per tile turns fuel off.
- A better freighter's tank holds more (`fueling.tank_of`; see [Quality](quality.md)).
- `burn` takes the straight-line distance driven since the last sample (`trip.at`). It runs at each once-a-second check (`check_trip`), when a leg starts (`drive`, `set_off`) and when a trip ends (`end_trip`). Why the checks must be exactly a second apart is in [Spreading the work](spreading-the-work.md#trips-one-tick-each).
- Through a tunnel, the way to the mouth is burned on entry (`into_tunnel`) and the tunnel's length on exit (`through_tunnel`), so the jump between mouths is never measured as a straight line.

## What burns

Fuel comes from game data, never a list: any item with `fuel_value > 0` (any fuel category, any mod), and any fluid with `fuel_value > 0`. The base game has no such fluid, so `data-final-fixes.lua` gives petroleum gas 400 kJ a unit (a normal full tank is 50 units, Transport Drones' fuel per drone), unless another mod has given it a fuel value.

## Parked freighters keep their fuel

- New freighters come with a full tank.
- `depot.fuel` lists the energies of a slot's normal freighters whose tank is not exactly full (less, or more), lowest first. Freighters without an entry are full. Better freighters have their own lists (`depot.graded_fuel[quality]`).
- Freighters taken out of the slot take the full ones first, then the fullest entries: `parked_fuel` trims each list to its quality's count in the slot, at once in `take_freighters` and `remove_freighters`, so freighters put in afterwards come full.
- `start_trip` sends the best freighter (`logistics.next_freighter`, see [Quality](quality.md)) and, of its quality, the one with the most fuel.
- Items go in whole (`refuel` rounds up), so an item worth more than a tank (some mods' items hold 10 GJ) fills a freighter past its capacity, and it keeps that.

## Before each leg

Every leg (setting off from home, leaving the provider, heading for a new provider after a reroute, going home) goes through `set_off`:

1. `short_of_fuel`: the tank is short if it holds less than the leg's road length times `FUEL_MARGIN` (1.25), plus `FUEL_RESERVE` (0.1) of a full tank, capped at a full tank. The leg's length is `trip.leg` (the search's `best_length`); the way home is taken as the longer of the way out and the straight line.
2. Short, it stands while a search finds the Fuel depot nearest by road (`look_for_fuel`, `seek_fuel`: the same token-owned `request_path` search as for providers, with `search.fuel` set).
3. It drives there (`trip.refuel`; `target` returns it), stands `LOADING_TICKS`, fills up (`arrived_at_fuel`, `refuel`) and drives on to its target.
4. `trip.fuel_check` becomes `checked` after filling up or deciding to go without, so the check runs once a leg.

Fuel depot candidates (`fuel_candidates`): same surface and force, road at the loading zone, not on the request depot's cooldown, and holding fuel (`has_fuel`: a burnable fluid, or a burnable item; one with a `burnt_result` only while the chest has room for that result). Nearest first in a straight line.

Filling up (`refuel`): burnable fluid first, then items a whole item at a time. The last item may overfill the tank, as a burner holds the item it is burning. An item with a `burnt_result` leaves it in the depot, and is taken only as far as there is room for it.

## When there is no fuel

- The Fuel depot found was emptied or removed during the search: it looks again among the rest.
- No Fuel depot (none with fuel, none reachable): it goes on to its target on what it has (`go_without_fuel`). `target` falls back to where the trip was last heading (`trip.destination`, set to the provider's zone by `start_trip`) if that depot is gone.
- Exception: a freighter still at home (`trip.movement == "departing"`) that can't reach the provider on what it has goes back into the slot, never sent to wait at an empty Fuel depot. Its depot waits `RETRY_TICKS` (10 s) with `retry_status`:
  - `no-fuel` (yellow) when its road reaches Fuel depots, but none with fuel;
  - `no-fuel-depot` (red) when its road reaches no Fuel depot.
- To tell the two apart, a freighter at home also searches empty Fuel depots, ranked after those with fuel (`fuel_candidates(..., empty)`, rank 1).
- `dispatch` ends either wait early once `fuel_candidates` finds a Fuel depot with fuel. Building or turning a depot, or laying road, ends it too (`retry_now`).
- A road failure to a Fuel depot puts it on the request depot's cooldown and looks again (`fuel_route_failed`).
- A removed Fuel depot sends the freighters heading for it to look again.
- A reroute drops a pending fuel detour; `set_off` decides afresh for the new leg.
- Timeouts and restarts repeat whichever search a trip had (`search_again`).

## Running dry

A tank that runs dry sets `trip.dry` and slows the unit to `DRY_SPEED` (0.1) of its speed (`LuaEntity::speed`, writable for units in 2.1). If it isn't already searching, standing or heading for fuel, it looks for a Fuel depot, or crawls on to its target, so a freighter is never stranded. Repainting, research and lost qualities keep the crawl. It ends when filling up leaves fuel in the tank, or when fuel is turned off.

## Showing fuel

- A freighter out shows its fuel on hover as its status (`show_fuel`: `LuaEntity::custom_status`, a dot and `jatz-gui.freighter-fuel` with the amount and the full tank, in MJ, or GJ from 1,000 MJ). The dot is green, yellow below `LOW_FUEL` (a quarter) of a tank, red when dry. Nothing shows while fuel is off.
- It is set when the freighter sets off, at its once-a-second check, after filling up, after a repaint and out of a tunnel. It is written only when what it shows changes (`trip.fuel_shown`).
- A requesting depot's panel shows its slot's fuel under the freighter slot (`freighter_fuel` label: how many are full, and the lowest). The tooltip lists every freighter's fuel, home and out, with each size of full tank its freighters have. The label is hidden while fuel is off.

## The Fuel depot

- `jatz-fuel-depot`, role `fuel` in `logistics.depots`, takes no part in deliveries.
- A container (`jatz-fuel-depot-slots`, 48 slots by default), so fuel items go in by hand, inserter or robot.
- A hidden storage tank under it holds liquid fuel (`jatz-fuel-depot-tank`, `jatz-fuel-depot-capacity`, 25,000 by default), since no entity type has both an item inventory and a fluid box of its own. The tank draws only its pipe port and connectors; it is not selectable, minable or blueprintable, and collides with nothing. It takes the depot's quality, so a better depot holds more fuel (see [Quality](quality.md)).
- `fuel_tank(entity)` makes the tank (`logistics.add`, `add_all`, on demand). It keeps the tank's `direction` and `mirroring` the depot's on every build, turn and flip (`on_depot_changed`), and at the depot's once-a-second check, since scripts can turn entities without an event.
- The tank goes with its depot (`on_object_destroyed`, or the depot's check if that finds the depot gone first).
- Cloning keeps the liquid: a tank cloned with its depot is adopted by the cloned depot (`fuel_tank` takes an unowned tank at its position, `stray_tank`; `on_cloned` keeps a cloned tank whose depot owns it or stands on it, `cloned_tank_kept`, whichever clone event comes first). A depot cloned alone gets the original tank's fluid (`set_fluid`). A tank cloned without its depot is destroyed.
- The depot's panel shows the tank's fluid (`fuel_contents`), with a flush button (`flush_fuel`: `clear_fluid_inside`, which empties connected pipes too, as a vanilla flush does).

## Remote interface

`jatz-distribution` has `freighter_fuel` (a requesting depot's freighters' fuel in joules: home, fullest first, and out, each with its full tank, the normal capacity, and whether fuel is used), `set_freighter_fuel` (every freighter in a slot) and `fuel_contents`.

## Tests

- `tests/lua/logistics.lua`: burning, the detour and its order, liquid before items, burnt results, staying home, going without, cooldowns, running dry, a removed Fuel depot, cloning, the hover status, an item worth more than a tank, freighters taken out, fuel turned off, the fuel check on a failed pickup and on turning on the road, and fuel through tunnels.
- The check mod (`tests/factorio/jatz-distribution-check_0.1.0`, run by `tools/test_mod.py`): a coal detour before loading, petroleum gas at the mod's own 0.4 MJ, a dry freighter that waits for fuel and then crawls to it, and a cloned Fuel depot.
