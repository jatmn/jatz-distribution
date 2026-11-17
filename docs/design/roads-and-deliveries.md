# Roads and deliveries

Freighters drive only on road: every other tile is off-road for the freighter unit, so the engine's own pathfinder keeps them on road and Lua keeps no road-network bookkeeping for ordinary driving. Request and buffer depots send their freighters to the provider (or buffer) depot nearest by road that has what they ask for. Each freighter promises what it will load, loads real item stacks or fluid, brings them home, unloads and parks in its depot's freighter slot.

Trip states and their owners are in [Runtime state](../runtime-state.md). Related designs: [spreading the work](spreading-the-work.md) (once-a-second checks, remembered road lengths, depot groups), [fuel](fuel.md), [road tunnels](road-tunnels.md), [prototypes and placement](prototypes-and-placement.md) (depot road, orientation, loading zone), [circuit network](circuit-network.md), [logistic robots and replacing depots](depots-robots-and-replacing.md), [compatibility](compatibility.md), [quality](quality.md), [cargo paint](cargo-paint.md).

## Code

- `prototypes/roads.lua`: `jatz-road` (tile, item, recipe) and the hidden `jatz-depot-road`.
- `prototypes/off-road.lua` (from `data-final-fixes.lua`): the `jatz_off_road` and `jatz_road` collision layers.
- `prototypes/freighter-drone.lua`: `jatz-freighter-drone`, the delivering unit. `prototypes/truck-chest.lua`: the chest robots bring freighters into.
- `scripts/logistics.lua`: depots, searches, dispatch, trips, arrivals, failures, refunds, remote interface.
- `scripts/routes.lua`: pathfinder questions, remembered road lengths and answers.
- `scripts/promises.lua` (`ledger`): promises at providers, cargo coming home, unpromised stock.
- `scripts/cargo.lua` (`transfer`): moving stacks and fluid, spilling.
- `scripts/trip-state.lua` (`lifecycle`): saved trip and search transitions.
- `scripts/freighter-requests.lua`: freighters asked of construction robots.
- `scripts/blueprints.lua`, `scripts/depot-settings.lua` (with `prototypes/depot-settings.lua`), `scripts/undo.lua`: settings in blueprints, copy and paste, parametrisation and undo.
- `scripts/impact.lua`: running over enemies. `scripts/request-gui.lua`: the depot panel.
- `control.lua`: every event registration (Factorio keeps one handler per event).

## Road tiles and collision layers

- `jatz-road` is a floor tile like stone path. Both road tiles (`jatz-road`, `jatz-depot-road`) carry the `jatz_road` layer.
- `prototypes/off-road.lua` runs in `data-final-fixes.lua`, after every mod. It gives every other tile `jatz_off_road`.
- It adds `jatz_road` to every buildable entity (an item's `place_result`, or one with `placeable_by`), so nothing else, depots included, can be built or ghosted on road, nor road laid under it. Exceptions: belts (loaders and linked belts too), pipes (pipe-to-ground, infinity pipes), train tracks of every kind with rail ramps and supports, vehicles (cars, spider vehicles, rolling stock), and masks that collide with nothing (meant to overlap anything).
- Cliffs get `jatz_road` too, so road can't be laid through one; a road tunnel goes under (the owner's report, November 14, 2026).
- The layer goes in every mask the entity uses on the ground (`ground_masks`): `collision_mask`, and for gates `opened_collision_mask`, since an open gate switches to it. Add any ground-level alternate mask a future type has.
- A depot's loading zone tile is outside its box, so it can be road; every depot lays `jatz-depot-road` there ([prototypes and placement](prototypes-and-placement.md)).

### The freighter unit

- `jatz-freighter-drone` is a hidden unit whose only collision layer is `jatz_off_road`, tiles only (`colliding_with_tiles_only`): it paths over road and nothing else, and collides with no buildings, players or other freighters.
- Its collision box is 0.4 tiles (±0.2). Units overshoot a right-angle turn (about 0.3 tiles at the base speed, more when faster); a 0.8-tile box pinned freighters against the off-road corner across a junction, where they slid sideways and drove back at an angle. With 0.4 they swerve and settle (the owner's choice, November 6, 2026).
- Keep its `path_resolution_modifier` at the default: at 1 the engine found no path for the 0.8-tile box on a one-tile road.
- It is repairable, so construction robots repair it (the owner's report, November 6, 2026). Painted copies show the cargo ([cargo paint](cargo-paint.md)).

## Depots and roles

| Role | Item depot | Liquid depot |
| --- | --- | --- |
| provider | `jatz-provider-depot`, Mining Drones' `mining-depot` ([compatibility](compatibility.md)) | `jatz-liquid-provider-depot` |
| request | `jatz-request-depot` | `jatz-liquid-request-depot` |
| buffer | `jatz-buffer-depot` | `jatz-liquid-buffer-depot` |
| fuel | `jatz-fuel-depot` ([fuel](fuel.md)) | |

- `logistics.depots` maps names to roles. Request and buffer depots request (`logistics.requesting`): each has its own request, freighters, panel, copy and paste and refunds. Buffers also supply request depots. Providers send nothing anywhere.
- Liquid depots are `depot.fluid` (`logistics.liquid`). Candidates must be the same kind (`provider.fluid == depot.fluid`), so items and fluids never meet; copy and paste between kinds copies nothing.
- Sizes are startup settings read by `prototypes/depots.lua`: `jatz-liquid-{provider,request,buffer}-depot-capacity` (1,000 to 1,000,000, 25,000 by default) and `jatz-<role>-depot-slots` for provider, request, buffer and Fuel depots (1 to 1,000, 48 by default; deliveries and refuelling walk a chest stack by stack, hence the cap). Deliveries read sizes from the entity (`get_fluid_capacity(1)`, the inventory), never a constant; the check mod's `settings-updates.lua` gives each a different non-default value.

### Requests

- `set_request` checks `prototypes.fluid` for liquid depots and `prototypes.item` for item depots.
- An item request is capped at the chest's slots times the stack size (`request_limit`), so the panel, copy and paste, tags and the remote interface can't ask for more than the depot holds.
- A liquid request keeps the amount set (`request.asked`) and asks for it as far as the depot holds (`logistics.fit_request`, at `set_request` and every dispatch), following `logistics.fluid_limit` (the tank, or more with freighter storage). An amount no tag can hold (infinity) is kept as `logistics.request_fill` (2,147,483,647, the most a blueprint parameter holds), which fills any depot. Blueprints and copy and paste carry `asked`; `get_request` returns it when above `count`. A request saved before `asked` gets it when first fitted: `request_fill` if at its tank's size, or at least 25,000 for a liquid request depot (whose tank had no setting then), else its amount.
- A new request starts at `jatz-default-item-request` stacks (1) or `jatz-default-fluid-request` (1,000), startup settings read by `scripts/request-gui.lua` (the owner's request, November 13, 2026).
- Changing the request cancels the depot's search, clears its cooldowns, and zeroes the promises of outbound trips for another item; trips for the same item keep what they promised of qualities it still takes.

### Settings that shape deliveries

| Panel control | Field | Depots | Default |
| --- | --- | --- | --- |
| Request from buffer depots | `from_buffers` | request | off |
| Full loads only | `full_loads` | request and buffer | `jatz-default-full-loads` (off) |
| Use freighter storage | `freighter_storage` | liquid request and buffer | off |
| Priority slider, 1 to 10 | `priority` (nil = 5, `PRIORITY_DEFAULT`) | provider and buffer | 5 |

- Each has copy and paste, a blueprint tag (`jatz_from_buffers`, `jatz_full_loads`, `jatz_freighter_storage`, `jatz_priority`) and so undo, and remote `set_`/`get_` calls.
- Full loads only was the owner's request (November 7, 2026), so freighters don't drive out for a single ore; `jatz-default-full-loads` (November 13, 2026) is read by `logistics.add`. Tags record `false` for full loads and freighter storage whatever the setting, so a depot set off stays off.
- `set_priority` rounds and clamps; blueprints keep it only when not 5; `apply_tags` applies it only if a number. A change restarts the searches on its surface (`restart_searches`). Buffer depots have the slider above their request; provider depots get a panel with the slider (item providers also robot access).

## Picking a provider

`search_providers` looks for the supplier nearest **by road** holding the item unpromised. Both loading zones must be road (`loading_tile`).

### Candidates and ranks

- `candidates` lists suppliers of the same surface, force and kind, holding the item unpromised, switched on (`enabled`, [circuit network](circuit-network.md)), with road at the loading zone, and off cooldown for this depot. Depots checked in one tick share one look (`suppliers`, [spreading the work](spreading-the-work.md)).
- Request depots take providers and buffers. Buffers take providers, and with the startup setting `jatz-buffer-priority-pull` (off by default) also buffers of strictly lower priority, item and liquid: the rule is `logistics.buffer_source`, applied inline by `candidates` with the floor read once (`logistics.buffer_floor`). Never an equal priority, never itself.
- `rank` is the kind (asked first 0, the other `PRIORITY_MAX`) plus `PRIORITY_MAX - priority`. For a request depot with `from_buffers`, buffers come first and a nearer provider loses to any reachable buffer. Unset (the default), providers come first and a buffer is asked about only when no provider holding the item unpromised and off cooldown has a road (the owner's choice, November 4, 2026). A buffer ranks its buffer sources with providers, by priority alone.
- Within a rank: nearest in a straight line, then lowest unit number, so every player's game agrees.
- `candidates` returns the first and the rest as a heap (`search.rest`: `ids`, `positions`, `distances`, `ranks`, lists in step; `logistics.sift_candidate`); `route_answered` takes each next one (`logistics.candidate`). Building and sorting a table per candidate for every depot each second was mostly never read, and a linear scan per next candidate cost more than the sort.
- With full loads or a liquid depot, a supplier must hold that load unpromised. Those skipped for cooldown, too little, or (several qualities) no room set the status.

### Asking the road

- `surface.request_path` with the freighter's box and mask (`routes.drone_shape`), one candidate at a time (`routes.ask_route`). Depot searches' answers are remembered ([spreading the work](spreading-the-work.md)).
- The search stops once a rank has a road, or at a candidate already farther in a straight line than the best road, since a road is never shorter.
- With road tunnels, a shorter way through them replaces the road ([road tunnels](road-tunnels.md)).
- No route puts the candidate on a 10-second cooldown for that depot (`RETRY_TICKS`). Laying road, or building, turning or flipping a depot, clears that surface's cooldowns (`retry_now`).

### Search ownership

- Each search has a token (`new_token`); its owner, the depot or a rerouted freighter's trip, holds the token of its one current search (`owner.search`, `lifecycle.owns_search`). A road or depot change, a changed request or priority, a busy pathfinder for a depot's search, or the 10 s `SEARCH_TIMEOUT` replaces or drops it, so stale answers neither set cooldowns nor send freighters. A depot searches afresh at its next dispatch, a freighter at once or at its next check.
- A busy pathfinder (`try_again_later`) ends a depot's search. A freighter's search stands with the candidates already answered and asks the same question again at its next check (`search.again`, `lifecycle.ask_again`, `logistics.ask_again` from `check_trip`) until the 10 s are up, so the pathfinder is asked at most once a second per owner. Started afresh, it asked again about every answered candidate, each answer a whole route for the collector, and on the stress map a few busy answers kept the pathfinder busy for good.
- `on_configuration_changed` (`add_all`) cancels depot searches and restarts freighters'.

## Sending freighters

Each requesting depot's once-a-second check (`dispatch`):

1. Moves freighters into the slot (`absorb_freighters`) and keeps robot requests to their target (`trim_freighter_requests`).
2. A liquid depot pumps freighter storage into its tank (`drain_reserve`) and fits its request.
3. `need` gives what it wants (request less held less coming), its room, whether another fluid blocks the tank, and any excess, which it lets go (`release_excess`) before reading its circuit condition.
4. Sends nothing if disabled, satisfied, full, short of a full load, off road, waiting to retry, without freighters, within `SEND_SPACING` (1 s, per depot) of its last freighter, or searching.
5. Otherwise searches; `finish_search` checks everything again and sends one freighter (`start_trip`).

A depot marked for deconstruction needs nothing: `need` gives no room and all that is coming as excess, so it lets its promises go and a freighter reaching a provider for it loads nothing. Freighters refilled what robots were emptying, for ever (the owner's report, November 14, 2026).

### Promises

- Each trip promises (`trip.planned`) the rest of the need, as far as the provider has it unpromised and the freighter carries (`research.cargo_stacks` stacks, 2 before research; `research.fluid_capacity_of`, 750 before research; more for better [quality](quality.md)). So the next freighter goes to the next provider, and large requests gather from several.
- `storage.promised` files promises by provider and key, `storage.promise_totals` their totals (each rounded up to a whole unit: exact for items, never less than the promises for fluid), `storage.coming` the cargo coming home, re-filed at its spoil tick (`storage.spoiling`). `available` is stock less promises; `committed` what a depot's freighters bring, counted only for the item it requests now.
- A provider keeps promises in order (`trip.queued`, `logistics.ahead`). Its check (`keep_promises`) sends freighters it no longer has a load for (stock taken out, switched off) to look elsewhere at once.
- A freighter goes to another provider at most once a trip (`trip.diverted`); after that a failed pickup goes home (the owner: no going back and forth). Giving up (`logistics.give_up`) frees its promise at once (`trip.passed`).

### Letting excess go

A depot holding and expecting more than it requests (filled some other way) cuts its outbound promises, the last promised first (`logistics.release_excess`), so providers can give that stock to others at once. A trip cut to nothing goes home (`logistics.home_empty`; one still at home parks). Untouched: trips loading at a provider, trips bringing cargo home, and trips sent for a larger request than the depot has now (`trip.request_count`): a lower request isn't stock got elsewhere, and typing 200 used to pass through 2 and 20 and cut freighters for good (the owner's decision, November 7, 2026).

### Full loads and least fluid

- `logistics.full_load(depot, trip)` gives the least a freighter may set off (or be rerouted) to load, and what it carries. With Full loads only: its capacity, or the whole request if smaller. Deliberately the whole request, not what is missing: a depot with part of a small request in stock waits until one trip can bring all of it.
- A new freighter's capacity is the next one's (`logistics.next_freighter`, the depot's best quality); one already out carries its own cargo inventory's size (fluid: `research.fluid_capacity_of`, read again by `arrived_at_provider`).
- Every send decision applies it: `dispatch` waits (status `full-load`, yellow) while room is below it, `candidates` skips suppliers with less unpromised, `finish_search` checks both again, and `reroute` sends the freighter home when room besides its other freighters (`need(depot, id)`) is below it. A reroute that finds a provider plans a full load afresh (`min(room, unpromised, carries)`).
- Least fluid: a liquid depot not on full loads still has `logistics.least_fluid` (100, the owner's choice, November 8, 2026), or its request if smaller, so freighters skip the fractions pumps leave behind and tanks a little short. Status `least-fluid` (yellow); a rerouted liquid freighter plans afresh too.
- At the provider a freighter loads what fits whatever the threshold: something beats driving home empty.

## The trip

- `start_trip` takes the best freighter in the slot (of those, the most fuel), creates the unit at the loading zone at the freighter's quality, and keys the trip by unit number in `storage.trips`. The freighter item rides along (`trip.truck`) and goes back into the slot when the trip ends, unless the freighter is destroyed.
- `trip.buffer_pull` records whether the pickup was admitted as a buffer pull, at dispatch and reroute. `arrived_at_provider` checks `logistics.buffer_source` again before such a pickup loads (a priority changed or a source replaced on the way gives nothing). A request depot's pickup from a buffer (`buffer_pull` false) still loads after its home becomes a buffer (`tests/lua/depot-swap.lua`).
- Every command goes through `logistics.command`, which counts them (`trip.command_id`) and holds them while under ground; every command has `distraction = none`. Each leg starts in `drive` (fuel burned so far; a plan through tunnels) after `set_off` checks its fuel ([fuel](fuel.md)).
- Arriving to load or unload, a freighter stands 1 s (`LOADING_TICKS`): `on_ai_command_completed` gives it a `stop` with `ticks_to_wait` and starts its service (`trip.service`, `lifecycle.begin_service`); the transfer happens when that stop completes. Re-planning skips a trip in service, and a removed depot sends one standing there on at once. One coming home empty parks without stopping.
- At the provider it loads what it promised, as far as its depot (counting its other freighters) still needs and has room for (`get_insertable_count`), only if the request is still for that item and the promises ahead leave it some (`logistics.honoured`).
- Loaded, it shows its cargo in alt mode as machines show their recipe (`show_cargo`): the icon over `utility/entity_info_dark_background`, `rendering.draw_sprite` on the `entity-info-icon` layer, targeting the freighter. `repaint` swaps the unit and drops them, so they are drawn after it. `tests/lua/harness.lua` fakes `draw_sprite` strictly (2.1's parameters, layers, existing sprites).
- Each freighter out pollutes `POLLUTION_PER_SECOND` (0.005, Transport Drones' default) at its check, credited to the freighter in the statistics.
- One with nothing to load, or whose reroute finds nothing, drives home empty.

## Liquid deliveries

- A liquid trip has `trip.fluid = { amount, temperature }` instead of a cargo inventory. It loads with `remove_fluid(1, amount)` (which returns the temperature), keeps it, and unloads with `insert_fluid`.
- Fluid that doesn't fit goes back to the provider (`returning`); fluid with nowhere to go is lost (it can't be spilled).
- A tank holding another fluid has no room and shows `other-fluid` (yellow).
- Freighter storage (the owner's request, November 14, 2026): ticked, `logistics.fluid_limit` is the larger of the tank and all its freighters' capacity (parked and out, times `research.fluid_capacity_of`). The owner's rule: a 25,000 tank and 50 freighters of 2,625 make 131,250, not the sum.
  - `need` counts room against the limit, and what parked freighters hold (`depot.reserve`, one fluid with its temperature) as held.
  - Fluid the tank has no room for stays in the reserve (`logistics.store_in_freighters`: at most the limit less the tank, only the fluid requested now).
  - `drain_reserve` pumps it into the tank each second, ticked or not, so unticking or losing freighters never loses fluid (removing the depot does).
  - A reserve of a fluid no longer requested waits for that fluid to be asked again, rather than entering pipes meant for another; meanwhile `need` gives only the tank's room. A reserve whose fluid's mod was removed is forgotten.

## Road cuts, removed depots and rerouting

- Road removed or covered (any tile event, `script_raised_set_tiles` included, through `control.lua` to `logistics.on_roads_changed`) marks the surface's freighters (`trip.road_cut`) and the tick (`storage.road_cuts`). Each re-plans at its own check (`logistics.replan_cut`), within a second or so, so a route that is gone fails then rather than after the engine's ~6 s stuck timeout.
  - Not in the event, and not while road is still being removed there (`logistics.cut_quiet`, 10 ticks). Road removed tile by tile raises an event per tile: on a player's save (November 15, 2026: 17,372 road tiles, 30 tunnels, 281 freighters out) re-planning all of them in each event froze the game for seconds.
  - With tunnels, a freighter whose way the removed tiles can't touch drives on (`tunnels.untouched`, [road tunnels](road-tunnels.md)).
- Road laid, or a depot built, turned or flipped: cooldowns cleared, searches restarted, and trips to or from that depot re-plan (`on_depot_changed`).
- `replan` replaces the command, so `behavior_result.deleted` completions are ignored. A freighter waiting for a reroute search stays stopped; re-planning and completions skip it.
- A removed provider: its outbound freighters stop and search from where they stand (`reroute`); if the one found empties or goes meanwhile, they search again. Cargo being returned to it goes back to the request depot, or spills.
- A removed request depot: cargo goes back to the provider (`returning`); empty freighters just leave.

## Failed commands and lost freighters

- Killed by enemies, a freighter fails its command at 0 health while still valid; `on_ai_command_completed` ignores that, and it is lost once gone (`on_object_destroyed`).
- Killed by a script (`LuaEntity::die`: console, editor, another mod), it fails with its health still showing (probed on 2.1.24). So failures wait for the next tick (`storage.failed_trips`, `logistics.failed_commands`, first in `control.lua`'s `on_tick`): gone by then, it is lost; otherwise it lost its way, but only if that command is still its latest (`trip.command_id`). A command given meanwhile (depot removed, re-plan, reroute) supersedes the failure, so a loaded freighter sent back that tick isn't failed again and its cargo spilled. Taken home at once instead, a killed freighter went back into the slot for free and no replacement was asked for.
- A failed route puts the provider on a 10-second cooldown (`route_failed`). A loaded freighter that can't get home returns its cargo to the provider, and spills it only if that fails too.
- A lost freighter (`lose`) doesn't return its item; its depot asks robots for a replacement (`match_freighters` to what it had, or its `replenishment.target` if higher, at the lost one's quality), as soon as a chest stack is free. One put in by hand counts.

## Cargo integrity

- Cargo moves as real stacks in a script inventory (`transfer.load` with `transfer_stack`, `transfer.unload` with `insert` of the stack), never as name and count, so item data (equipment, spoilage, health) survives. Keep it that way.
- Spilled cargo (`transfer.spill`) is looted and marked for deconstruction for robots, never put on belts.
- Saves from the first version carried cargo as a number: `upgrade(trip)` converts it on use (the mod version didn't change then).
- `on_configuration_changed` clears requests and ends trips for items or fluids whose mod was removed.

## Refunds when a depot goes

- Mined (player, robot or platform, `on_*_mined_entity` in `control.lua` → `on_depot_mined`), a requesting depot hands every freighter, in the slot, out and in its truck chest, to the miner's buffer; those out finish their trips and leave. Not when it is replaced by itself at another quality or by its request/buffer partner ([logistic robots and replacing depots](depots-robots-and-replacing.md)).
- Died, or removed by a script raising `script_raised_destroy`: they are left on the ground where it stood, chests included (`on_depot_destroyed` for its own chest, `on_object_destroyed` for its truck chest).
- Removed silently: `on_object_destroyed` (end of the tick or the next) leaves them there. A depot `check_depot` or `add_all` finds gone first is handed to `on_object_destroyed` at once, so every way ends in one cleanup.
- Cloned depots are registered with their request; cloned freighters and truck chests are removed.

## Enemies and wrecks

- The freighter is a military target (`is_military_target`), so enemies attack it; it never fights back or turns aside.
- `scripts/impact.lua` (through `logistics.on_impact_share`, spread over the trips' phases): every 20 ticks (`IMPACT_INTERVAL`, the owner's choice, November 6, 2026) a freighter that moved damages enemy `unit`, `spider-unit` and `segmented-unit` entities in the ground it crossed, `IMPACT_REACH` (0.4 tiles, its box's width before narrowing) either side.
  - The ground is counted first (`count_entities_filtered`, one reused filter) and listed only when something is there. With no such entity in the game but freighters (`units_exist`, `LuaForce::get_entity_count` per prototype at each round's start), nobody looks, and the first look after only notes positions (`storage.impact_paused`).
  - Each enemy takes `IMPACT_DAMAGE` (200) impact damage at most once a second from each freighter (`trip.hits`), the freighter as source and cause. Damage runs other mods' handlers at once, so validity is checked before reading anything.
  - Characters, buildings and other freighters (any paint, `paint.is_drone`) are never hit, and nothing collides. A freighter in a tunnel hits nothing.
- A destroyed freighter explodes like the car and leaves `jatz-freighter-remnants` (15 minutes). Each depot leaves its own `jatz-<role>-depot-remnants` facing as it did: seven wrecks from five sheets (Provider and Request share the cargo one, Liquid Provider and Liquid Request the liquid one), each in its depot's palette, rendered by `assets/depots/tools/build_remnants.py` ([assets/depots/README.md](../../assets/depots/README.md), "Remnants"). The check mod destroys each depot facing three ways and requires its wreck, and the ambushed freighter's.

## Freighters at the depot

### Slot and truck chest

- A requesting depot holds up to 100 freighters (`FREIGHTER_CAPACITY`, counting those out; the item stacks to 10) in a script inventory (`trucks_of`): ten stacks plus one per quality beyond normal, as qualities never share a stack, so every freighter out can come back. Older slots are resized; the panel shows one slot.
- Every requesting depot has a truck chest (`jatz-truck-chest`): invisible, unselectable, indestructible, twenty slots, at its centre, colliding with nothing, ignored by inserters (`no-automated-item-removal`/`-insertion`) and skipped by blueprints. `logistics.add` makes it (`add_all` and `truck_chest()` for older saves); it goes with its depot; a cloned one is removed.
- Robots bring freighters into it, never into the depot: storage tanks have no item inventory, and inserters unloading an item depot took robot-delivered freighters before the next dispatch, so the depot asked for more, over and over (the owner's video, November 7, 2026; the check mod's `deliveries.unloaded`, emptied by a burner inserter, reproduces it).
- `truck_chest(entity)`/`freighter_chest(entity)` map a depot to it; every freighter request, removal and count goes through them. Its freighters move into the slot at dispatch (`absorb_freighters`), except those waiting to be taken away (`logistics.leaving`).

### Moved by hand

- Freighters in an item depot's own chest also move into the slot at dispatch (`logistics.waiting_freighters` counts both chests), unless freighters are its request (then they are cargo).
- Ctrl+ or shift+click in the depot's window, ctrl+click on it in the world, or a drop (`on_player_dropped_item_into_entity`) moves them at once (`take_in_freighters`); what doesn't fit goes back to the player. Item depots take them in their own chest, liquid depots in the truck chest.
- `on_player_main_inventory_changed` and `on_player_cursor_stack_changed` work out how many fewer freighters the player carries, inventory and cursor together (counted on opening or pointing at the depot, and at every change). Placing onto a requested freighter's ghost counts; moving between inventory and cursor doesn't.
- Only what the player just put in moves: at most what left their inventory, and no more than the chest gained since last seen (`depot.chest_seen`). Other items stay, as in any container.

### Asked of robots

- Robots can't reach a script inventory, so freighters are requested like modules: `request_freighters` adds an insert plan (one empty chest stack, 0-based) to an `item-request-proxy` targeting the truck chest, within the slot's room counting those out, in the chest, requested, and still waiting for a free stack.
- The panel does this when the cursor holds a freighter ghost. In remote view it never moves items: a click with an empty cursor cancels freighter requests (`cancel_freighter_requests`), a right-click has robots take the slot's freighters away (`remove_freighters`: moved to an empty truck chest stack with a removal plan; right-click again: `cancel_freighter_removal`).
- Requests remember their target (`depot.replenishment.target`, the total to end up with), set before free stacks are looked for, so a chest short of free stacks (it also holds cargo) delays them rather than losing them. `request_up_to` aims at an absolute target; `request_freighters` adds to what is had or awaited, so a retry never counts twice.
- Every dispatch and every hand insertion keeps requests to the target (`trim_freighter_requests`): excess cancelled, a shortfall nothing covers asked again (Factorio drops an item request a player fills even partly by hand). The target is forgotten once met, or when the player takes freighters out or has robots remove them. Requests without one (Factorio's own from a ghost a player built over, which passes no tags) adopt the depot's current total.
- `match_freighters` to a smaller count cancels requests but never takes freighters away. Requests are lowered by editing proxy plans in place (`reduce_freighter_requests`), the last asked first (`depot.freighter_asks`).
- Freighters asked of an item depot's own chest by a proxy targeting the depot (an old blueprint's or save's, another mod's) are asked of its truck chest instead: `trim_freighter_requests` drops those plans from every such proxy (found by position, as `item_request_proxy` names only the first) and adds them to the target. `apply_tags` trims each requesting depot as it is built.
- Counts for copying and blueprints are `freighter_total` (slot, out, chest not leaving, coming).

## Blueprints, copy and paste, and parametrisation

- Copy and Paste settings and clones copy the request, a provider or buffer depot's priority and any delivery depot's circuit condition; the destination asks robots to match the source's freighters (slot, out, coming).
- Blueprints keep a requesting depot's request as `jatz_request` and its freighters as `jatz_freighters`, never as an insert plan: parametrisation would offer that item to swap, and robots would bring the chosen item as cargo. `setup_blueprint` (from `on_player_setup_blueprint`; the blueprint may be the record, the stack, `blueprint_to_setup` or the cursor, any nil) replaces those settings on a re-setup, keeps other tags and items' plans, and drops old freighter plans.
- A depot built from a ghost applies well-formed tags (`apply_tags`, every build event) and asks robots for its freighters (`match_freighters`).

### Parametrisation

The game parametrises only its own entity settings, and 2.1.24 has no API for blueprint parameters. So `setup_blueprint` also puts each requesting depot's request and freighters in `jatz-depot-settings`, a hidden decider combinator at its centre that exists only in blueprints (the game refuses entities no item places, hence a hidden item). Reported by the owner, November 7, 2026.

- The request is a condition comparing its item or fluid to its amount; the freighters a condition with only a constant (the owner's choice, November 7, 2026: a constant combinator slot needs a signal, "ID must be provided when count values are set", so it offered an item to swap; a decider keeps a bare constant through blueprints, ghosts and revives, and its conditions never merge).
- They hold the depot as it is, request (or none) and freighters (none included), so pasting over the same depot sets both, as Copy and Paste settings does. Its other settings (priority, from-buffers, full loads, circuit) aren't pasted.
- `settings_of` reads the condition with a signal as the request and the constant-only one as the freighters, in either order; no request condition (nor tag) means none (`false`). A request the depot can't take (a fluid for an item depot) is no word on it.
- Their tag `jatz_settings_of` names their depot; only that depot, of their own force, takes them, so a forced paste over another kind changes nothing. Without the tag they are ignored.
- A condition's constant is an int32: a request above 2,147,483,647 (only a huge-stack item gets there; the check mod defines one) is held as the settings' own `jatz_request` tag. A non-"=" quality comparator is their `jatz_quality_comparator` tag ([quality](quality.md)).
- Probed on 2.1.24: a blueprint's ghosts are all placed before their build events, and a combinator ghost reads its conditions. So the settings ghost's build event (`depot_settings.built`, also filtered by `ghost_name`) writes them into the depot ghost's tags at its position, or onto that depot already there, and destroys itself. A depot built takes its settings ghost in `apply_tags` (`logistics.take_request_settings`), tags or not (a script's `build_blueprint` without `raise_built` raises nothing), before its own tags.
- Settings built at once (the editor) carry tags only in their own build event, so the depot leaves them to it; if that event comes first they note what they gave (`storage.depot_settings_given`, that tick only) so the depot's older tags don't override them.
- Nothing stays in the world, so saves need no migration, and old blueprints work from their tags. `require` works only while loading, so `scripts/depot-settings.lua` installs `logistics.plan_request_settings` and `take_request_settings` as hooks.

## Undo

Factorio records a removal on the player's undo stack from the entity alone, so undo would bring back a bare ghost. `scripts/undo.lua` works out the settings of a depot or road network monitor a player removes as a blueprint keeps them (`logistics.settings_tags`) just before it goes, while its chest still holds its freighters, and puts them on the `removed-entity` action as `jatz_settings` (`LuaUndoRedoStack.set_undo_tag`). An empty snapshot still replaces an earlier attempt's.

- Marked for deconstruction (cutting too): the action is made just after `on_marked_for_deconstruction` and keeps its tags through the robots' removal (probed on 2.1.24). So the mark only notes who marked it (`storage.undo_marked`, forgotten on `on_cancelled_deconstruction` or when it is gone, since an attempt can fail and leave it marked), and `on_robot_pre_mined` or `on_space_platform_pre_mined` tags that player's action with the settings as they are then. Liquid depots and the monitor can stand on a platform, which takes a marked entity within the tick.
- Each tagged action is marked with its removal (`jatz_removal_of`, the unit number) and no other removal takes it: history places aren't identities (items are pushed on top, and at the limit of 100, probed on 2.1.24 and not in the API docs, the oldest drops).
- Reading an undo item builds all its actions, so `on_tick` locates all of a player's marked entities in one pass in the tick of the marking and remembers each action's index within its item. A robot or platform removal then reads only that tag of each item (`get_undo_tag` in `pcall`: an out-of-range index raises).
- Mining by hand makes its undo item only after `on_player_mined_entity`: `on_pre_player_mined_item` holds the settings (`storage.undo_mining`) until that event, then they wait (`storage.undo_pending`) for the next `on_tick` (given up after 60 ticks). Every waiting removal is matched in each pass, this tick's too, by surface, name and position, newest to newest, never to another's action, so removals at one spot never swap settings.
- `on_undo_applied` puts the action's tags (or settings still waiting, if a ghost came back) on the returned ghost, keeping its other tags; its build, by robots or player, applies them like a blueprint ghost's. Undone before robots took it, the deconstruction is just cancelled.
- Not handled: redo (`get_redo_tags` exists), and the editor with instant building (undo revives at once, no ghost).
- The mod's own entities and tiles (truck chests, Fuel depot tanks, freighters, proxies, depot road) are made and removed without `player` or `undo_index`, so they never reach an undo queue.
- `tests/lua/control-events.lua` fakes the stack. The check mod's `scenarios/undo` (`--test-scenario`, which gives it a player) checks the tagging (failed hand mining, a liquid depot cut on a Space Age platform) and rebuilds by robots, player and platform. Pressing undo can't be scripted (`game.simulation` is nil there and `LuaUndoRedoStack` can't apply an item, probed on 2.1.24), so `on_undo_applied` is covered only by the Lua checks and the graphical client.

## The depot panel

- `scripts/request-gui.lua`, a relative GUI on the depot's window: `container_gui` for item depots, `pipe_gui` for liquid depots (2.1 removed `storage_tank_gui`).
- The fluid chooser's `FluidPrototypeFilter`s have no `is-parameter`; parameter fluids are left out by their `parameters` subgroup.
- A pipe window doesn't show the character inventory, so a liquid depot's adds the player's main inventory (ten slots a row, not in remote view): click picks up, shift- or ctrl-click on a freighter puts it in the slot.
- The amount field isn't rewritten while typing (the next key would add to it): it shows the depot's request on Enter (`on_gui_confirmed`) or 2 s after the last key (`show_request_count`, `tags.typed_at`), and follows it otherwise.
- Beside the slot (freighters at home): "3 out" (`request_gui.freighter_caption`) and a green "+N" while N are requested, with the full breakdown as tooltip. This is where requests show, since the depot's window draws no ghosts for truck chest requests.
- Pipette over the slot (`jatz-pipette`, linked to the game's pipette control, with `raise_hover_events`) calls `LuaPlayer.pipette` for the freighter, ghost allowed.
- Status is a light (`utility/status_working`, `status_yellow`, `status_not_working`, `status_inactive`; style `status_image`) with the text as tooltip. Green: stocked or coming. Yellow: available but blocked (no route, no road, no freighters, full, full load or least fluid, other fluid, no fuel). Red: disabled, nothing it fetches from has the item, or no Fuel depot. Grey: no request. Every `logistics.status` needs an entry in `request_gui.lights` (`tests/lua/control-events.lua` checks).

## Remote interface and debugging

- The remote interface `jatz-distribution` (`logistics.register`) serves the check mod: requests and status, the settings above, robot access, circuit conditions, freighters (`add_freighters` within the slot's limit, no raw inventory; `freighter_counts`, `request_freighters`, `requested_freighters`, `cancel_freighter_requests`, `remove_freighters`, `cancel_freighter_removal`, `match_freighters`, `take_in_freighters`, `describe_freighters`), `setup_blueprint` and fuel.
- `/jatz-freighters` prints, for the request depot a player has open or points at, everything its freighter requests are worked out from (`logistics.describe_freighters`). Use it when freighter requests misbehave in play.

## Tests

- `tests/lua/logistics.lua` plays searches, trips and races against the fake runtime (`tests/lua/harness.lua`) under Lua 5.2, run by `tools/test_mod_setup.py`, including the slot's sending, returning, losing and handing back; extend it with any change to the search or the freighters. It runs `tests/lua/busy-searches.lua` (question asked again, answered candidates kept, timeout, restart meanwhile), `tests/lua/road-cuts.lua` and `tests/lua/freighter-storage.lua`.
- `tests/lua/depot-swap.lua` covers pickup admission through home replacement and reload; `tests/lua/control-events.lua` the event registrations, the undo stack and the status lights.
- The check mod checks deliveries in the real engine ([testing](../testing.md)).

## Known engine traps

Beyond those noted above:

- An open container window doesn't redraw requested-item ghosts for script changes. Reopening it by script (over two ticks; within one does nothing) works but flashes, and the owner chose no flash: the ghost updates on the next open, and the panel shows the live count.
- 2.1 removed `LuaEntity::fluidbox`: use `get_fluid(1)`, `get_fluid_capacity(1)`, `remove_fluid(1, n)` and `insert_fluid`.
- `on_object_destroyed` comes at the end of the tick or the next; check entities valid before then.
- Lua 5.2 allows 200 active locals per function, a file's main chunk included: read the "Top-level locals" rule in [AGENTS.md](../../AGENTS.md) before adding any to `scripts/logistics.lua`.
