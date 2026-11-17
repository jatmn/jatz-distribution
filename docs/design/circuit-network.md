# Circuit network

Every depot takes red and green wires. Provider, request and buffer depots (item and liquid) also have an enable/disable circuit condition, like a logistic chest's: while it is ticked, the depot takes part in deliveries only while the condition holds. The road network monitor, a constant combinator built beside road, puts one reading of the depots on its road network on the wires, so depots can switch on what a whole network holds or needs.

This page covers how the condition is read, how it interacts with the promises freighters make at a provider, and how the monitor counts. For what players see, read the [player guide](../guide.md#circuit-network).

## Code

- `prototypes/depots.lua`: the depots' wire connectors and reach.
- `scripts/depot-circuit.lua`: conditions themselves: normalising one (`condition`), what it reads (`reads`), and whether it holds (`allows`).
- `scripts/circuit-switch.lua`: each depot's switching: its own signals (`own_signals`), the per-tick sample (`sample_circuits`), `enabled`, `holds_less`, `claims_ahead`, the switched-off status, `get_circuit` and `set_circuit`. `scripts/logistics.lua` re-exports these as `logistics.*`.
- `scripts/logistics.lua`: where the condition gates deliveries: `dispatch`, `suppliers`, `finish_search`, `honoured`, `keep_promises`, `give_up`, `reroute` and `home_empty`.
- `scripts/request-gui.lua`: the condition section at the bottom of every delivery depot's panel.
- `scripts/blueprints.lua`: the `jatz_circuit` blueprint tag, Copy and Paste settings and clones (`copy_request`).
- `prototypes/road-monitor.lua`, `prototypes/road-monitor-points.lua`: the road network monitor's prototype.
- `scripts/road-monitor.lua`, `scripts/road-monitor-gui.lua`: the monitor's readings and its panel.
- `control.lua`: `on_tick` (the sample), `on_nth_tick` (the monitors' update) and the paste and clone events.

## Wire connectors

- Every depot has a four-direction `circuit_connector` and the base game's wire reach (`default_circuit_wire_max_distance`).
- Liquid depots have the connector where a 3x3 assembling machine has it (`CIRCUIT_CONNECTOR`).
- Item depots and the Fuel depot (the roles in `orientation.half_turn`) would have it on the edge of their loading opening when they face south (the owner, November 5, 2026). So theirs (`PILLAR_CONNECTOR`, `util.by_pixel(37, 31)`) sits on the right-hand pillar below the painted band, which is in the same place in all four of their views.
- Engine trap: a container with `direction_count = 4` needs one connector per direction, so the steel chest's single connector can't be reused.
- The hidden storage tank under a Fuel depot has no connector (`footprint()` clears it).

## The enable/disable condition

### Which depots have one

Every delivery depot: any registered depot whose role is not `fuel` (`switching.delivery_depot`). That is the item and liquid provider, request and buffer depots, and a Mining Drones mining depot ([compatibility](compatibility.md)). Fuel depots have none: freighters refuel there whatever its wires say.

The condition is modelled on 2.1's `LuaLogisticContainerControlBehavior.circuit_condition_enabled` and `circuit_condition`.

### The condition

`depot_circuit.condition` turns whatever it is given (the panel, a blueprint tag, another mod) into a well-formed CircuitCondition:

- An unknown signal is dropped.
- "Each" is dropped as the first signal, and "Everything", "Anything" and "Each" as the second signal.
- An unknown comparator becomes `<`. `>=`, `<=` and `!=` are stored as `≥`, `≤` and `≠`, as the game writes them back.
- The constant is floored and clamped to a signed 32-bit integer.

`allows` reads it as the game's own conditions do:

- No first signal never holds.
- "Everything" holds when every signal does (so also with none); "Anything" when at least one does. A wildcard compared with a second signal leaves that signal out of its inputs.
- Red and green are added together, with the game's 32-bit wrap-around (`wrap`), before zeros are dropped and before anything is compared.

### Settings and where they are kept

- Stored on the depot record: `depot.circuit_enabled`, `depot.circuit_condition` and `depot.circuit_mode` (nil for "network").
- `set_circuit(entity, enabled, condition, mode)` and `get_circuit(entity)` set and read them, also through the remote interface. A nil condition or mode is left as it is. A condition that isn't a table, or an unknown mode, is refused (`false`, nothing changed). `get_circuit` returns `{ enabled, condition, mode, connected, fulfilled }`.
- The panel's bottom section: an "Enable/disable" checkbox, two radio buttons for the mode, the first signal, a comparator drop-down, a second signal or a constant, and a light. The light is green while the condition holds, red while it switches the depot off, and grey while it has no effect (not ticked, or reading the network with no wire).
- Copy and Paste settings and clones copy it between any two delivery depots, item and liquid alike (`copy_request`).
- Blueprints keep it as the `jatz_circuit` tag, `{ enabled, condition, mode }`, when any part is set. `mode` is present only for `"contents"`. Undoing a depot's removal brings it back with the other settings (`scripts/undo.lua`).
- On configuration changes (`logistics.add_all`), a stored condition is normalised again, so signals whose mod was removed drop out.

### What the condition gates

- `dispatch`: a request or buffer depot switched off sends nothing, drops any search under way and shows status `disabled` (red). Its trips already out finish.
- `suppliers`: a provider or buffer depot switched off is no source (`enabled(provider, true)`, see [Promises and the condition](#promises-and-the-condition)).
- `finish_search`: the provider found must still be switched on, and so must the searching depot.
- While the condition switches a depot off, its hover panel shows `jatz-circuit-status.entity-off` ("Switched off by its circuit condition") with a red light, through `LuaEntity.custom_status`. It is written only when it changes (`depot.shown_off`), at the depot's once-a-second check and by `set_circuit`. Setting nil gives the entity its own status back.

## Two modes

What the condition reads is `depot.circuit_mode` (the owner's request, November 5, 2026: a depot's own stock must not count when it reads another depot's):

| Mode | Stored as | Reads | Without a wire |
| --- | --- | --- | --- |
| "Circuit network" (`network`, the default) | nil | Red and green, through `get_circuit_network` and `LuaCircuitNetwork.get_signal`/`signals`, less the depot's own share on each wire | No effect, as with the game's entities |
| "This depot's contents" (`contents`) | `"contents"` | What the depot holds (`own_signals`): items by quality, fluids floored, as a container or tank sends them | Works; no wire needed |

### Leaving the depot's own share out

Logistic chests, inserters and assembling machines would read their own output back; the game gives them a read toggle instead. 2.1 has no API for one entity's share of a network. So "network" mode subtracts, per wire (`external` in `scripts/depot-circuit.lua`):

- What the depot sends itself (`sent`), only on the colours its `output_networks` allows:
  - a `container` or `logistic_container` control behavior with `read_contents`: its contents;
  - a `single_fluid_box` set to `send_contents`: its fluid; set to `send_segment_contents`: its pipe segment's fluid (`get_fluid_segment_fluid`).
  - Other kinds, such as a mining depot's assembling machine, aren't worked out: nothing is subtracted.
- What road network monitors on that network counted for it (`road_monitor.counted`, through the `logistics.monitor_counts` hook).

Engine facts, probed on 2.1.24:

- A depot's control behavior exists once it is wired, and it reads or sends its contents by default.
- A tank's fluid goes out floored.
- A wire carries what each entity sent at the previous tick's circuit update. A transfer earlier in the same tick is not on it yet: 700 wood taken out of 1000 still read 1000 (Pullfrog's review of 08bed57).

### The per-tick sample

So what a depot takes back out must be its contents as they were at the start of the tick, not live:

- `control.lua`'s `on_tick` runs `logistics.sample_circuits` near the start (only `failed_commands` runs before it). The game raises `on_tick` before `on_nth_tick` and the entity updates.
- It samples only the depots in `storage.circuit_watch`: those with the condition ticked and reading the network. `set_circuit` keeps that list (`watch`), and so does `add_all` on configuration changes.
- The sample goes into `depot.circuit_sample` (`{ tick, sent, segment }`) and is used all that tick. A depot not sampled this tick (its condition was just set) uses its live contents.
- Known limitation: changes applied before any mod's `on_tick` (a player's own transfers), or by mods running earlier in the tick, are already in the sample for that one tick.

## Promises and the condition

A request depot's freighter promises what it will load at its provider (see [Roads and deliveries](roads-and-deliveries.md) for `available`, `storage.promised` and `storage.promise_totals`). A provider's condition must keep working while those loads are on their way.

### A contents-mode source

A provider or buffer depot reading its own contents is a source only if its condition holds both now and with every promise there taken (`enabled(depot, true)`, asked in `suppliers` and `finish_search`). Once the freighters already sent would take it below its condition, no more go.

- Both checks, never the second alone: a condition that taking items switches on (fetch only below 100, say) can hold with promises taken while the depot is off now (Copilot's review of 712a2fd).
- `true` means every promise there, from `claims_ahead` without a trip: an item depot's kept totals (`storage.promise_totals`, exact for items, read and never changed), a liquid depot's added up afresh.
- `holds_less` takes a fluid's promises from its exact amount and floors once, since promises can be fractions.
- In "network" mode the depot's own contents are left out, so promises don't change the answer.
- The depot's status, its panel and the road network monitors read what it holds now, without promises.

### Promise order

A provider or buffer depot keeps its promises in the order they were made there:

- `trip.queued`, numbered by `logistics.queue_place()` (`storage.promise_order`) when a trip sets off and again when a reroute files its promise at a new provider, so a rerouted trip joins the end.
- `logistics.ahead(key, trip)` compares them. Trips from before the order have none and come first; the trip key breaks ties.

### On arrival: `honoured`

A freighter arriving to load (`arrived_at_provider`) asks `logistics.honoured(trip)` what it may still load, but only while its depot still has room; with no room it loads nothing and goes home.

- Switched off now: nothing, whatever the promises.
- Fast path: while the provider's stock covers every promise there (`storage.promise_totals`), the order is not asked. The trip may load all it promised. A contents-mode condition is then decided with every other promise taken, when one comparison of the item's signal with a constant reads it and the comparator isn't `=` or `≠`. Each other comparison only turns one way as stock goes, so holding now and with more than the promises ahead taken, it holds with those ahead taken.
- Otherwise it adds up the promises ahead of the trip's own, of its item. It needs every item's (`claims_ahead(provider, trip)`) only when the condition reads more than that item's signal (`depot_circuit.reads`).
- The answer is the stock less the promises ahead, while that is above 0 and the condition holds with those taken; otherwise false. A trip covered only in part loads that much (its depot sends for the rest). So a later trip arriving first never takes an earlier one's stock.
- A trip planning several qualities treats each quality as its own stock and queue (`honoured` with `trip.mix`; `honoured_one` for a single key). See [Quality](quality.md).
- Why the shortcuts: many freighters arriving at a busy provider together cost the square of its promises. 800 arrivals in one tick took 320,400 order comparisons (Pullfrog's review of feca8c7); scanning every item's promises for each did the same (Sourcery's review of 2559152).

### At the provider's check: `keep_promises`

At a provider or buffer depot's once-a-second check, freighters on their way that it no longer has a load for (a condition switched off, stock taken out by an inserter or a player) are rerouted at once, rather than finding out on arrival (the owner's report, November 7, 2026: freighters all sent to a provider just switched on above its minimum).

- It returns at once unless a contents-mode condition is in effect, a network-mode condition doesn't hold, or the stock no longer covers what was promised.
- Otherwise it walks the promises once, in queue order, adding up the promises ahead as it goes: `honoured`'s rule for every trip without adding them up afresh for each. Per trip, that took tens of milliseconds for a provider with hundreds of promises (Pullfrog's review of 712a2fd).
- A trip with only part of its load left promises that part (its depot sends for the rest).
- Every trip is decided first. Then those failing let their promises go, `logistics.look_afresh()` drops the shared look at the suppliers, and only then do they start their searches, so each search sees this provider's promises as they end up (Sourcery's review of ac9ab0a).
- A promise made smaller also calls `look_afresh()`, since what the provider has unpromised and what its condition reads change (Sourcery's review of 2559152).
- `check_depot` reads a contents-mode depot's own contents once, for its status and this walk: each read builds a signal for every item it holds.

### Giving up on a provider

A trip whose provider no longer has a load for it goes through `logistics.give_up`, from `keep_promises` or `arrived_at_provider`:

- It sets `trip.passed` to that provider and drops the trip's promise there at once (`promise` files none while `passed` is set), so others can have the stock during the search.
- The search leaves that provider out (`candidates(..., passed)`). Otherwise a condition that taking items switches on would pass for the trip and find the same provider every second. `passed` is cleared when the reroute finds a provider or the trip goes home.
- `reroute` searches only while the trip's depot still has room for what it would bring (`need`, counting its other freighters), and for a full load if it sends full loads only. `finish_search` sends it on only if the room is still there. A depot filled meanwhile, by hand or otherwise, gets the freighter home through `home_empty` rather than a farther drive to load nothing (Copilot's review of 86332ce).
- A trip is sent to another provider only once (`trip.diverted`, set by `finish_search` when a reroute finds one, whatever started it: a provider removed or one given up on). `reroute` sends a diverted trip home. No going back and forth (the owner, November 7, 2026); a removed provider's reroute counts too (Sourcery's review of ac9ab0a).
- A reroute that finds a provider promises no more than its depot still has room for and the new provider has unpromised.
- A reroute of a freighter already destroyed, its `on_object_destroyed` still to come, hands it to `on_object_destroyed` there and then, so it is lost. Ended as a trip, its truck would go back into the slot for free (Pullfrog's review of e949b72).
- `home_empty` sets off with `set_off` like any leg, by a Fuel depot if short of fuel, sized as far by road as it came (`trip.leg`) and never less than the straight line. A freighter still at home (`trip.movement == "departing"`) parks there and then (`end_trip`).

## Road network monitor

### Prototype

- `jatz-road-monitor` (`prototypes/road-monitor.lua`) is a copy of the constant combinator with our own 1×1 model in the liquid depots' grey and bronze finish (the owner, November 5, 2026). Base graphics can't be recoloured to it, as tints only multiply channels, and copies of them may not be committed.
- The art is in `assets/depots/road-monitor/1/`, built, rendered and packaged with the depots ([assets/depots/README.md](../../assets/depots/README.md)). The mod draws its `preview` and `shadow` sheets.
- Its wire points, their shadows and the base game's activity glow sit on its posts and lens, at the points in `prototypes/road-monitor-points.lua`, copied from its `asset.json`; `tools/test_mod_setup.py` checks the copy.
- Its icon is the model facing north with the road icon in its corner (`tools/make_icons.py`).
- It has no fast replaceable group and no `next_upgrade`, so it is never swapped for a constant combinator.
- Like every building it collides with road (`prototypes/off-road.lua`), so it is built beside road, never on it.
- Research and recipe: [Research and recipes](research-and-recipes.md).

### Readings

Once a second (`road_monitor.update`, from `control.lua`'s `on_nth_tick(logistics.dispatch_interval)`) a monitor outputs one reading (the owner's request, November 5, 2026, so a condition reads one thing at a time). It is stored as `monitor.reading` in `storage.road_monitors`, nil for the default.

| Reading | Counts |
| --- | --- |
| `supply` (default) | What provider and buffer depots hold |
| `providers` | What provider depots hold |
| `requests` | What request depots hold, item and liquid, never buffer depots. A liquid request depot's `depot.reserve` (fluid waiting in its parked freighters) is added to its tank's before flooring |
| `needs` | What request depots still need (`logistics.missing`: the request less what is held and coming, none for a depot marked for deconstruction), as a signal of the quality the request names (normal for any quality), fluids floored |

- Only enabled depots of the monitor's own force count. The force is checked at each read, so `game.merge_forces` and scripted force changes count at once.
- Holdings count items by quality, read with `logistics.inventory` (so a mining depot's output counts), and fluids floored per depot. Totals are clamped to the 32-bit maximum and go out in sections of 1000 signals.
- Freighters on the road are not counted.
- The monitor owns its whole output (`show`). Copy and Paste settings from a constant combinator, or a blueprint, brings that combinator's state with it (probed on 2.1.24): its on/off switch, and sections with a multiplier, switched off, or in a named logistic group, whose filters every member shares. So it switches itself on and makes each section leave its group, active, with multiplier 1, before writing its filters.

### Its road network

- A depot is on a monitor's network when its loading zone tile is.
- The network is found with `LuaSurface.get_connected_tiles` over `jatz-road` and `jatz-depot-road`, from the four tiles beside the monitor and its own tile (for a monitor a script put on road).
- It is found again only for surfaces marked changed (`road_monitor.changed`, `storage.road_monitor_dirty`): road laid or removed, depots built, turned, cloned or removed, monitors built or cloned.

### What it counted

A depot reading the network leaves out exactly its own share, so each monitor remembers what it counted for each depot:

- `counted`, and `previous` with `counted_tick`: a combinator's output reaches the wire a tick later, so in the tick it changes its signals they still show what it counted before.
- That holds only while its signals are always what it counted. So a new monitor (`road_monitor.add`) shows its own reading at once, empty until its road is worked out. A clone keeps the original's signals and a blueprint a combinator's, which it never counted (Pullfrog's review of 99acef3).
- `road_monitor.replaced` moves its members and counts to a depot's new unit number when the depot is replaced ([Logistic robots and replacing depots](depots-robots-and-replacing.md)).

### Panel and settings

- Opening a monitor shows its own panel (`scripts/road-monitor-gui.lua`): four radio buttons in a centred screen frame, made the player's `opened`, which closes the combinator's own window, so its signals can't be edited. `road_monitor.add` makes the monitor operable for this.
- `scripts/request-gui.lua` passes the panel its opened, closed and checked events (one handler per event in `control.lua`).
- The reading is kept by Copy and Paste settings between monitors (`road_monitor.on_settings_pasted`, which also takes the output back after a paste from any constant combinator), clones, blueprints (the `jatz_monitor_reading` tag when not the default, through the `logistics.monitor_tag` hook), undo of its removal (`scripts/undo.lua`), and the remote interface (`set_monitor_reading`/`get_monitor_reading`, added through `logistics.remote_extra`).

## Tests

- `tests/lua/logistics.lua`: conditions read straight from `depot_circuit.allows`; providers and request depots switched off; a network-mode depot leaving out what it sends; the cost of `keep_promises`, arrivals and searches at a provider with 100 and 400 promises.
- `tests/lua/control-events.lua`: the panel's condition section and the road network monitor.
- The check mod (`tests/factorio/jatz-distribution-check_0.1.0/control.lua`), on the real engine: conditions in both modes, the monitors' readings, a paste from a grouped constant combinator, a force merge, wood taken out after the sample, and a cloned monitor.
