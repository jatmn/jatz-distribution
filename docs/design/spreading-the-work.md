# Spreading the work

Every depot and every freighter out is checked once a second (`DISPATCH_INTERVAL`, 60 ticks), but not all in the same tick, so hundreds of depots and thousands of freighters never stall the game.
This page covers how the checks are spread, how a depot's search avoids looking at every depot and trip, how road lengths are remembered, and how the mod keeps garbage collection from stuttering.
The deliveries themselves are in [Roads and deliveries](roads-and-deliveries.md); the trip state machine is in [Runtime state](../runtime-state.md).

## Code

- `control.lua`: `on_tick` runs `logistics.on_tick_share` and `logistics.on_impact_share` every tick.
- `scripts/logistics.lua`: trip phases (`trip_phases`, `schedule_trip`, `check_trip`), depot phases (`check_phase`, `depots_due`, `check_depot`), `suppliers`, `candidates`, the depot index (`depots_at`).
- `scripts/routes.lua`: remembered road lengths and the queue of remembered answers.
- `scripts/promises.lua`: the promise and incoming-cargo ledgers.
- `scripts/research.lua`, `scripts/cargo.lua`, `scripts/loading-zone.lua`: values kept to avoid allocation.
- Tests: `tests/lua/logistics.lua`, `tests/lua/group-spread.lua`, `tests/lua/busy-searches.lua` (both run by `tests/lua/logistics.lua`), and the UPS emulator (`tools/emulate_ups.py`, see [UPS benchmark](../benchmark.md)).

## Trips: one tick each

- Each trip gets its own tick of the second, its phase, when it sets off (`schedule_trip`: the phase with the fewest trips). `storage.trip_phases[phase + 1]` lists the trips of each phase.
- The phases are in storage so every player's game agrees. Repainting moves `trip.id` with the trip; trips no longer out leave the lists when their tick comes.
- `check_trip` burns and shows fuel, pollutes, restarts a timed-out search, re-asks a question a busy pathfinder refused, re-plans after a road cut, handles a dry tank, and reports a deferred repaint.
- `on_impact_share` uses the same phases, so each freighter looks for enemies exactly every 20 ticks.

Checks must come exactly a second apart, the first within a second of setting off. Fuel is burned by the straight-line distance since the last sample (see [Fuel](fuel.md)), so the way out and the way back must never be measured as one leg, which would cancel out. Two rules guarantee this:

- Every stop (`LOADING_TICKS`, 60, no shorter than `DISPATCH_INTERVAL`) has a check in it.
- A freighter can turn without stopping (a pickup given up or cancelled, a reroute, a road cut) or park with no stand (coming home empty). So `drive`, where every leg starts, and `end_trip` burn what was driven since the last sample, and `set_off` burns it before deciding whether the leg needs a Fuel depot.

Configuration changes leave `storage.trip_phases` alone (`add_all` does not touch it): a trip given a new phase could go up to two seconds without a check.
Save migration: the first use in a save from before phases deals the trips out over the phases in turn, burning each trip's fuel first.

## Depots: groups decide together

`depots_due` makes a plan at the start of each second (`storage.passes.depots`); depots added during a second wait for the next.

- Requesting depots fetching the same item or fluid on the same surface form a group (`check_phase`). Each group starts at its own tick (`storage.check_phases`), the next new group 37 ticks on (`GROUP_STRIDE`).
- Other depots (providers, Fuel depots) are checked at the tick of their place in the pass.
- `check_depot`: requesting depots dispatch, providers and buffers keep their promises (`keep_promises`), a Fuel depot's tank is kept facing as the depot, and a depot whose entity is gone is forgotten as `on_object_destroyed` would.

Why groups decide together: deciding one by one, later depots found the near providers' stock promised to earlier ones and drove past them to farther ones (14% fewer deliveries in the UPS emulator with the same freighters).

### Spreading a large group

The owner's report, November 15, 2026: dozens of depots asking for one fluid, each ranking every depot holding it, made one tick of every second many times longer than the rest, a stutter. So a group's checks are spread too:

- At most `logistics.group_share` (4) depots of a group are checked in a tick, the rest in the following ticks, up to `logistics.group_ticks` (15, a quarter of a second).
- A group of more than 60 depots is shared evenly over the 15 ticks, more than 4 in each.
- A group never runs past the end of the second, where the next plan starts: one that would starts earlier.

The group still decides together. While a depot checked before the group's last tick is checked, `routes.hold_until` holds that tick (`depot.group_ends` is the group's last tick of the second). Its search's first answer, remembered or the pathfinder's, waits in `storage.road_answers` until then (`search.hold`). So no depot sends a freighter, and promises stock, before the last has looked.

The ticks a search waited (`search.held`) are taken off `depot.next_send` in `finish_search`. A depot sends at most one freighter a second, counted from when its freighter left; without this, the depots answered first sent every other second instead of every second (7% fewer items delivered).

### Kept looks

In its ticks after the first, a group looks only at the depots its first tick found able to supply it (`storage.passes.looks`: their unit numbers, forgotten with each second's plan).

- Each kept depot is admitted again as at the first look: its stock, circuit condition, force and loading zone can change between ticks with no event.
- A depot found only since waits for the next second, as when the group was checked in one tick.
- A check in between that changes what the depots hold unpromised, or which depots there are, calls `logistics.look_afresh`. That drops the kept look, so the group's later ticks look at every depot again. Stock a depot lets go of (`release_excess`) then goes to the depots of its group checked after it, not to farther providers.

The owner's choice, November 15, 2026: kept looks, so every depot a search starts with is still able to supply it, at some cost to the mean (looking at every depot again in each tick cost 6% more of the mod's Lua).

## Looking at depots and trips cheaply

- **Shared look.** Depots checked in the same tick share one look at the depots that can supply them (`suppliers`, cached in `suppliers_cache` only during a tick's depot checks, keyed by surface, force, kind, item and quality filter). A check that changes stock or promises (a provider's `keep_promises` rerouting trips, a depot found gone, `release_excess`) calls `logistics.look_afresh`, which drops the cache and the group's kept look.
- **Lists in step, a heap of candidates.** The look is three lists in step (`ids`, `depots`, `positions`), not a table per depot. A search takes only its first candidate at once; the others wait in a heap (`search.rest`, `logistics.candidate`) until the search comes to them. A table per depot and a sorted table per search made about 10,000 tables a second for a group of 100 depots, nearly all never read.
- **Depot index.** `suppliers` and the Fuel depot search (`fuel_candidates`) read `storage.depot_index[surface index][role]` (`depots_at`), not every depot. `logistics.add`, the removals (`on_object_destroyed`, also reached from `check_depot`) and `logistics.replaced` (a request and buffer depot swapping roles) keep it up to date. It is built afresh when missing; `add_all` drops it. It is not keyed by force: a script can change an entity's force without an event, and merging forces moves entities, so the force is checked as each depot is read.
- **Promise ledger.** A provider's unpromised stock is its stock less the promises filed for it (`storage.promised[provider][key][trip.key]`, with totals in `storage.promise_totals`). See [Roads and deliveries](roads-and-deliveries.md) for how dispatch uses it.
- **Incoming ledger.** What a requesting depot's freighters are bringing (`committed`, read by `need`) is filed in `storage.coming[request][key][trip.key]`: each trip's promise on the way out, its cargo on the way home (`file_coming`, called from `promise`).
- **Spoiling cargo.** The game turns a whole stack into its spoil result just after its `spoil_tick` (on that tick it is still there), inside the cargo inventory, with no event. So `file_coming` also files the earliest `spoil_tick` of a returning trip's cargo (`storage.spoiling[request][item]`, only for items whose `get_spoil_ticks()` is above 0), and `committed` files that depot's trips for the item again (`file_spoiled`) once the tick has come.
- **Freighter counts.** Freighters in a chest are counted in one call (`get_item_count_filtered` with a name and no quality matches every quality). A chest's item request proxies are searched for only when `item_request_proxy` says it has one.

The contract: call `promise(trip)` after every change to a trip's state, promise or cargo, including state changes alone (`arrived_at_provider`, a route lost on the way home, fluid that didn't fit, a depot removed). `file_promises` files everything afresh for a save from before the ledgers and after `add_all`.

## Remembered road lengths

The engine's path answers were the largest source of garbage: every `on_script_path_request_finished` builds the whole route in the mod's Lua state, a table per tile.

- Depots remember road lengths (`storage.road_lengths[surface index]`: `lengths` by `road_key`, loading zone to loading zone, `false` for no road, and the `ticks` they were found), for `ROAD_MEMORY_TICKS` (five minutes).
- A surface's lengths are forgotten whenever its road changes (`on_roads_changed`, which also counts up `storage.road_versions[surface index]`; an answer to a question asked before the change is not remembered) and on configuration changes.
- Freighters' reroutes start wherever the freighter stands, so they always ask the pathfinder.

A remembered length is answered as the pathfinder's would be, through `storage.road_answers` (`answer_remembered`, called after the tick's depot checks):

- Never during the tick's depot checks (`routes.checking_depots`), so a group still decides together.
- Paced by search, not by answer, since each search that ends sends a freighter off. A search given a remembered answer takes its next remembered ones at once (`give_remembered`) until it ends or asks the pathfinder.
- Searches are answered in the order asked, at least `REMEMBERED_PER_TICK` (3) a tick, or as many as clear the queue evenly within `DISPATCH_INTERVAL` of the oldest's question. A search made stale meanwhile is dropped without taking a turn.
- Pacing answer by answer let a large group's searches each wait their turn for every candidate, so none finished within `SEARCH_TIMEOUT` and every one restarted (Pullfrog's review of `5832360`). `tests/lua/logistics.lua` sends 300 depots comparing 7 providers each from remembered roads.

Depots send freighters off sooner with remembered roads than with the pathfinder alone. The owner's choice, November 6, 2026, to keep it: in the UPS emulator, which answers the pathfinder's questions a few ticks late, 31% more items are delivered on the standard preset.

## Garbage

Lua's garbage collection is most of what still stutters on the stress map. The collector's work per tick grows with what the mod allocates per tick, and a collection that frees much of the heap at once takes several milliseconds in one tick. Fewer, larger collections cost more than many small ones: the last steps of a cycle (clearing what is finalized, sweeping strings) take longer the more engine objects (positions, inventories, entities, prototypes) were made. Tuning the collector (`collectgarbage("setpause"/"setstepmul")`, explicit steps) was tried and made the worst tick worse.

Measured on 2.1.24: reading a position makes 200 bytes, a setting (`settings.global[...]`) 200, an inventory 144, a tile 144, a prototype 112, and a method read off an object (`surface.pollute`) 88. `valid`, `name`, indices and a bound method called again make none.

So work done every tick avoids allocation:

- The fuel settings are read once a tick and handed to every `check_trip`.
- Each surface's `pollute` (in `check_trip`) and `count_entities_filtered` (in `scripts/impact.lua`) are bound once a tick.
- A provider keeps its inventory (`depot.stock_inventory`) and its bound `get_item_count` (`stock_counters` in `scripts/promises.lua`, Lua only, rebuilt after a load).
- Item stack sizes, the freighter's speed, which items and fluids exist, and what fuels give are read from prototypes once a session.
- A force's research levels are kept (`research_of` in `scripts/research.lua`: `storage.research_levels[force index]`), forgotten on any research finished or reversed, forces reset, made or merged, configuration changes, and after a minute.
- Impact looks reuse the position that tick's check read (`trip.at`, when `trip.at_tick` is this tick).
- Freighter fuel statuses reuse their tables (`FUEL_STATUS`, `trip.fuel_shown`).
- `loading_zone.tile_centre` reads a position once. A depot keeps its loading zone tile and whether it is road (`loading_tile`: `depot.zone`, read again when the depot turns, its surface's road changes, or after five minutes).
- `load` (`scripts/cargo.lua`) skips the leading cargo stacks that can take nothing more (full, or holding another item). It never skips a stack of the item with room that refused a stack: stacks merge only when their quality and data (health, tags, durability) match, so a later stack can still top it up (Pullfrog's review of `187a87e`: skipping it left damaged machines behind). The test harness's item stacks hold at most their stack size and merge only with matching `health`, as in the game.

## Tests

- `logistics.on_tick` runs every trip's and depot's check at once; `tests/lua/logistics.lua` drives most deliveries with it and checks the spreading itself (`on_tick_share`, `on_impact_share`) separately.
- The harness's shared `check` (`tests/lua/harness.lua`, used by `tests/lua/logistics.lua` and the files it runs, `quality.lua` and `depot-swap.lua`) compares `storage.coming` with every trip at each check, and checks that each spoiling stack's tick is filed (`coming_filed`).
- `tests/lua/group-spread.lua` checks the spreading of a large group, the wait for its last tick, the next freighter, a provider removed, emptied or given to another force between the group's ticks, and stock let go between them.
- `tests/lua/busy-searches.lua` checks that a freighter's question refused by a busy pathfinder is asked again at its next check, keeping the candidates already answered.
