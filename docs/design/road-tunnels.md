# Road tunnels

Freighters can't drive over the factory, so they go under it (the owner's request, November 8, 2026). Units have no height, so a tunnel is a pair of portals, like underground belts: a freighter drives into one mouth, stands unseen for as long as the tunnel takes to drive, and comes out of the other.

The engine's pathfinder knows nothing of tunnels. The mod works out which road network each point is on and the shortest way through any number of tunnels; the pathfinder still drives every road leg. Players: [guide](../guide.md). Trip fields: [runtime state](../runtime-state.md).

## Code

- `prototypes/road-tunnel.lua`, `prototypes/constants.lua`: the portal, item and recipe; `prototypes/technologies.lua`: its research.
- `prototypes/freighter-drone.lua`, `scripts/freighter-paint.lua`: the unseen freighter.
- `scripts/tunnels.lua`: portals, road networks, measured roads, `tunnels.plan`.
- `scripts/routes.lua`: asks the pathfinder for legs.
- `scripts/logistics.lua`: `drive`, `into_tunnel`, `out_of_tunnel`, `route_answered`, `search_plan`, `on_roads_changed`.
- `control.lua`: portal and tile events (`tunnels_changed`, `roads_changed`).

## The portal

`jatz-road-tunnel` is a `pipe-to-ground`, one tile wide and two deep: a ramp down from its mouth (the owner's choice, November 8, 2026).

- Its one `underground` connection is in its own `connection_category`, so the game pairs portals, shows the reach while placing, and connects no other pipe to them. Nothing ever flows.
- `constants.tunnel_reach` is 19: back tiles at most 19 apart, so at most 18 tiles between (probed on 2.1.24). About twice Space Age's longest underground belt (the owner's choice, November 8, 2026).
- `prototypes/off-road.lua` leaves pipes-to-ground alone, so the prototype adds `jatz_road` to its collision mask itself.
- The tile in front of the mouth (`tunnels.entry`) must be road; a mouth off road is on no network.
- A tunnel also goes under cliffs, which road can't cross (the owner's report, November 14, 2026).
- The recipe makes two portals; the owner approved it ([research and recipes](research-and-recipes.md)). `jatz-road-tunnels` is not in `research.unlocks`, because no save from before research had tunnels.
- The art is the mod's own; [assets/depots/README.md](../../assets/depots/README.md) owns it. It slopes down at the back so it reads as a ramp (the owner, November 8, 2026: an arched hood read as a pipe, a box as a lift).

## Road networks

`net_of` floods a network once with `LuaSurface.get_connected_tiles` over `jatz-road` and `jatz-depot-road`, and notes every portal entry and loading zone it reaches. Floods live in storage so every game agrees. Freighters share one flood a network: a 14,000-tile flood takes 20 ms and more (a player's report, November 15, 2026).

- A network keeps its number while known; networks that new road joins merge under the lowest number.
- Tiles laid or removed are applied to the known floods, not flooded again (`tunnels.changed`). Each tile is read from the surface as it is now. A removal whose road neighbours may no longer reach each other forgets that flood.
- Everything is forgotten when a portal changes, and for events over 1,000 tiles (`TILES_AT_ONCE`).

## Planning a way

A tunnel counts as road, with no penalty, even several in series (the owner, November 13 and 14, 2026: "There should never be a penalty for underground road path even multiple in series").

`tunnels.plan` is a Dijkstra over `from`, `to` and each portal entry. Tunnel edges weigh their length; road edges weigh the length the pathfinder measured, or the straight line until measured. A road is never shorter than its straight line, so once every road edge of the shortest way is measured, no other way is shorter. It returns false while waiting for measurements, and nil with no portal, an end off road, or no way; the road is then left to the pathfinder.

### Measured roads

- Laid road can only make a road shorter, so an old measurement still counts while it is measured again (roads measured as none too); a plan waits only for roads never measured. Removed road leaves a road measured as none as none.
- Everything is forgotten after five minutes (`LEG_MEMORY_TICKS`), since another mod may change tiles without an event.
- A question unanswered for 10 s (`ASK_TICKS`) is asked again. Only a leg's current question is kept, so an old answer resumes nobody.
- Waiters are resumed in `order` through `tunnels.resume`, the same in every player's game.

## When road is removed

A road between two points lies within the sum of its distances from them, so removed tiles farther off (plus `NEAR`, 2 tiles) were never on it (`passes`). `tunnels.forget` forgets only measured roads the tiles can have been on, and drops every question asked before the removal. When the event's tiles are known, a freighter with a plan (or standing at a depot) keeps it unless the tiles can have been on road it has yet to drive (`tunnels.untouched`); others are marked `road_cut` and plan again later ([roads and deliveries](roads-and-deliveries.md)).

Engine traps:

- A freighter whose road is cut and isn't re-planned stands 280 to 400 ticks before its command fails (probed on 2.1.24), so every freighter near the tiles is marked at once.
- The pathfinder's lengths are not the shortest roads, so no more is concluded from them than `passes` allows.

## Searches and plans

- Every candidate a search gets is planned from `search.from` (`route_answered`).
- `logistics.search_plan` passes a search's plan on only if the freighter is still where it last arrived; one that came out of a tunnel since plans afresh from the exit.
- `trip.origin` is cleared with the plan when road is cut, before the searches there restart, so they start from where the freighter stands.
- A tunnel closed before entry drops the plan.

## Driving through a tunnel

Going under (`logistics.into_tunnel`):

- Burn fuel for the way to the mouth first: going through moves the freighter at once, so a short tunnel was otherwise measured as one straight line.
- Repaint as `paint.underground`: drawn as nothing, unlit, unselectable. Every unit must be a military target in 2.1, so enemies at the mouth can still hurt it.
- If a sticker is on it, `repaint` refuses; it waits at the mouth (`waiting-at-tunnel`) until it wears off.
- It stands for the tunnel's length at road speed, holds every command, and always comes out (even if a portal is removed). `paint.names()` includes the underground paint so every freighter filter finds it.
- Its stand only completes successfully, so a failure is a freighter dying at the mouth (enemies, or a script's `die`) and is deferred like any failure.

Coming out (`logistics.out_of_tunnel`) charges the tunnel's length in fuel exactly and sets `trip.origin` to the exit. With a sticker or a search under way it is teleported unseen, and `check_trip` paints it later; repainting would make the search stale.

Engine traps behind coming out:

- **Facing out of the mouth.** The unseen freighter has one direction, so the game turns it north; it is repainted facing out (`tunnels.facing`) (the owner's report, November 8, 2026).
- **Inset 0.25, not 0.3** (`WAY_OUT_INSET`). The collision box is 0.2, and the game rounds positions to 1/256 tile towards zero. At 0.3, out of a west- or north-facing mouth at negative coordinates, the box touched the portal's off-road tile and no route led on (the owner's save, November 8, 2026).
- **A straight stretch out** (`exiting-tunnel`). The game turns a unit to its route's first point at once, and that often lies across the road, so the freighter was never seen leaving the mouth (the owner's video, November 8, 2026).
- **Made facing its orientation.** `repaint` passes `create_entity` a `direction`; a unit made without one is drawn facing north and turns round whatever its orientation. The headless game can't show this (the owner's video, November 8, 2026).

## Tests

`tests/lua/logistics.lua` (which runs `tunnel-legs.lua` and `road-cuts.lua`), `tests/lua/control-events.lua`, and the check mod (`tests/factorio/jatz-distribution-check_0.1.0`).
