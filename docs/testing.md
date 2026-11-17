# Testing

Three runners check the mod and its artwork in the real game: `tools/test_mod.py` for the mod, `tools/test_factorio.py` for the freighter artwork and `tools/test_depot_art.py` for the depots. Each builds an isolated Factorio setup under `.local/`, so your normal mods, settings and saves are never touched. Other checks run without Factorio.

You need Factorio 2.1 (recent runs used 2.1.25; see [test-results.md](test-results.md)), Python 3.13 and, for the engine-free Lua tests, Lua 5.2 (`lua5.2` on your `PATH`). The free headless server is enough for the automated runs. Automated (headless) runs prove the prototypes load and behave, but only the graphical client shows whether the sprites *look* right. Both are needed after visual changes.

## Setup

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python assets/quinityn-freighter/tools/validate_assets.py
```

The validator checks every freighter atlas cell: neutral masks, no clipped edges, and paint layers that recombine into the preview. The depot packager runs equivalent checks whenever depot sprites are rebuilt.

On Windows, use `py -3.13 -m venv .venv` and `.venv\Scripts\python.exe`.

## Without Factorio

CI's area jobs run these (AGENTS.md, **Continuous integration**); run the ones for what you changed.

- `python3 tools/test_mod_setup.py`: `tools/test_mod.py`'s mod selection and locale parsing, the English names, the prototypes' icon size, and the depots' orientation and loading zones with Lua 5.2 (south by default, turning with the depot, never on a pipe tile). It also runs the Lua harnesses in `tests/lua/` against a fake runtime: `logistics.lua` (with the files it loads), `quality.lua`, `depot-swap.lua`, `depot-road.lua`, `control-events.lua` and `freighter-colors.lua`. Without `lua5.2` the Lua tests skip.
- `python3 tools/test_depot_lua.py`: the generated depot Lua matches its generators.
- `python3 tools/test_emulate_ups.py` and `python3 tools/emulate_ups.py --base origin/main`: the engine-free UPS check ([benchmark.md](benchmark.md#ci-the-ups-benchmark-check)).
- Repository tools: `tools/test_ci_changes.py`, `tools/test_pullfrog_command.py`, `tools/test_check_blender_sources.py` and `tools/test_apply_rulesets.py`. Release and portal tools: `tools/test_releases.py` and `tools/test_portal_page.py` ([releases.md](releases.md#build-and-validate-locally)).
- Artwork: `python3 tools/check_blender_sources.py`, then, in the virtual environment above, `tools/test_art_dependencies.py`, `tools/make_icons.py --check` and `assets/depots/tools/make_loading_zone.py --check`.

## The mod

```sh
python3 tools/test_mod.py --factorio /path/to/factorio/bin/x64/factorio
```

This builds the installable zip with `tools/package_mod.py` and loads it, with the check mod `tests/factorio/jatz-distribution-check_0.1.0`, in a fresh workspace under `.local/mod-check/`. It creates a save, runs it for 2,600 ticks (the check mod fails itself if the deliveries haven't finished by tick 2,500), then runs the check mod's scenarios with a player (`--test-scenario`): `undo`, `bonuses`, `network`, `drop-freighters` and, with the Quality mod, `quality`.

It runs with the base game only and, if your Factorio includes Space Age and the mods it needs, again with Space Age. To look around yourself, open the newest save under `.local/mod-check/` in the full game with that run's `config.ini` and `mods` folder (see [Depots](#depots) for the command).

The full list of what it checks is `EXPECTED` and its siblings (`RECIPES`, `EXPECTED_UNDO`, `EXPECTED_BONUSES`, `EXPECTED_QUALITY`, ...) in `tools/test_mod.py`, and the check mod's `control.lua` and scenarios. Extend the check mod along with new behavior. Its `EXPECTED_PORTS` table is the designed pipe layout, kept independent of the generated data (see AGENTS.md).

### What it covers

- **Recipes, research and placement:** every recipe locked until its technology, research levels and bonuses, every depot placed, rotated and destroyed (its own wreck) in all four directions, pipe ports, the freighter's hidden drivable car, English names, the crafting-menu row, decoratives cleared from loading zones, road stack size.
- **Deliveries over road:** freighters stay on road, cargo keeps its data (equipment, spoilage), lost freighters are replaced and repaired, enemies are run over or destroy a freighter, road tunnels, promises let go, the 1-second stops, cargo paint and alt-mode icons, road cuts and mended roads, the shortest provider by road.
- **Blueprints and settings:** requests and freighters in blueprint tags and parametrisable request settings, pasting over depots, matching freighter counts.
- **Depot road**, **freighters in the slot** (ctrl+click, remote view, robots), **buffers, priority, full loads and liquids**, **what road allows**, **fuel** (refuelling legs, petroleum gas, `no-fuel` status, Fuel depot clones) and the **circuit network** (depot conditions, the road network monitor).

What needs a player or input a script can't raise (Copy and Paste settings, blueprint setup, building with tags, mining a depot, clicking the slot, turning a depot or covering its road, loading older saves) is checked against a fake runtime in `tests/lua/control-events.lua`, `tests/lua/logistics.lua` and `tests/lua/depot-road.lua`.

### Scenarios with a player

- **`undo`:** depots cut, mined by hand, replaced (from the hand, a ghost or an upgrade planner) or upgraded by a script (`apply_upgrade`) keep their settings on the player's undo actions, also with the undo history at its 100-item limit, and get them back when rebuilt; with Space Age, also on a space platform. The undo key press itself can't be scripted.
- **`bonuses`:** the "Freighters" panel beside the Bonuses window follows research, undone levels and force changes. That it looks right needs the graphical client.
- **`network`:** the freighter network window with real GUI elements and inventories. The scenario calls the production shortcut handler because the engine cannot raise `on_lua_shortcut` by script. It also opens the window in remote view on another surface, and pins it: the engine's `on_gui_closed` during the click must find the pin set; `tests/lua/control-events.lua` covers the event wiring, force isolation, scans, pagination and filters.
- **`drop-freighters`:** the single-item-drop event payload supplied to the production inventory handler. The engine cannot raise that event by script; `tests/lua/control-events.lua` checks its registration.
- **`quality`** (the Space Age run, with the Quality mod): requests by quality, better freighters and depots (a rare freighter has the game's 800 health for a rare unit), quality upgrades by robots and by a player, and blueprints keeping the quality and comparator.

### Other mods

With `--mod path/to/Mining_Drones_2.1.1.zip` (or Mining Drones 2 Remastered's or Mining Drones Mod's zip, from the mod portal), a request depot must also fetch iron ore from a mining depot's output, over the road the mining depot lays behind it.

With `--mod path/to/Milestones_1.5.2.zip`, Milestones must log that it loaded our preset addon. Milestones only tracks forces with players, so whether the milestones are reached needs the graphical client: start a new game with Milestones, craft a freighter, and check that the "first freighter" milestone is announced and listed under Progress. Every run also checks that each item in the addon is a real item.

The option can be repeated for other mods, which then only have to load.

### In the graphical client

Headless runs prove API behavior, not visual layout or live multiplayer latency. Check these in the full game:

- **Cargo paint:** freighters heading to a provider have light grey cargo bays; ones coming back carry their load's color (blue-grey for iron plates, orange for copper, blue for water), with the cab and clamps unchanged.
- **Loading zone:** each depot's marking lies on the right side and stays there as you rotate the depot.
- **Freighter drops:** hold several freighters and press Z over a request or buffer depot being unloaded by an inserter or loader, with its window closed: each drop must reach the freighter slot.

The request panel:
- Open a liquid request depot: your inventory is on the left of the tank window, and ctrl-clicking a freighter fills the slot (shift-click moves one stack).
- Open a request depot, choose an item and amount, and hover the status light: its tooltip shows the status in words, and its color follows (green while stocked or on its way, yellow while something is in the way, red when no provider or buffer depot has the item, grey with nothing requested).
- With the Quality mod, the **Quality** row under them reads "Quality ≥ rare" (with the quality's icon), the quality hides while **Any quality** is chosen, and nothing stands between the item and its amount.
- Use Copy and Paste settings onto another request depot.
- **Use freighter storage** shows on a liquid request and a liquid buffer depot, and on no item depot: it sits under **Full loads only**, its tooltip fits, ticking it with enough freighters raises the request amount, the field keeps an amount above the limit while you type and shows the limit on Enter or a moment after, and the line under it shows what the freighters hold.
- **Full loads only** on a request, a buffer, a liquid request and a liquid buffer depot: it sits under the request row (below **Request from buffer depots** on a request depot), caption and tooltip fit (the liquid tooltip names 750), and ticked while no provider holds a full load the light turns yellow with "Waiting for a full load". It must show within half a second in another player's open panel of that depot, and pasting settings must carry it.
- **Logistic robots can use it** on a provider and a buffer depot: under the priority slider, unticked on a new depot, caption and tooltip fit, and the depot's own window (a logistic container's) still has the panel on its right. Ticked inside a roboport's range, robots take from it for a requester chest; unticking stops them.
- Load a save made before provider and buffer depots were logistic containers: its depots still face the way they did, with their contents and settings.
- Open a Fuel depot: the panel shows the fluid piped in and its amount, and the flush button empties it.
- Hover a freighter on the road: its fuel shows as a status line (green, yellow when low, red when dry). A request depot shows a fuel line under its freighter slot, its tooltip listing every freighter's fuel. With a fuel item worth more than 20 MJ (a mod's), the hover shows the whole amount after filling up and on the next trip.

The freighter network window (click the freighter shortcut after Freight system research):
- Summary: fleet counts align, item and liquid depots align by role, Fuel and optional Mining Drones depots stay under Support, and read-only depot icons and counts have no button chrome or click feedback. Hover the icons and counts, zero included.
- Each resource is one line, full-width dividers separate rows, the depot icon and name head each role, and the Stock/Depots/Requests/Still needed headings sit over their right-aligned numbers.
- A page of seven rows shows with no scrollbar and no cut-off row; large amounts read as 63.8k/189k with the exact amount on hover; zero shows as a dash.
- The Items and Fluids tabs, hover details, quality and demand tooltips, empty requests, and shortages first.
- The resource picker's search and right-click clear, all three filters, and the page arrows with over seven resources, at your normal resolution and UI scale. Long platform names and large counts fit, and the snapshot age beside the arrows updates.
- Pick a planet and a platform, then rename the platform.
- With a second player, force and surface choices stay independent and deliveries stay smooth. Close both and check the update-time display returns to its closed-window level.
- E, Esc, close and the shortcut toggle.
- Save with the window open, load it and join in multiplayer: the snapshot completes and refreshes without desync. Update the mod with the old window open and check it rebuilds.

## Freighter

```sh
python3 tools/test_factorio.py --factorio /path/to/factorio/bin/x64/factorio
```

Add `--data-dir /path/to/factorio/data` if your install keeps data elsewhere. The runner creates `.local/factorio/freighter-test.zip`. The save holds 64 trucks on a concrete pad in an 8×8 grid, one per direction, plus a truck in alternate colors at (54, 54). Open it in the graphical client:

```sh
/path/to/factorio/bin/x64/factorio \
  --config "$PWD/.local/factorio/config.ini" \
  --mod-directory "$PWD/.local/factorio/mods" \
  --load-game "$PWD/.local/factorio/freighter-test.zip"
```

Check:
1. **Directions:** all 64 headings at normal and close zoom match `assets/quinityn-freighter/previews/all-64-directions.png`. The cab points north at 0, east at 16, south at 32 and west at 48. Look for skipped or repeated frames, a jumping pivot or wheels leaving the ground.
2. **Colors:** compare the default truck (violet cab, orange clamps, slate-blue cargo) with the alternate one. Glass, tires, steel, copper and the violet lenses must not change color. To stress one layer, edit its tint in `tests/factorio/freighter-art-check_0.1.0/data.lua` and rerun the runner.
3. **Shadow and night:** the shadow stays attached at every heading. Check again at night.
4. **Driving:** drive forward, turn in a full circle and reverse. The body and shadow move together.
5. **This art fixture only:** its truck keeps the base car's selection and collision boxes, which cover only the middle of the truck. The mod's freighter (`prototypes/freighter.lua`) is drawn at 60% of this fixture's scale, with a box fitted to the body (1.5 × 4.5 tiles measured on the art, about 0.9 × 2.7 in game); check it in a save from `tools/test_mod.py`.

## Depots

```sh
python3 tools/test_depot_art.py --factorio /path/to/factorio/bin/x64/factorio
```

The runner prints a workspace path under `.local/depot-art-check/`. It also runs automated checks: 28 placed depots, 7 alternate palettes, 28 ghosts, 112 rotation steps, 20 pipe connections and a save reload. Open the save:

```sh
/path/to/factorio/bin/x64/factorio \
  --config <workspace>/config.ini \
  --mod-directory <workspace>/mods \
  --load-game <workspace>/depot-art-test.zip
```

Each row is one depot, in this order: Provider, Request, Buffer, Fuel, Liquid Provider, Liquid Request, Liquid Buffer. Row *i* is at y = −55.5 + 8*i*. The columns face north (x = −29.5), east (−13.5), south (2.5) and west (18.5). A column of alternate colors with unconnected ports is at x = 44.5. Tanks hold water and the Fuel depot holds light oil.

Check:
1. **Footprint:** with the tile grid on, every depot covers 3×3 tiles in every rotation, sits on the ground and fits next to other buildings.
2. **Pipes:** trace each vanilla pipe into its tank in every rotation. Pipe width matches vanilla, the joint is seated and nothing clips. Remove and re-add pipes and check the pipe covers. Pipes on unused edges must not connect. North-side connectors draw behind the building.
3. **Colors:** role, clamp and housing colors change only their own areas. Metal, chips and lenses never change.
4. **Placement:** held-item rotation, ghosts, blueprints, rotating placed depots and save/reload all agree.
5. **Shadows and night** look right on both concrete and brick.

To get depot items for placement tests, run this in the console:

```lua
/c for name in pairs(prototypes.item) do if string.find(name, "^depot%-art%-") then game.player.insert{name=name,count=10} end end
```

### Freighter at the depots

To check that a truck can plausibly pull up to a depot:
1. Run the freighter runner first.
2. Copy `.local/factorio/mods/freighter-art-check_0.1.0` into the depot workspace's `mods` folder.
3. Add `{"name":"freighter-art-check","enabled":true}` to that workspace's `mod-list.json`, then open the depot save.
4. Spawn a truck from the console:

```lua
/c local s=game.surfaces["depot-art-test"]; game.player.teleport({0,-50.5},s); local v=s.create_entity{name="quinityn-freighter-art-check",position={2.5,-50.5},force=game.player.force}; if v then v.get_fuel_inventory().insert{name="coal",count=50} end
```

## Screenshots

Screenshots are written to `<config folder>/write/script-output/jatz-distribution/`. Examples:

```lua
/c game.take_screenshot{surface="depot-art-test",position={6,-31.5},resolution={2304,1536},zoom=0.8,path="jatz-distribution/depots-overview.png",show_gui=false,daytime=0}
/c game.take_screenshot{surface="freighter-art-test",position={0,0},resolution={2048,2048},zoom=0.5,path="jatz-distribution/freighter-headings.png",show_gui=false,daytime=0}
```

The first `/c` command in a save may need to be entered twice to enable console commands.

## Performance (UPS)

`tools/benchmark_ups.py` measures the game update time Jat'z Distribution's deliveries cost on a large generated road map, and `tools/emulate_ups.py` compares the mod's script cost with another revision without the game. Pull requests that can change what the game does each tick must include the benchmark's before and after table. See [benchmark.md](benchmark.md).

## Recording results

Record each run in [test-results.md](test-results.md), replacing the area's previous entry. Include the commit tested, Factorio version, OS and graphics backend, then a passed, failed or untested result for each check. Attach screenshots to the pull request instead of committing them. Only images used by the README belong in `docs/images/`, and only the Mod Portal page's in `portal/gallery/` and `portal/images/`.
