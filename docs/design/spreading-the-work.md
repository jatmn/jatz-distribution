# Spreading the work

Every depot and freighter out is checked once a second (`DISPATCH_INTERVAL`, 60 ticks), but not all in the same tick. This page covers how the checks are spread, how searches stay cheap, remembered road lengths, and garbage. Deliveries are in [Roads and deliveries](roads-and-deliveries.md); trip states in [Runtime state](../runtime-state.md).

## Code

- `control.lua`: `on_tick` runs `logistics.on_tick_share` and `logistics.on_impact_share`.
- `scripts/logistics.lua`: trip and depot phases, `suppliers`, `candidates`, the depot index (`depots_at`).
- `scripts/routes.lua`: remembered road lengths. `scripts/promises.lua`: the promise and incoming ledgers.
- Tests: `tests/lua/logistics.lua`, `tests/lua/group-spread.lua`, `tests/lua/busy-searches.lua`; the UPS emulator ([UPS benchmark](../benchmark.md)).

## Trips: one tick each

Each trip gets its own tick of the second (`schedule_trip`), kept in `storage.trip_phases` so every player's game agrees. `on_impact_share` uses the same phases.

Checks must come exactly a second apart. Fuel burns by straight-line distance since the last sample ([Fuel](fuel.md)), so the way out and back must never be measured as one leg. So every stop (`LOADING_TICKS`, no shorter than `DISPATCH_INTERVAL`) has a check in it, and `drive`, `set_off` and `end_trip` burn what was driven since the last sample.

Configuration changes leave `storage.trip_phases` alone: a trip given a new phase could go two seconds without a check. A save from before phases deals its trips out over the phases, burning each trip's fuel first.

## Depots: groups decide together

Requesting depots fetching the same item or fluid on one surface form a group (`check_phase`) checked together. Deciding one by one, later depots found the near providers' stock promised and drove to farther ones.

A large group is spread over up to `logistics.group_ticks` (15) ticks, at most `logistics.group_share` (4) a tick (a group over 60 depots is shared evenly over the 15, more than 4 a tick), never past the end of the second (the owner's report, November 15, 2026: one tick of every second stuttered). It still decides together: `routes.hold_until` holds each search's first answer until the group's last tick, and the ticks held come off `depot.next_send`.

Kept looks: a group's later ticks look only at the depots its first tick found (`storage.passes.looks`), admitting each again. A check that changes unpromised stock or which depots there are must call `logistics.look_afresh`. The owner's choice, November 15, 2026.

## Looking cheaply

- Depots checked in one tick share one look (`suppliers_cache`), kept as lists in step; other candidates wait in a heap (`search.rest`).
- `storage.depot_index` (`depots_at`) is not keyed by force: a script can change an entity's force without an event, so the force is checked as each depot is read.
- The game spoils a cargo stack after its `spoil_tick` with no event, so `file_coming` files the earliest `spoil_tick` and `committed` files the trip again once it has come.
- The contract: call `promise(trip)` after every change to a trip's state, promise or cargo, including state changes alone. `file_promises` files everything afresh for a save from before the ledgers and after `add_all`.

## Remembered road lengths

Each pathfinder answer builds the whole route in the mod's Lua state, a table per tile: the largest source of garbage. So depots remember road lengths (`storage.road_lengths`) for `ROAD_MEMORY_TICKS` (five minutes), forgotten when the surface's road changes and on configuration changes. Reroutes always ask the pathfinder.

Remembered answers go through `storage.road_answers`, never during the tick's depot checks, paced by search, not by answer: pacing by answer made every search of a large group time out. The owner's choice, November 6, 2026, to keep them.

## Garbage

Lua's garbage collection is most of what still stutters on large maps. Its work per tick grows with what the mod allocates per tick, and the last steps of a cycle take longer the more engine objects were made. Tuning the collector made the worst tick worse.

Probed on 2.1.24: reading a position, a setting (`settings.global`), an inventory, a tile, a prototype, or a method off an object (`surface.pollute`) allocates; `valid`, `name`, indices and a bound method called again do not.

So work done every tick must avoid allocation: read settings once a tick, bind methods once, keep inventories, prototype values and research levels (`research_of`), and reuse tables and positions. `load` (`scripts/cargo.lua`) skips leading stacks that can take nothing more, never a stack of the item with room: stacks merge only when quality and data match.
