# Road tunnels

Freighters can't drive over the factory, so they go under it (the owner's request, November 8, 2026). Factorio's elevated rails are for rolling stock only, and units have no height, so a tunnel is a pair of portals, like underground belts. A freighter drives to one portal's mouth, disappears for as long as the tunnel takes to drive, and comes out of the other.

The engine's pathfinder knows nothing of tunnels. The mod works out which road network each point is on and the shortest way through any number of tunnels, and the pathfinder still drives every road leg.

## Code

- `prototypes/road-tunnel.lua`: the portal entity, its item and recipe.
- `prototypes/constants.lua`: `road_tunnel` (`jatz-road-tunnel`), `tunnel_reach`, `tunnel_technology_icon`.
- `prototypes/technologies.lua`, `scripts/research.lua`: the `jatz-road-tunnels` research.
- `prototypes/freighter-drone.lua`, `scripts/freighter-paint.lua`: the unseen freighter, `paint.underground`.
- `scripts/tunnels.lua`: portals, road networks, measured roads, `tunnels.plan`.
- `scripts/routes.lua`: `tunnels.ask` and passing the pathfinder's answers to `tunnels.answered`.
- `scripts/logistics.lua`: `drive`, `into_tunnel`, `out_of_tunnel`, `through_tunnel`, `route_answered`, `tunnels.resume`, `search_plan`, `on_roads_changed`.
- `scripts/trip-state.lua`: movement phases (`approaching-tunnel`, `entering-tunnel`, `waiting-at-tunnel`, `underground`, `exiting-tunnel`); see [runtime state](../runtime-state.md).
- `control.lua`: portal build, turn, clone and removal events (`tunnels_changed`), and tile events passed on to `roads_changed`.

## The portal

`jatz-road-tunnel` is a `pipe-to-ground`, one tile wide and two deep: a ramp going down from its mouth (the owner's choice, November 8, 2026).

- Its one pipe connection, on its back tile, is an `underground` connection in its own `connection_category` (the entity's name). The game pairs two portals facing each other (`LuaEntity::fluidbox_neighbours`), shows the reach while placing, and connects no pipe, from this or any other mod, to them. Nothing ever flows.
- The reach is `constants.tunnel_reach`, 19: back tiles at most 19 apart, so at most 18 tiles between (probed on 2.1.24). That is about twice Space Age's longest underground belt, with the ends meeting in the middle left out (the owner's choice, November 8, 2026).
- Its collision mask is the default pipe-to-ground mask plus `jatz_road`. `prototypes/off-road.lua` leaves pipes-to-ground alone, so the prototype adds the layer itself: a portal can't stand on road, and road can't be laid under it.
- Its mouth faces its direction (north unrotated; the underground connection runs south). The tile in front of the mouth is its entry (`tunnels.entry`: 1.5 tiles from the portal's centre, which lies between its two tiles). The entry must be road: a mouth off road is on no network, and no route goes through it. A chain of tunnels still missing its middle road joins nothing.
- A tunnel also goes under cliffs, which road can't be laid through (the owner's report, November 14, 2026; see [roads and deliveries](roads-and-deliveries.md)).

### Recipe and research

The recipe makes two portals, one for each end. It is 20 stone brick, 10 steel plate and 10 iron gear wheels, 10 s. The owner approved it with road tunnels; see [research and recipes](research-and-recipes.md).

`jatz-road-tunnels` research (after `jatz-freight-system` and `logistics`, 300 × red and green) unlocks it. It is not in `research.unlocks`, the list that saves from before research get unlocked, because no such save had tunnels. The check mod adds it to the research it unlocks.

### Art

The art is the mod's own (`assets/depots/road-tunnel/1/`, `build_depots.py --role road-tunnel --size 1`, rendered over 3.5 tiles, drawn at scale 0.21875). It is built like the item depots' loading side at its mouth, in their dark steel with the road monitor's grey housing and brown band. Its roof and walls slope down to the ground at the back, so it reads as a ramp going down (the owner, November 8, 2026: an arched hood read as a pipe on its side, then a box as a lift). Its icon and technology icon face south (`tools/make_icons.py`). [assets/depots/README.md](../../assets/depots/README.md) owns how it is built and rendered.

## Portals and road networks

`scripts/tunnels.lua` keeps:

| Storage | What it holds |
| --- | --- |
| `storage.tunnel_portals` | Portals by unit number, each with the surface noted at build (`on_object_destroyed` leaves only `valid`). |
| `storage.tunnel_surfaces` | How many portals each surface has. Nothing is worked out on a surface without one, and `drive` doesn't call the planner at all in a game without any. |
| `storage.tunnel_nets[surface]` | What is known of the surface's road networks: `made`, `stale`, `count`, `points` (tile key → network number, or false off road), `portals` (each paired portal once per end, with its `entry`, the `other` end's place and the `length` entry to entry), `floods` and `tiled`. |

### Flooding a network

`net_of` finds the network a point is on. Unknown, it floods once with `LuaSurface.get_connected_tiles` over both road tiles (`jatz-road`, `jatz-depot-road`), as the road monitor does. It notes the network of every portal entry and depot loading zone it reaches (`tunnels.zones`, set by `scripts/logistics.lua`), and of the point asked about.

Every flooded network is kept in `nets.floods` (its tiles by numeric key, in storage, so every player's game agrees) until it is forgotten. A flood of a 14,000-tile network takes 20 ms and more, so freighters planning from where they stand share one flood a network between them (a player's report, November 15, 2026).

A network keeps its number while that knowledge lasts. A flood takes the number of any point already remembered on it, and networks remembered apart that new road has joined become one under the lowest number. A fresh number each flood left earlier freighter positions on a network with no portals (Pullfrog's review of 4d4f64a).

### Road laid and removed

Tiles laid and removed are put on the known networks and taken off them, not flooded again (`tunnels.changed` with the event's tiles, `apply`). `control.lua` passes the tiles of player, robot, platform and script tile events, and the tile a depot lays its road on or lifts it from. Each tile is read from the surface as it is now, so what the event says of the old tile doesn't matter.

- One flood holds every tile of its network (`nets.tiled`), and stays so.
- A tile laid beside a flood joins it, with the tiles laid beside it in the same event. One laid between two floods makes them one, under the lower number.
- A tile removed leaves its flood. If its road neighbours don't all reach each other round it, through the eight tiles about it (`joined`), it may have cut the network in two. That flood is forgotten with its points, and flooded again when next asked about. Each removal in an event is judged in turn, with those before it gone.
- Road laid beside a known network and beside road never flooded joins it to something unknown, so everything known goes stale.

What is known is forgotten instead of updated:

- At once, when a portal is built, turned, cloned or removed (`tunnels.add`, `tunnels.removed`, `control.lua`'s `tunnels_changed`), and when road is removed with its tiles not known.
- At most once a second (`FORGET_TICKS`, 60) when road is laid with its tiles not known, since that comes in bursts and only joins networks. Until then a freighter may go through a tunnel where road now joins the two ends, which still gets it there.
- When an event has more than 1,000 tiles (`TILES_AT_ONCE`), or for a save whose networks are not `tiled`.

## Planning a way

A tunnel counts as road, with no penalty, even several in series (the owner, November 13 and 14, 2026: "There should never be a penalty for underground road path even multiple in series"). Before, tunnels were used only between networks the pathfinder couldn't join, so a road round a tunnel always won however long.

`tunnels.plan(surface_index, from, to, road, force, waiter)` finds the shortest way by road through any number of tunnels or none. It is a Dijkstra (`shortest`) whose states are `from`, `to`, and each portal's entry twice: come by road, and come out of its partner's tunnel.

- Only `from` and a tunnel's way out go on by road. Two roads one after the other are never shorter than the road from end to end.
- Tunnel edges weigh their entry-to-entry length.
- Road edges join points of one network. `from` to `to` is also an edge wherever the pathfinder found a road (`road`), as just-laid road can join networks still known apart.
- Every road edge weighs the length the pathfinder measured for it, or its straight line until measured. A road is never shorter than the straight line, so once every road edge of the shortest way is measured, no other way can be shorter.

It returns the tunnels in turn (`{ entry, exit, length, from, to }` each, `from` and `to` being portal unit numbers), with `hops.from` (where the way starts) and `hops.roads` (the length of each road of it, one more than its tunnels), and the way's length. It returns false while waiting for measurements, and nil when there is nothing to weigh: no portal on the surface, an end off road, or no way at all. The road, if any, is then left to the pathfinder.

A plan reads each mouth's network from what is known, and makes each leg's key once (`leg_between`: kept in Lua only, since a key is the same whenever it is made; started afresh at 20,000 keys). Making the key of every road from every tunnel's way out to every other mouth anew was most of what a plan cost, about 1 ms with 30 tunnels on one network.

### Measured roads

`storage.tunnel_legs[surface]` holds what the pathfinder measured:

| Field | What it holds |
| --- | --- |
| `lengths[leg]` | The road's length, or false for no road. `leg_key` is the tiles of both ends, the same either way round. |
| `measured[leg]` | The tick of each answer. |
| `spans[leg]` | The two ends of each road measured, for `tunnels.forget`. |
| `asked[leg]` | `{ tick, id }` of the leg's current question to the pathfinder. |
| `cut` | How many times road was removed there. |
| `made`, `fresh`, `stale` | When the table was made, when lengths were last fresh, and whether road was laid since. |

- A road whose two ends are on the same tile (a freighter at a mouth) counts as its straight line.
- `road`, a search's own answer for `from` to `to`, is recorded as measured.
- Road laid makes the lengths stop being `fresh`, at most once a second. Laid road can only make a road shorter, so one measured before still counts while it is measured again. The way is first worked out with only fresh roads (the others as their straight line), and the roads on it are asked again. Then it is worked out with the older ones too, so a plan waits only for roads never measured. Robots lay road a tile at a time: forgetting each tile's worth kept freighters waiting while they worked (the review of 0633faa), and forgetting them once a second kept a freighter waiting as long as answers took over a second (the review of 3569498).
- An answer to a question asked before road was only laid is taken.
- Everything is forgotten after five minutes (`LEG_MEMORY_TICKS`), since another mod may change tiles without an event. Questions unanswered for 10 s by then go too, with their waiters.

### Asking the pathfinder

Until the shortest way's road edges are measured, `tunnels.plan` asks the pathfinder for them and returns false.

- `tunnels.ask` (set by `scripts/routes.lua`) asks as a search's road is asked. `routes.on_script_path_request_finished` hands the answer to `tunnels.answered` via `storage.tunnel_leg_asks`.
- A question unanswered after 10 s (`ASK_TICKS`) is asked again and the old one dropped. Only a leg's current question is kept, so any other's answer changes nothing and resumes nobody (Pullfrog's review of 3569498: an old busy answer cancelled the search waiting for the question asked after a removal).
- The `waiter` is registered in `storage.tunnel_waiters[surface][leg][waiter.id]`. When the leg is answered, its waiters are resumed in `order` through `tunnels.resume` (set by `scripts/logistics.lua`), the same in every player's game. `busy` is passed for `try_again_later`. A search's waiter carries its `wait`, so an answer to a question an earlier wait asked says nothing to it.
- `tunnels.add_all` (on `on_init` and `on_configuration_changed`) forgets the measured roads, questions and waiters.

## When road is removed

Road removed changes only what it can have been on. Every point of a road of some length between two points lies within that sum of distances from the two. So tiles farther off than that, with `NEAR` (2 tiles) to spare for a freighter's width and the arrival radius, were never on it (`passes`; the box of an event's tiles, `tunnels.box`, stands for each of them). That road is still there, as long as it was, and removing road makes no other road shorter.

- `tunnels.forget` (from `logistics.on_roads_changed`) forgets only the measured roads the removed tiles can have been on. A road measured as none stays none, unless the same event also lays road (a script's event of road and another tile can). Every question asked before a removal is dropped with its waiters, since its answer may be of the road as it was.
- A freighter keeps where it last arrived and its plan unless the tiles can have been on a road it has yet to drive (`tunnels.untouched`, by its plan's `from` and `roads`). One standing to load or unload, with no plan, counts only within a tile of where it arrived.
- Any other freighter on that surface has its `origin` and `plan` cleared and is marked `road_cut`. It plans its way again at a check of its own once the road is left alone (`logistics.replan_cut`; see [roads and deliveries](roads-and-deliveries.md)).
- With the tiles not known, more than 1,000 of them, or roads or plans from a save before their ends and lengths were kept, everything is forgotten and every freighter on the surface plans again.

Why: before, any tile removed anywhere made every freighter on the surface plan again, asking the pathfinder about each road from where it stood. On a map of 17,446 road tiles with 30 tunnels and 504 freighters, one tile removed beside a road meant 925 plans in two seconds, with most freighters still waiting ten seconds on.

Engine traps behind this:

- A freighter whose road is cut and isn't re-planned stands 280 to 400 ticks before its command fails (probed on 2.1.24), so every freighter the tiles can have been near is marked at once.
- The pathfinder's lengths are not the shortest roads: from where a freighter stood on its way, it measured a road longer than the whole way. No more is concluded from them than `passes` allows. Telling whether a freighter is still on its way from two more measured roads failed for most freighters, and was dropped.
- Road laid still has every road measured again, at most once a second. Going through the measured roads for each tile laid cost more than it saved.

## Searches through tunnels

In `scripts/logistics.lua`, on a surface with tunnels, every candidate the pathfinder (or a remembered road) answers is planned from `search.from` with that answer as `road` (`route_answered`). `search.from` is where the pathfinder was asked from: the depot's loading zone, or where a rerouted or refuelling freighter stood.

- A plan still waiting leaves the search at that candidate (`search.waiting`: the road's length, or false for none) until `tunnels.resume` gives it back.
- With the pathfinder busy, a depot's search is cancelled and a freighter's retried, as for their own questions.
- The best candidate's tunnels are `search.best_plan`.
- A freighter's search also notes where the freighter last arrived (`search.origin`). `logistics.search_plan` passes the search's plan on only if the freighter is still there. One that has come out of a tunnel since (a search started under ground plans from the mouth it went in at) plans afresh from the exit. Without this a freighter was sent by road from the exit to a provider back on the side it went in at (the review of 0633faa).
- The way home is planned at the provider from the roads the search measured on the way out (leg keys are the same either way round), so it asks the pathfinder nothing new.

## Driving through a tunnel

### Following a plan

`drive` follows `trip.plan` (`{ to, hops, step }`):

- the plan the search made (`start_trip`, `set_off` and the Fuel depot leg pass it);
- the one it is on, when re-planning for the same destination;
- or one made then from `trip.origin` (or where the freighter stands).

`trip.origin` is the last place it arrived: its depot's loading zone at `start_trip`, then each destination it reaches (`on_ai_command_completed`, which also drops the plan), and each tunnel's entry and exit. It is cleared with the plan when road is removed where its way can have been (above), before the searches there restart, so they and its re-plan start from where it stands. A cut can leave a freighter on another network than where it last arrived (Claude's review; Pullfrog's review of fa62744 for the order).

A freighter waiting for measured roads stops (`trip.planning = { to, token, since }`).

- `trip.planning` is cleared by `drive`, `lifecycle.begin_search` and `lifecycle.clear_route_search`.
- `on_ai_command_completed` and `failed_commands` skip a freighter that is planning.
- Its once-a-second check (`check_trip`) plans again after `SEARCH_TIMEOUT`, or at its next check after a busy answer, unless its road is cut. What it waited on then went with the measured roads, and `logistics.replan_cut` plans it.

It drives to the next hop's mouth (`trip.tunnel`, movement `approaching-tunnel`). A tunnel closed before it goes in (`tunnels.open` false: a portal removed or turned) drops the plan, and it plans afresh from the mouth.

### Going under

At the mouth, `logistics.into_tunnel`:

1. Burns the fuel for the way to the mouth (`burn`). Going through moves the freighter from one mouth to the other at once, so without this a short tunnel between two once-a-second checks was measured as one straight line across the approach, the tunnel and the way out (Pullfrog's review of fa62744).
2. Repaints it as `paint.underground` (`jatz-freighter-drone-underground`, `prototypes/freighter-drone.lua`): the same unit drawn as nothing, unlit and unselectable. Every unit must be a military target in 2.1, so it stays one, and enemies at the mouth can still hurt it.
3. If something is stuck to it (fire, acid, slowdown), `repaint` refuses. It waits at the mouth (`waiting-at-tunnel`, a 60-tick stop) until that wears off.
4. Clears `trip.last_position`, so `scripts/impact.lua` runs nothing over between the two ends.
5. Stands for the tunnel's length at its speed times the road's `walking_speed_modifier` (`logistics.road_speed`), with movement `underground`.

While under ground:

- `logistics.command` holds every command, and `drive` only notes the destination. Re-plans, reroutes and fuel searches wait for it to come out.
- It always comes out, even if a portal is removed meanwhile.
- `paint_of` returns `paint.underground`, `show_cargo` draws nothing, and `scripts/impact.lua` skips it.
- `paint.names()` includes the underground paint, so every freighter filter finds it.
- Its stand only completes successfully. A failure there is a freighter dying at the mouth (enemies, or a script's `die` with its health still showing), so it is deferred like any failure (`failed_commands`). That loses a freighter gone by then and brings out one still alive.

### Coming out

`logistics.out_of_tunnel` moves the plan on a step, sets `trip.origin` to the exit, and charges the tunnel's length in fuel exactly, with the next fuel sample taken from the exit (`logistics.through_tunnel`).

- It repaints the freighter at the exit, facing out of that mouth (`tunnels.facing`, or the way it went in if that portal is gone). The unseen freighter has one direction, so the game turns it north, and a freighter coming out kept that and swung round at once (the owner's report, November 8, 2026).
- If something got stuck to it under ground, it is teleported instead, comes out unseen, and `check_trip` paints it once that wears off.
- With a search under way (a reroute or fuel search started under ground, which belongs to the unit's id), it comes out unseen too: teleported, not repainted, which would make the search stale. It waits, and `check_trip` paints it once the search is over (Claude's review).
- It appears just inside the mouth's edge on the entry tile (`tunnels.way_out`, `WAY_OUT_INSET` 0.25 from the tile's centre).
- It first drives straight out (`trip.movement == "exiting-tunnel"`): to the tile beyond if that is road, else to the entry tile's centre. A failure of that stretch just drives on. `on_ai_command_completed` then drives it on to `trip.destination`.

Engine traps behind these choices:

- **Inset 0.25, not 0.3.** The freighter's collision box is 0.2 each way, so at 0.25 it ends short of the portal's tile. The game rounds positions to 1/256 tile towards zero. At 0.3, out of a mouth facing west or north at negative coordinates, the box's edge landed on the portal's off-road tile, no route led on, and a loaded freighter took its load back (the owner's save, November 8, 2026).
- **The straight stretch out.** The game turns a unit to the first point of its route the moment it gets one, and the route on from the entry tile often starts across the road, so the freighter was never seen to leave the mouth (the owner's video, November 8, 2026).
- **Made facing its orientation.** `repaint` creates every new freighter with `create_entity`'s `direction` (the nearest of 16), then sets the exact orientation. A unit made without one is drawn facing north and turns round at its rotation speed whatever its orientation is set to. The headless game can't show this (the owner's video, November 8, 2026: freighters came out of a tunnel showing north for a few ticks).

## Tests

- `tests/lua/logistics.lua`: a round trip through a tunnel; a tunnel closed before entering; a portal removed while under ground; something stuck at the mouth; freighters killed under ground by enemies and by a script; a reroute started under ground; mouths off road; a road cut behind a freighter with a reroute under way; a same-network route that no tunnel shortens; a tunnel shorter than the road round it taken there and back with no new question home; a shorter road driven instead; rerouting mid-road weighing both ways; a Fuel depot through a tunnel; a reroute under ground back to the side it went in at; the road found just after it joins two networks; two tunnels in series, through a one-tile road and on one network.
- `tests/lua/tunnel-legs.lua` (run by `tests/lua/logistics.lua` with its helpers, since that file is at the size CI downloads): tiles laid elsewhere while a freighter waits for its plan; road laid while it waits; old answers resuming nobody after a removal; questions never answered dropped with their waiters; a freighter destroyed while it waits to plan again.
- `tests/lua/road-cuts.lua` (run the same way): road removed a tile a tick; a flood kept for the next freighter; a tile removed off a freighter's way, on the road still ahead, beside one standing to load; more than 1,000 tiles; roads and plans from a save before.
- `tests/lua/control-events.lua`: portal build, turn, clone and removal through `control.lua`'s events, and road laid and removed where networks are known.
- The check mod (`tests/factorio/jatz-distribution-check_0.1.0`):
  - `on_road`: a portal can't be placed on road; `road_through_cliff.tunnel_under`: portals pair under a cliff.
  - 10 radars through a tunnel under stone walls, west of x 0, so the freighter comes out of a west-facing mouth at negative coordinates (`tunnel_paired`, `tunnel_received`, `tunnel_went_under`).
  - 10 small lamps through the same layout east of x 0, with a road round the walls 8 tiles longer that no freighter may drive (`shortcut_received`, `shortcut_went_under`, `shortcut_drove_round`).
  - 10 medium electric poles through two tunnels in series on one road network, with roads round them 10 tiles longer or more (`series_received`, `series_went_under` at all three mouths, `series_drove_round`).
