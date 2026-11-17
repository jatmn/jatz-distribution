# Roads and deliveries

Freighters drive only on road: every other tile is off-road for the freighter unit, so the engine's pathfinder keeps them on road and Lua keeps no road bookkeeping for ordinary driving. Request and buffer depots send freighters to the supplier nearest by road that has what they ask for.

Trip, search, undo and road states: [runtime state](../runtime-state.md). Related: [spreading the work](spreading-the-work.md), [fuel](fuel.md), [road tunnels](road-tunnels.md), [prototypes and placement](prototypes-and-placement.md), [circuit network](circuit-network.md), [depots, robots and replacing](depots-robots-and-replacing.md), [compatibility](compatibility.md), [quality](quality.md), [cargo paint](cargo-paint.md), [player guide](../guide.md).

## Code

- `prototypes/`: `roads.lua`, `off-road.lua` (from `data-final-fixes.lua`), `freighter-drone.lua`, `truck-chest.lua`.
- `scripts/`: `logistics.lua`, `routes.lua`, `promises.lua`, `cargo.lua`, `trip-state.lua`, `freighter-requests.lua`, `blueprints.lua`, `depot-settings.lua`, `undo.lua`, `impact.lua`, `request-gui.lua`.
- `control.lua`: every event registration (Factorio keeps one handler per event).

## Road tiles and collision layers

- `jatz-road` and the hidden `jatz-depot-road` carry `jatz_road`; `prototypes/off-road.lua`, after every mod, gives every other tile `jatz_off_road`.
- It adds `jatz_road` to every buildable entity, so nothing else, depots included, can be built on road. Exceptions: belts, pipes, rails, vehicles, and masks that collide with nothing.
- Cliffs get `jatz_road` too, so road can't cross one; a tunnel goes under (the owner's report, November 14, 2026).
- The layer goes in every ground mask, including a gate's `opened_collision_mask`. Add any ground-level alternate mask a future type has.

### The freighter unit

- `jatz-freighter-drone` collides only with `jatz_off_road` tiles.
- Its box is 0.4 tiles: units overshoot right-angle turns, and a 0.8-tile box pinned freighters against junction corners (the owner's choice, November 6, 2026).
- Keep `path_resolution_modifier` at the default: at 1 the engine found no path for the 0.8-tile box on a one-tile road.
- It is repairable by construction robots (the owner's report, November 6, 2026).

## Depots and requests

Roles (provider, request, buffer, fuel; item and liquid) are in `logistics.depots`. Request and buffer depots request; buffers also supply; providers send nothing. A supplier must be the same kind (`depot.fluid`), so items and fluids never meet.

- Deliveries read depot sizes (startup settings) from the entity, never a constant.
- An item request is capped at slots times stack size. A liquid request keeps the amount set (`request.asked`) and asks for it as far as the depot holds (`logistics.fit_request`); a request saved before `asked` gets it when first fitted.
- New requests start at `jatz-default-item-request` / `jatz-default-fluid-request` (the owner's request, November 13, 2026).
- Full loads only was the owner's request (November 7, 2026); its default setting came November 13, 2026. Tags record `false` for full loads and freighter storage whatever the setting, so a depot set off stays off. A priority change restarts its surface's searches.

## Picking a provider

`search_providers` looks for the supplier nearest **by road** holding the item unpromised; both loading zones must be road.

- Buffers take providers, and with `jatz-buffer-priority-pull` buffers of strictly lower priority (`logistics.buffer_source`); never equal, never itself.
- Ranked by kind, then priority. With `from_buffers`, buffers come first. Unset, a buffer is asked only when no provider holding the item unpromised and off cooldown has a road (the owner's choice, November 4, 2026).
- Within a rank: straight-line distance, then unit number, so every player's game agrees.
- One candidate at a time is asked of the pathfinder; the search stops once a rank has a road, or at a candidate farther in a straight line than the best road. No route puts it on a 10 s cooldown for that depot.
- Each search has a token held by its owner; changes or the 10 s timeout replace it, so stale answers neither set cooldowns nor send freighters ([runtime state](../runtime-state.md)). A busy pathfinder ends a depot's search; a freighter's asks the same question again at its next check, keeping answered candidates: restarting re-asked all of them and kept the pathfinder busy for good.

### Changes take effect at once

Changing a request clears that depot's cooldowns and cancels its search (`logistics.set_request`). Laying road clears the surface's cooldowns (`retry_now`) and restarts its searches. Building, turning or flipping a depot does both and re-plans the trips to or from it (`on_depot_changed`). Removed or covered road marks the surface's freighters (`trip.road_cut`) and each re-plans at its own next check (`logistics.replan_cut`), so a lost route fails within a second rather than after the engine's ~6 s stuck timeout. Never re-plan inside the tile event, nor while road is still being removed (`cut_quiet`): one event per tile froze a large save for seconds.

## Sending freighters

Each requesting depot's once-a-second `dispatch` absorbs freighters into the slot, trims robot requests, drains freighter storage, works out its `need`, lets excess go, and sends at most one freighter (`start_trip`), at least `SEND_SPACING` apart.

- A depot marked for deconstruction needs nothing and lets its promises go: freighters refilled what robots were emptying, for ever (the owner's report, November 14, 2026).
- Each trip promises the rest of the need, as far as the provider has it unpromised and the freighter carries, so large requests gather from several providers.
- A freighter goes to another provider at most once a trip; after that a failed pickup goes home (the owner: no going back and forth).
- Excess (filled some other way) cuts outbound promises, last first (`logistics.release_excess`). Untouched: trips loading, trips bringing cargo, and trips sent for a larger request than now (`trip.request_count`): typing 200 used to pass through 2 and 20 and cut freighters for good (the owner's decision, November 7, 2026).
- Full loads only (`logistics.full_load`): the least to set off for is the freighter's capacity, or the whole request if smaller, deliberately not what is missing. Every send decision applies it: dispatch, candidates, `finish_search`, `reroute`.
- Least fluid: a liquid depot not on full loads still waits for `logistics.least_fluid` (100, the owner's choice, November 8, 2026), or its request if smaller.
- At the provider a freighter loads what fits whatever the threshold: something beats driving home empty.

## The trip

- Every command goes through `logistics.command` (counted in `trip.command_id`), with `distraction = none`.
- A freighter loads only what its depot still needs and has room for, if the request is unchanged and promises ahead leave some (`logistics.honoured`).

## Liquid deliveries

- Fluid that doesn't fit goes back to the provider; fluid with nowhere to go is lost (it can't be spilled).
- Freighter storage (the owner's request, November 14, 2026): the limit is the larger of the tank and all its freighters' capacity, not the sum. Overflow stays in `depot.reserve`; `drain_reserve` pumps it into the tank each second, ticked or not, so unticking never loses fluid. A reserve of a fluid no longer requested waits rather than entering another's pipes; one whose mod was removed is forgotten.

## Failed commands

- `replan` replaces the command, so `behavior_result.deleted` completions are ignored.
- Killed by enemies, a freighter fails its command at 0 health; it is lost once gone (`on_object_destroyed`).
- Killed by a script (`LuaEntity::die`), it fails with its health still showing (probed on 2.1.24). So failures wait a tick (`storage.failed_trips`): gone, it is lost; otherwise it lost its way, but only if that command is still its latest (`trip.command_id`), so a freighter sent back meanwhile isn't failed again and its cargo spilled.
- A loaded freighter that can't get home returns its cargo, and spills it only if that fails.

## Cargo integrity

- Cargo moves as real stacks (`transfer_stack`, `insert` of the stack), never name and count, so item data (equipment, spoilage, health) survives. Keep it that way.
- First-version saves carried cargo as a number: `upgrade(trip)` converts it on use.
- `on_configuration_changed` clears requests and ends trips for items or fluids whose mod was removed.

## Refunds when a depot goes

- Mined: every freighter goes to the miner, except when replaced ([depots, robots and replacing](depots-robots-and-replacing.md)). Died or removed: they are left on the ground. Every way ends in one cleanup (`on_object_destroyed`).
- Cloned freighters and truck chests are removed.

## Enemies and wrecks

- The freighter is a military target that never fights back. Every 20 ticks (`IMPACT_INTERVAL`, the owner's choice, November 6, 2026) a moving freighter damages enemy units it crossed (`scripts/impact.lua`); never players (characters), buildings or other freighters. Damage runs other mods' handlers at once, so check validity before reading anything.
- Wrecks: [assets/depots/README.md](../../assets/depots/README.md).

## Freighters at the depot

- The slot is a script inventory with one extra stack per quality, since qualities never share a stack. Older slots are resized.
- Each has a hidden truck chest (`jatz-truck-chest`) ignored by inserters; `truck_chest()` makes it for older saves. Robots bring freighters into it, never into the depot: storage tanks have no item inventory, and inserters took robot-delivered freighters from item depots, so the depot asked for more, over and over (the owner's video, November 7, 2026).
- Robots can't reach a script inventory, so freighters are requested like modules: an insert plan on an `item-request-proxy` targeting the truck chest. Requests remember their target (`depot.replenishment.target`), so a chest short of free stacks delays them rather than losing them.
- Every dispatch keeps requests to the target (`trim_freighter_requests`): Factorio drops an item request a player fills even partly by hand. Requests without a target adopt the depot's total. Old proxies targeting an item depot's own chest are moved to its truck chest.

## Blueprints and parametrisation

- Blueprints keep the request as `jatz_request` and freighters as `jatz_freighters`, never as an insert plan: parametrisation would offer that item to swap, and robots would bring it as cargo.
- 2.1.24 has no API for blueprint parameters, so `setup_blueprint` also puts each requesting depot's request and freighters in `jatz-depot-settings`, a hidden decider combinator that exists only in blueprints (the game refuses entities no item places, hence a hidden item). Reported by the owner, November 7, 2026.
- The freighters are a condition with only a constant (the owner's choice, November 7, 2026): a constant combinator slot needs a signal, so it offered an item to swap.
- A constant is an int32: a larger request is held in a `jatz_request` tag.
- Probed on 2.1.24: a blueprint's ghosts are all placed before their build events, and a combinator ghost reads its conditions, so the settings ghost writes them into the depot (ghost) and destroys itself. Settings built at once (the editor) carry tags only in their own build event.
- Nothing stays in the world, so saves need no migration. `require` works only while loading, so `scripts/depot-settings.lua` installs its hooks.

## Undo

Factorio records a removal from the entity alone, so undo would bring back a bare ghost. `scripts/undo.lua` snapshots a removed depot's or road network monitor's settings as a blueprint keeps them and tags the `removed-entity` action (`set_undo_tag`).

- Marked for deconstruction, the action is made just after `on_marked_for_deconstruction` and keeps its tags through robot removal (probed on 2.1.24), so the tag is written at `on_robot_pre_mined` / `on_space_platform_pre_mined`.
- Each tag is bound to its removal (`jatz_removal_of`): history places aren't identities (items are pushed on top, and at 100, probed on 2.1.24 and not in the API docs, the oldest drops).
- `get_undo_tag` on an out-of-range index raises, so call it in `pcall`.
- Hand mining makes its undo item only after `on_player_mined_entity`, so the settings wait for the next tick.
- Not handled: redo, and editor instant building.
- The mod's own entities and tiles are made and removed without `player` or `undo_index`, so they never reach an undo queue.
- Pressing undo can't be scripted (`game.simulation` is nil and `LuaUndoRedoStack` can't apply an item, probed on 2.1.24), so `on_undo_applied` is covered only by Lua checks and the graphical client.

## The depot panel

- `scripts/request-gui.lua`: a relative GUI on `container_gui` or `pipe_gui` (2.1 removed `storage_tank_gui`).
- `FluidPrototypeFilter` has no `is-parameter`; parameter fluids are left out by their `parameters` subgroup.
- A pipe window doesn't show the character inventory, so a liquid depot's panel adds the player's main inventory.
- The amount field isn't rewritten while typing (the next key would add to it).
- Every `logistics.status` needs an entry in `request_gui.lights` (`tests/lua/control-events.lua` checks).

## Debugging and tests

- `/jatz-freighters` explains a depot's freighter requests.
- Tests: `tests/lua/logistics.lua` and the files it runs, `depot-swap.lua`, `control-events.lua`; the check mod ([testing](../testing.md)).

## Known engine traps

- An open container window doesn't redraw requested-item ghosts for script changes; reopening it by script flashes, and the owner chose no flash.
- 2.1 removed `LuaEntity::fluidbox`: use `get_fluid(1)`, `get_fluid_capacity(1)`, `remove_fluid` and `insert_fluid`.
- `on_object_destroyed` comes at the end of the tick or the next; check entities valid before then.
- Lua 5.2 allows 200 active locals per function: read "Top-level locals" in [AGENTS.md](../../AGENTS.md) before adding any to `scripts/logistics.lua`.
