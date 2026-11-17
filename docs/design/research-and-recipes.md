# Research and recipes

Every recipe is locked until research unlocks it. The tree follows Transport Drones' values (no code). Freighter upgrades are scripted bonuses: the technologies carry `nothing` modifiers, and the runtime reads a force's levels to size cargo and set speed.

## Code

- `prototypes/technologies.lua`: technologies; `scripts/research.lua`: names, levels, bonuses, pre-research unlocks.
- `scripts/logistics.lua`: applies bonuses (`start_trip`, `on_research_changed`); `scripts/bonus-gui.lua`: the Freighters panel.
- Recipes: `prototypes/depots.lua` (`INGREDIENTS`), `freighter.lua`, `roads.lua`, `road-monitor.lua`, `road-tunnel.lua`.
- `tools/make_icons.py`: 256 px technology icons.

## Technologies

- Liquid freight is its own research, after Fluid handling (the owner's choice, November 5, 2026). The road network monitor has its own research (the owner, November 5, 2026). Road tunnels come after `logistics`.
- Item and fluid capacity stay separate upgrades, ten levels each; item capacity adds one stack a level, from 2 up to 12 (the owner's choice, November 8, 2026).
- An infinite level's `level` is the next one to research, so one less is done. Quality also scales bonuses ([Quality](quality.md)).
- A trip keeps the cargo size it set off with. `storage.research_levels` caches levels; research and force events clear it.

## Bonuses panel

The game's Bonuses window never lists `nothing` modifiers (the owner's report, November 14, 2026), so `bonus-gui.lua` anchors a panel to it (`relative_gui_type.bonus_gui`). Probed on 2.1.24:

- Opening the window raises `on_gui_opened` with `gui_type.bonus`.
- `LuaForce.reset` raises no `on_research_reversed`, so the reset itself refreshes the panel.
- `game.merge_forces` raises `on_player_changed_force` for each player it moves.

## Saves from before research

Factorio resets every force's technology effects on load when unlocks change, so an old save would have every recipe locked. `research.on_configuration_changed` researches `research.unlocks` once for a save without `storage.recipes_by_research`; `research.init` sets it on new games. Probed on 2.1.24.

## Technology icons

A scaled-up 64 px icon was too blurry for the owner, so icons are 256 px. Fluid capacity adds the game's water icon: with only the liquid depot, the owner read it as the depot holding more.

## Recipes

The owner approved the depot, freighter, road and monitor recipes on November 6, 2026, and the road tunnel recipe with road tunnels. The numbers are on the Mod Portal page (`portal/description.md`) and in `tools/test_mod.py`'s `RECIPES`; the check mod reports each recipe for it to compare, so change both together.

- Every ingredient must be craftable once its research is done in 2.1. Iron sticks are not (circuit network, railway and concrete unlock them).
- Item depots take the belt their artwork shows in place of a gear (the owner's offset). The Fuel depot takes no pump: Fluid handling isn't needed for the freight system.
- The freighter takes 5 coal and stays 5 whatever `jatz-freighter-fuel-capacity` (the owner's choice).
- The Space Age carbon recipe has `auto_recycle = false`: the recycler names its recipe after the product, so only the coal recipe may make one.
- Road stacks to `jatz-road-stack-size`; its weight lets a rocket carry `jatz-road-rocket-stacks` stacks (the owner's request, November 14, 2026).

## Tests

`tests/lua/logistics.lua`, `tests/lua/control-events.lua`, and the check mod (with `scenarios/bonuses`).
