# Logistic robots and replacing depots

Item provider and buffer depots are logistic containers that robots may use, but only while the depot lets them. Item request and buffer depots replace each other in place, as Factorio's chests do. Both create a new entity with a new unit number, so both rely on `logistics.replaced` (with `depot_road.replaced` and `road_monitor.replaced`) to move what the old unit number kept. Replacement by the same depot at another quality: [quality](quality.md).

## Code

- `prototypes/depots.lua`: `LOGISTIC_MODES`, the `-legacy` containers, `FAST_REPLACEABLE`, `footprint()`.
- `scripts/robot-access.lua`: robot access.
- `migrations/2026-11-07-logistic-depots.json`, `scripts/legacy-depots.lua`: depots from before.
- `scripts/depot-swap.lua`: request and buffer depots replacing each other, with undo and redo.
- `scripts/logistics.lua`: `logistics.replaced`; `logistics.add` turns robots off on every new depot.

## Logistic robots

The owner's request, November 7, 2026; off by default (the owner's choice).

- The setting is the depot's logistic points' `enabled`. A disabled point is out of the network: robots neither take from it nor bring it anything (probed on 2.1.24). A buffer depot has two points; write both.
- Engine trap: the game's own logistic container circuit condition writes the same `enabled` at every update while it is on (probed on 2.1.24). So while it is on, the checkbox is greyed out and shows what the condition makes it.

## Depots from before they were logistic containers

Engine trap: Factorio rebuilds an entity whose prototype changed type facing north with a new unit number, removes its ghosts, and forgets its direction in blueprints (probed on 2.1.24). So depots are never retyped in place:

- The migration renames old ones, in saves, ghosts and blueprints, to hidden `-legacy` containers placeable by the depot's item; without that, the rename would drop ghosts and blueprint entries.
- `scripts/legacy-depots.lua` replaces each with the depot on configuration changes, and legacy ghosts and builds as they appear. The replacement is made without `player`, which would put it on that player's undo queue.

Not handled:

- A deconstruction mark from before is made again for the force, so its player's undo action no longer finds it.
- Undoing the paste or build of an old blueprint finds the legacy ghost or depot gone.
- A legacy blueprint's parametrised request settings apply only if the depot's ghost was replaced before their build event.

## Replacing request and buffer depots

The owner's request, November 14, 2026.

- The two share the fast replaceable group `jatz-cargo-depot`; `footprint()` clears it for every other depot.
- There is no `next_upgrade`: a swap is no upgrade tier, and with one a blank upgrade planner would flip every depot.
- A player's swap, a robot's and a script's `apply_upgrade` (Blueprint Sandboxes' labs) raise different events within one tick (probed on 2.1.24). `scripts/depot-swap.lua` notes the replacement so the mined handlers don't hand its freighters to the miner, then moves everything to the new depot when it is built.
- A depot destroyed outright by a script while marked leaves its freighters on the ground.
- `logistics.replaced` caps the request at what the new chest or tank holds, since chest slots differ by depot and quality. The depot record moves under the new role: a new request depot supplies no one. Freighters already sent finish their trips as sent; a buffer pull whose source became a request depot takes nothing there.

### Undo and redo

- A player's swap by hand is one undo item (`removed-entity` plus `built-entity`, probed on 2.1.24). Undone as is, robots would empty and take the new depot and build a bare one. So `swap.on_undo_applied` cancels that deconstruction, removes the ghost, turns the depot to the ghost's facing and orders an upgrade (without `player`), so robots swap it in place.
- Unverified: no script call applies undo, so the undo item's effect is inferred. It needs a check in the graphical client.

## Tests

`tests/lua/logistics.lua`, `tests/lua/depot-swap.lua`, `tests/lua/control-events.lua`, and the check mod with its `scenarios/undo`; see [testing](../testing.md).
