# Research and recipes

Every recipe of the mod is locked until research unlocks it. The tech tree follows Transport Drones' (its values only, no code). Freighter upgrades are scripted bonuses: the technologies carry `nothing` modifiers, and the runtime reads a force's levels to size cargo and set speed. The recipes are the ones the owner approved, and a test holds the list.

## Code

- `prototypes/technologies.lua`: the technologies, their costs, prerequisites, unlocks and icons.
- `scripts/research.lua`: technology names and numbers (loaded by the data stage too), the levels a force has, what they give, and the unlocks for saves from before research.
- `scripts/bonus-gui.lua`: the "Freighters" panel beside the game's Bonuses window.
- `scripts/logistics.lua`: applies the bonuses to trips and freighters (`start_trip`, `on_research_changed`, `on_forces_changed`).
- `prototypes/depots.lua` (`INGREDIENTS`), `prototypes/freighter.lua`, `prototypes/roads.lua`, `prototypes/road-monitor.lua`, `prototypes/road-tunnel.lua`: the recipes.
- `tools/test_mod.py`: `RECIPES`, `RECIPES_SPACE_AGE` and the expected research tree.
- `tools/make_icons.py`: the 256 px technology icons in `assets/*/technology/`.

## Technologies

| Technology | Prerequisites | Cost | Unlocks |
| --- | --- | --- | --- |
| `jatz-freight-system` | `engine` | 200 × red and green, 30 s | Provider, request, buffer and Fuel depots, the freighter (and its carbon recipe with Space Age), road |
| `jatz-liquid-freight` | freight system, `fluid-handling` | 200 × red and green, 30 s | The three liquid depots |
| `jatz-road-network-monitor` | freight system, `circuit-network` | 500 × red and green, 30 s | The road network monitor |
| `jatz-road-tunnels` | freight system, `logistics` | 300 × red and green, 30 s | Road tunnels |

- Liquid freight is its own research, after Fluid handling, which unlocks storage tanks (the owner's choice, November 5, 2026).
- The road network monitor got its own research when it arrived, at Transport Drones' depot circuits cost (the owner, November 5, 2026).
- Road tunnels come after underground belts (`logistics`), since freighters go under the factory as items do on underground belts.
- The freighter network window's shortcut (`prototypes/shortcut.lua`) is unlocked by the freight system (`technology_to_unlock`).

## Upgrades

| Upgrade | Levels | Each level | Range |
| --- | --- | --- | --- |
| `jatz-freighter-speed-1` to `-4` | after the freight system | +20% speed | up to +80% |
| `jatz-freighter-speed-5` | infinite, `2^(L-5)*500`, all six science packs, 60 s | +20% speed | no limit |
| `jatz-freighter-item-capacity-1` to `-10` | after the freight system | one more stack | 2 stacks up to 12 |
| `jatz-freighter-fluid-capacity-1` to `-10` | after liquid freight | 375 more fluid | 750 up to 4,500 |

- Finite levels cost 200 × the level, 30 s, on Transport Drones' science ladder (`LADDER`): red and green at level 1, then blue, purple and yellow added one level at a time, so level 4 and every level after it take all five packs up to yellow.
- Item and fluid capacity stay separate upgrades, with ten levels each (the owner's choice, November 8, 2026).
- The effects are `nothing` modifiers with an `effect_description` (`modifier-description.*` in the locale), so the technology screen shows what each gives.

## How the runtime applies research

- `research.levels(force, name)` counts levels in turn, up to the first not researched. An infinite level's `level` is the next one to research, so one less is done.
- `research.cargo_stacks`, `research.fluid_capacity_of` and `research.freighter_speed` give what a force's freighters carry and how fast they drive. Each takes the freighter's quality too (see [Quality](quality.md)).
- A force's levels are kept in `storage.research_levels[force index]`, because working them out reads every level's technology and prototype. They are forgotten when that force's research finishes or is undone, when forces are reset, created or merged, on `on_technology_effects_reset`, on configuration changes (`logistics.add_all`), and after a minute in case a script changed a level without an event.
- `start_trip` sizes each new trip's cargo inventory, and the planned load, from the request depot's force, and sets the new freighter's `speed` (a unit's `speed` is writable) to the prototype's times the multiplier. A trip keeps the cargo size it set off with.
- `repaint` copies the old unit's speed to the new one.
- `logistics.on_research_changed` (`on_research_finished` and `on_research_reversed`) updates the speed of the force's freighters on the road when a speed level changes. A dry freighter keeps crawling at its share of the new speed (see [Fuel](fuel.md)).

## Bonuses panel

The game's Bonuses window lists only its own modifiers, never `nothing` ones (the owner's report, November 14, 2026). So `scripts/bonus-gui.lua` anchors a "Freighters" panel to it (`relative_gui_type.bonus_gui`), with one line for each researched bonus (speed, item stacks, fluid) and no panel at all while nothing is researched.

The panel is built afresh for the player's force:

- on `on_gui_opened` with `gui_type.bonus` (the game raises it for that window, probed on 2.1.24); `scripts/request-gui.lua` passes the event on;
- for each of the force's players with the window open (`opened_gui_type`) when a freighter upgrade is researched or undone (`logistics.on_research_changed`) or the force is reset (`logistics.on_forces_changed`);
- for a player with it open who moves to another force (`on_player_changed_force`, registered by `scripts/request-gui.lua`).

Engine facts behind these handlers, probed on 2.1.24:

- `LuaForce.reset` raises no `on_research_reversed`, so the reset itself refreshes the panel.
- `game.merge_forces` raises `on_player_changed_force` for each player it moves.

## Saves from before research

Factorio resets every force's technology effects on load when technology unlocks change (2.1's changelog). A save made before research existed would then have every recipe locked with nothing researched.

- `research.init` (`on_init`) sets `storage.recipes_by_research` on a new game or a save the mod is added to. Those stay research-gated.
- `research.on_configuration_changed` (from `control.lua`) researches `research.unlocks` (freight system, liquid freight, road network monitor) for every force once, for a save without `storage.recipes_by_research`, then sets it. Road tunnels came after research, so no save had them unlocked.

This came from Pullfrog's review of `c1d45da` and was probed on 2.1.24 by loading a save from main into this mod.

## Technology icons

- Icons are 256 px, made by `tools/make_icons.py` from the 512 px game frames. A scaled-up 64 px item icon was too blurry for the owner.
- The freighter is the icon of the freight system and of every upgrade; the liquid provider depot of liquid freight; the road network monitor and the road tunnel of their own research.
- Upgrades add the game's constant overlays (`constant-movement-speed`, `constant-capacity`).
- Fluid capacity also adds the game's water icon (`__base__/graphics/icons/fluid/water.png`, referenced, not copied) in the top left corner. With the liquid depot as its icon, the owner read it as research that makes the depot hold more, not the freighter carry more.

## Recipes

The owner approved the depot, freighter, road and monitor recipes on November 6, 2026. `tools/test_mod.py`'s `RECIPES` holds the list, and the check mod reports each recipe's ingredients, time and amount for it to compare, so change both together. The Mod Portal page (`portal/description.md`) lists them too.

Every ingredient must be craftable once its research is done in Factorio 2.1. Iron sticks are not: circuit network, railway and concrete unlock them.

### Depots

`INGREDIENTS` in `prototypes/depots.lua`, 5 s each:

- Item depots take a steel chest (their 48 slots by default) and the belt their artwork shows, each belt in place of a gear (the owner's offset).
- Liquid depots take a storage tank; the request and buffer ones take pumps too.
- The Fuel depot takes a steel chest, a belt and an engine unit, not a pump: pumps come with Fluid handling, which the freight system doesn't need.

### Freighter

- `prototypes/freighter.lua`, 4 s. It takes its full tank's fuel: 5 coal for the default 20 MJ tank. It stays 5 coal whatever the `jatz-freighter-fuel-capacity` setting (the owner's choice).
- With Space Age (`? space-age` in `info.json`), `jatz-quinityn-freighter-carbon` makes it with 10 carbon instead, unlocked by the freight system too. It has `auto_recycle = false`: the recycler names its recipe after the product, so only the coal recipe may make one.

### Road

- `prototypes/roads.lua`: slag, 5 stone and 5 iron ore for 10 tiles, 1 s.
- It stacks to the startup setting `jatz-road-stack-size` (250 by default).
- Its weight is the rocket's lift (`default_rocket_lift_weight`) over `jatz-road-rocket-stacks` stacks of it (2 by default), as the game works out its own items' weights, so a Space Age rocket carries that many stacks (the owner's request, November 14, 2026). The check mod reports both.

### Road network monitor and road tunnels

- The road network monitor (`prototypes/road-monitor.lua`, 5 s): a constant combinator, 5 electronic circuits and 5 copper cable.
- Road tunnels (`prototypes/road-tunnel.lua`, 10 s): 20 stone brick, 10 steel plate and 10 iron gear wheels make two, one for each end. This recipe was proposed with road tunnels on November 8, 2026 (PR #81) for the owner's approval. It has shipped since and is on the Mod Portal page, but no record of that approval was found; `tools/test_mod.py` still calls it proposed.

## Tests

- `tests/lua/logistics.lua` covers the bonuses with fake technologies.
- `tests/lua/control-events.lua` covers the research event wiring, the Bonuses panel, and the `on_init` and `on_configuration_changed` handlers for saves from before research.
- The check mod checks the lock, the unlock, the tree, the levels against the game's own technologies, and a delivery on a researched force. Its `scenarios/bonuses` checks the panel with a player, the window kept open while research and the player's force change.
