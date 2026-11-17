# Circuit network

Every depot takes red and green wires. Provider, request and buffer depots also have an enable/disable condition, like a logistic chest's. The road network monitor puts one reading of the depots on its road network on the wires. Player view: [player guide](../guide.md).

## Code

- `prototypes/depots.lua`: the wire connectors.
- `scripts/depot-circuit.lua`: conditions (`condition`, `reads`, `allows`) and the depot's own share (`external`).
- `scripts/circuit-switch.lua`: each depot's switching, the per-tick sample, `get_circuit` and `set_circuit`.
- `scripts/logistics.lua`: gating deliveries and promises.
- `scripts/request-gui.lua`, `scripts/blueprints.lua`: the panel section; tag, paste and clones.
- `prototypes/road-monitor*.lua`, `scripts/road-monitor*.lua`: the road network monitor.

## Wire connectors

- Item and Fuel depots' connector (`PILLAR_CONNECTOR`) sits on the right-hand pillar below the painted band, not on the loading opening's edge (the owner, November 5, 2026).
- Engine trap: a container with `direction_count = 4` needs one connector per direction, so the steel chest's single connector can't be reused.
- The hidden storage tank under a Fuel depot has no connector.

## The enable/disable condition

- Every delivery depot has one (role not `fuel`), including a Mining Drones mining depot ([compatibility](compatibility.md)). Fuel depots have none: freighters refuel there whatever its wires say.
- `depot_circuit.condition` normalises any condition (panel, blueprint tag, another mod); `allows` reads it as the game's own conditions do. Red and green are added with 32-bit wrap-around before anything is compared.
- Configuration changes normalise stored conditions again, so removed mods' signals drop out.
- Switched off, a depot sends nothing (trips out finish) and is no source.

## Two modes

The owner's request, November 5, 2026: a depot's own stock must not count when it reads another depot's.

- "Circuit network" (the default, stored as nil): red and green less the depot's own share. Without a wire it has no effect, as with the game's entities.
- "This depot's contents": what the depot holds, as a container or tank sends it. No wire needed.

### Leaving the depot's own share out

The game gives chests a read toggle; 2.1 has no API for one entity's share of a network, so "network" mode subtracts, per wire (`external`):

- what the depot sends itself, only on the colours its `output_networks` allows (a container's contents, a tank's fluid or its pipe segment's fluid). Other kinds, such as a mining depot's assembling machine, aren't worked out: nothing is subtracted.
- what road network monitors on that network counted for it.

Engine facts, probed on 2.1.24:

- A depot's control behavior exists once it is wired, and it reads or sends its contents by default.
- A tank's fluid goes out floored.
- A wire carries what each entity sent at the previous tick's circuit update. A transfer earlier in the same tick is not on it yet.

### The per-tick sample

So what a depot takes back out must be its contents at the start of the tick. `on_tick` runs `logistics.sample_circuits` near its start (only `failed_commands` before it), for the depots in `storage.circuit_watch` (ticked and reading the network). A depot not sampled this tick reads live.

Known limitation: changes applied before any mod's `on_tick` (a player's own transfers), or by mods running earlier in the tick, are already in the sample for that tick.

## Promises and the condition

Freighters promise what they will load at a provider ([roads and deliveries](roads-and-deliveries.md)); its condition must keep working while they are on their way.

- A contents-mode provider or buffer depot is a source only if its condition holds both now and with every promise there taken (`enabled(depot, true)`). Both checks, never the second alone: a condition that taking items switches on can hold with promises taken while the depot is off now.
- A provider keeps its promises in the order they were made (`trip.queued`); a rerouted trip joins the end.
- On arrival, `honoured` gives a trip the stock less the promises ahead, while that is above 0 and the condition holds with those taken; nothing while switched off. So a later trip arriving first never takes an earlier one's stock; its fast paths avoid a cost quadratic in promises.
- At a provider's once-a-second check, `keep_promises` reroutes freighters it no longer has a load for at once, rather than on arrival (the owner's report, November 7, 2026). It walks the promises once, in order. Every trip is decided first; only then do failing trips let their promises go, `look_afresh()` runs, and their searches start.
- `give_up` sets `trip.passed` and drops the promise; the search leaves that provider out, or a condition that taking items switches on would find it again every second.
- A trip is sent to another provider only once (`trip.diverted`), whatever started the reroute; a diverted trip goes home. No going back and forth (the owner, November 7, 2026).
- A reroute of a freighter already destroyed, its `on_object_destroyed` still to come, hands it to `on_object_destroyed` at once. Ended as a trip, its truck would go back into the slot for free.

## Road network monitor

- `jatz-road-monitor` is a copy of the constant combinator with our own model in the liquid depots' finish (the owner, November 5, 2026). Base graphics can't be recoloured to it (tints only multiply channels), and copies of them may not be committed. Art: [assets/depots/README.md](../../assets/depots/README.md).
- No fast replaceable group and no `next_upgrade`, so it is never swapped for a constant combinator. It collides with road, so it is built beside it. Research: [research and recipes](research-and-recipes.md).
- It outputs one reading (the owner's request, November 5, 2026): `supply` (default), `providers`, `requests` or `needs`.
- Only enabled depots of its own force count, checked at each read. Freighters on the road are not counted.
- A depot is on its network when its loading zone tile is on the monitor's road; that is found again only for surfaces marked changed.
- It owns its whole output. Copy and Paste settings from a constant combinator, or a blueprint, brings that combinator's on/off switch and sections with it (probed on 2.1.24), so it resets them before writing its filters.
- A combinator's output reaches the wire a tick later, so a monitor remembers what it counted for each depot, now and the tick before. That holds only while its signals are always what it counted, so a new monitor (a clone or blueprint too) shows its own reading at once.
- Its own panel replaces the combinator's window, so its signals can't be edited.
- A replaced depot's counts move with `road_monitor.replaced` ([logistic robots and replacing depots](depots-robots-and-replacing.md)).

## Tests

`tests/lua/logistics.lua`, `tests/lua/control-events.lua` and the check mod; see [testing](../testing.md).
