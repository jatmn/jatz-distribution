# Testing the artwork in Factorio

Two test mods check the artwork in the real game: one for the freighter and one for the depots. Each runner builds an isolated Factorio setup under `.local/`, so your normal mods, settings and saves are never touched.

You need a full Factorio 2.1 install (tested on 2.1.24) and Python 3.13. Automated (headless) runs prove the prototypes load and behave, but only the graphical client shows whether the sprites *look* right. Both are needed after visual changes.

## Setup

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python assets/quinityn-freighter/tools/validate_assets.py
```

The validator checks every freighter atlas cell: neutral masks, no clipped edges, and paint layers that recombine into the preview. The depot packager runs equivalent checks whenever depot sprites are rebuilt.

On Windows, use `py -3.13 -m venv .venv` and `.venv\Scripts\python.exe`.

## The mod

```sh
python3 tools/test_mod.py --factorio /path/to/factorio/bin/x64/factorio
```

This builds the installable zip with `tools/package_mod.py` and loads it, with the check mod `tests/factorio/jatz-distribution-check_0.1.0`, in a fresh workspace under `.local/mod-check/`. It checks that:
- all eight recipes are available from the start and free;
- every depot can be placed, as a ghost and for real, in all four directions, and rotated through a full turn;
- all 20 pipe ports connect;
- containers hold items and tanks hold fluid;
- a character can enter a fuelled freighter and drive it.

It runs with the base game only and, if your Factorio includes it, again with Space Age. The free headless server is enough. To look around yourself, open the newest save under `.local/mod-check/` in the full game with that run's `config.ini` and `mods` folder (see the depot instructions below).

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
5. **Known issue:** the selection and collision boxes are inherited from the base car and cover only the middle of the truck.

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

## Recording results

Add a short entry to [test-results.md](test-results.md) for each test run. Include the commit tested, Factorio version, OS and graphics backend, then a passed, failed or untested result for each check. Attach screenshots to the pull request instead of committing them. Only images used by the README belong in `docs/images/`.
