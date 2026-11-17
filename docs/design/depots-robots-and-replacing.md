# Logistic robots and replacing depots

Item provider and buffer depots are logistic containers, so logistic robots can use them as passive provider and buffer chests, but only while the depot lets them. Item request and buffer depots replace each other in place, as Factorio's chests do. Both features create a new entity with a new unit number where a depot stood, so both rely on one routine, `logistics.replaced`, to carry the depot's settings, freighters and trips over to it.

A depot replaced by itself at another quality uses the same routine; that path is in `scripts/depot-upgrades.lua` and described in [Quality](quality.md).

## Code

- `prototypes/depots.lua`: `LOGISTIC_MODES` (the logistic containers), the hidden `-legacy` containers, `FAST_REPLACEABLE`, and `footprint()`.
- `scripts/robot-access.lua`: whether robots may use a depot.
- `migrations/2026-11-07-logistic-depots.json` and `scripts/legacy-depots.lua`: depots from before they were logistic containers.
- `scripts/depot-swap.lua`: request and buffer depots replacing each other, and its undo and redo.
- `scripts/logistics.lua`: `logistics.replaced` (moves everything kept by the old unit number), and `logistics.add` (robots off on every new depot).
- `scripts/depot-road.lua` (`depot_road.replaced`) and `scripts/road-monitor.lua` (`road_monitor.replaced`): the same move for the depot road and the monitors.
- `scripts/request-gui.lua` (the checkbox) and `scripts/blueprints.lua` (the tag, Copy and Paste settings, clones).
- `scripts/undo.lua`: undo of a removal that names a legacy depot.
- `control.lua`: the order of the build, mined, destroy and undo handlers.

## Logistic robots

The owner's request, November 7, 2026; off by default (the owner's choice).

- Item provider and buffer depots are `logistic-container`s with `logistic_mode` `passive-provider` and `buffer`. `render_not_in_network_icon = false`, since most depots are off the network.
- The setting is the depot's logistic points' `enabled` (`LuaLogisticPoint::enabled`, read and write in 2.1, saved by the game). A disabled point is out of the network, so robots neither take from it nor bring it anything (probed on 2.1.24). `robot_access.set` writes both of a buffer depot's points.
- `logistics.add` turns it off for every new depot.
- It is set by:
  - the panel's "Logistic robots can use it" checkbox, under the priority slider;
  - Copy and Paste settings and clones, between provider and buffer depots (`copy_request`);
  - blueprints and undo, as the `jatz_robot_access` tag, written only when on;
  - the remote interface (`set_robot_access`/`get_robot_access`).
- Engine trap: the game's own logistic container circuit condition ("Enable/disable" in the depot's circuit settings, which 2.1 gives logistic containers) writes the same `enabled` at every update while it is on (probed on 2.1.24), overriding the setting. So while it is on, the checkbox is greyed out and shows what the condition makes it (`robot_access.circuit_controlled`).
- A buffer depot's own logistic requests (the logistic sections in its window) are the game's. Freighters still keep its mod request stocked.
- `depot_circuit`'s `sent` reads a `logistic_container` control behavior as a container's ([Circuit network](circuit-network.md)).

## Depots from before they were logistic containers

Item provider and buffer depots were `container`s before. Engine trap: Factorio rebuilds an entity whose prototype changed type facing north with a new unit number, removes its ghosts, and forgets its direction in blueprints (probed on 2.1.24).

So the depots are never retyped in place:

- `migrations/2026-11-07-logistic-depots.json` renames them, in saves, ghosts and blueprints, to `jatz-provider-depot-legacy` and `jatz-buffer-depot-legacy`. These are the hidden containers they were (copied in `prototypes/depots.lua` before the depot becomes a logistic container), placeable by the depot's item; without that, the rename would drop ghosts and blueprint entries too.
- `scripts/legacy-depots.lua` replaces each with the depot:
  - every one in the game first thing on configuration changes (`control.lua`'s `setup`, before `logistics.init`);
  - a ghost of one as it is placed (an old blueprint), and one as it is built (`control.lua`'s `on_built`, before anything else sees it).
- The new depot or ghost stands where the old one stood, facing and flipped the same, with its force, quality and last user. It is made without `player`, which would put it on that player's undo queue; `last_user` is set after.
- Both keep their wires and chest settings (`chest_settings`: the inventory limit and the circuit reading, `read_contents`, `read_empty_slots`, `empty_slots_signal` and `output_networks`, nil values too).
- A depot also keeps its health, contents (moved stack by stack, so item data stays) and deconstruction mark. A ghost keeps its tags and insert plan.
- `logistics.replaced`, `depot_road.replaced` and `road_monitor.replaced` then move everything kept by the old unit number ([below](#what-logisticsreplaced-moves)). Robot access starts off.
- `undo.on_undo_applied` also looks for the depot's ghost when an undo action names a legacy depot.

Not handled:

- A deconstruction mark from before is made again for the force, so its player's undo action no longer finds it.
- Undoing the paste or build of a blueprint from before finds the legacy ghost or depot gone, since the replacement is made without `player`.
- A legacy blueprint's parametrised request settings name the depot's old blueprint entry, so they apply only if the depot's ghost was replaced before their build event. Its own tags still carry its request.

## Replacing request and buffer depots

The owner's request, November 14, 2026: as Factorio's chests do.

### Prototypes

- The item request and buffer depots share the fast replaceable group `jatz-cargo-depot` (`FAST_REPLACEABLE`). `footprint()` clears the group for every other depot, and the legacy containers are copied before it is set.
- So a player can place one over the other. A ghost placed over one, a blueprint pasted over it super-forced, or an upgrade planner mapping one to the other marks it for upgrade for robots. (A blueprint pasted normally or forced doesn't replace it.)
- There is no `next_upgrade`: the group is what lets the upgrade planner map them. A swap is no upgrade tier, and with a `next_upgrade` a blank planner would flip every depot.
- The game moves the chest's contents and wires. The new entity has a new unit number.

### Events, probed on 2.1.24

All within one tick, with `on_object_destroyed` for the old depot at its end:

| Who | Events |
| --- | --- |
| A player | `on_pre_build` (old depot still standing, contents in it), `on_pre_player_mined_item` and `on_player_mined_entity` (contents already moved), then `on_built_entity` |
| Robots | `on_robot_mined_entity` (old depot still `to_be_upgraded()` to the other), then `on_robot_built_entity` |
| A script's `LuaEntity.apply_upgrade` (Blueprint Sandboxes carries out upgrade orders this way in its labs) | `script_raised_destroy` (old depot still marked), then `script_raised_built` |

### How `scripts/depot-swap.lua` carries the depot over

- `on_pre_build` notes the depot under a player's hand (`storage.depot_swap_hands`).
- `replacing`, from `control.lua`'s mined handlers, recognises the replacement (the noted depot, or one marked for upgrade to the other) and tells them not to hand its freighters to the miner. It keeps a note in `storage.depot_swaps` for that tick.
- `destroying`, from `control.lua`'s `script_raised_destroy` handler, does the same for `apply_upgrade`. The freighters still in the old depot's chest are moved aside into a script inventory on the note, instead of being left on the ground.
- `built`, from `control.lua`'s `on_built` (before `settle` and `logistics.add`), finds the note for the same spot and name this tick:
  - it puts any freighters kept aside into the new depot's chest;
  - it moves everything the old unit number kept to the new one, as `scripts/legacy-depots.lua` does (`logistics.replaced`, `depot_road.replaced`, `road_monitor.replaced`); `settle` then moves the depot road if the depot was turned;
  - it keeps robots out of a new buffer depot.
- `gone`, from `on_object_destroyed`: when a script destroyed a marked depot outright and nothing replaced it, the freighters kept aside are left on the ground where it stood. Notes from earlier ticks are dropped the same way at the next `built`.

### What `logistics.replaced` moves

- The depot record and its index entry, now under the new entity's role. A depot that became a request depot supplies no one; one that became a buffer depot supplies and fetches.
- Cooldowns other depots hold for it.
- Trips' `request`, `provider`, `refuel` and `passed`, and where each trip's promise is filed (`trip.promise.provider`).
- The `storage.promised`, `storage.promise_totals`, `storage.coming`, `storage.spoiling` and `storage.circuit_watch` entries.
- Its request, capped at what the new chest or tank holds (`request_limit`, as `set_request` does). Request and buffer chest slots are separate startup settings, and a lower quality's chest is smaller.
- It forgets the old entity's inventory, custom status and Fuel depot tank grade, and plans the second's depot checks afresh.

Freighters already sent finish their trips as they were sent. A buffer pull whose source has become a request depot takes nothing there (`arrived_at_provider`).

### Undo and redo

- Robots' replacements are undo actions of type `upgraded-entity` (with `original_name`), undone and redone as upgrade orders. Robots swap the depot back through the same path.
- A player's replacement by hand is one undo item: the old depot's `removed-entity` and the new one's `built-entity` (probed on 2.1.24). Undoing it would mark the new depot for deconstruction under a ghost of the old one, so robots would empty and take it, and build a bare depot.
- So `on_undo_applied` (after `undo.on_undo_applied`) and `on_redo_applied` call `swap.on_undo_applied`. For an item removing one of the pair and building the other at one spot, it finds that depot marked under the other's ghost and:
  - cancels the deconstruction and removes the ghost;
  - turns the depot to the ghost's facing, as a player turning it would (`control.lua`'s `on_turned`: its road, loading zone and trips follow), since `order_upgrade` takes no direction and an upgrade keeps the standing depot's;
  - calls `order_upgrade` to the other at the ghost's quality (the depot the undo or redo restores), without `player`, which would add to the undo queue.
- Robots then swap it in place (probed: request, freighters and chest kept).
- Unverified: no script call applies undo, so the undo item's effect itself is inferred from its actions and the game's ghost rules. It needs a check in the graphical client.

## Tests

- `tests/lua/logistics.lua`: `logistics.replaced` with a trip on the road (legacy depots).
- `tests/lua/depot-swap.lua` (on the fake runtime in `tests/lua/harness.lua`, split out of `tests/lua/logistics.lua` to stay under CI's 256 KiB text limit): the role change, promises of freighters on their way to load at a swapped depot, buffer pulls and reroutes across a swap, and the request cap.
- `tests/lua/control-events.lua`: the swap events, and the undo and redo conversion.
- The check mod's `setup_robot_access` (`tests/factorio/jatz-distribution-check_0.1.0/control.lua`): robots taking from a provider depot let in, not from one left as built, and from a buffer depot let in; the tag through a blueprint; a legacy depot and ghost built by script, with their facing, tags and chest settings.
- The check mod's main run: a request depot with a freighter out is upgraded to a buffer depot by `apply_upgrade` and its pickup still arrives.
- The check mod's `scenarios/undo`, which has a player: a request depot replaced by a buffer depot by hand; a buffer depot by a request depot from a ghost robots build; a request depot by a buffer depot from an upgrade planner; one upgraded at once by `apply_upgrade`, freighters in its chest too; and one marked for that upgrade but destroyed outright by a script, which leaves all its freighters on the ground.
- A save from before logistic depots, loaded into the change, was checked by hand once (directions, contents, wires, settings and a trip on the road kept).
