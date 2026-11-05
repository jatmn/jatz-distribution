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
- all nine recipes are available from the start and free, and the road item lays the road tile;
- every depot can be placed, as a ghost and for real, in all four directions, and rotated through a full turn;
- each depot's pipe ports match the designed layout (written out in the check mod, independently of the generated data) and all 20 connect;
- containers hold items and tanks hold fluid;
- a character can enter a fuelled freighter and drive it;
- every item, recipe and entity name the game shows has an English translation;
- our row sits directly above the car and tank row in the same tab, with the items in their intended order;
- building a depot clears decoratives from its loading zone tile and keeps those beyond it, for all 7 depots in all 4 directions;
- deliveries stay on road. A provider holding 50 iron plates and a request depot asking for 30 stand 20 tiles apart, joined by a U-shaped road that detours 10 tiles south over concrete. The request must receive exactly 30, the freighter must reach the bottom of the U, and every 10 ticks all four corners of every delivering freighter must be on road. A request depot whose loading zone is an isolated road tile must receive nothing and report no route, and one without road at its loading zone must send nothing. More pairs on straight roads check that armor arrives with its equipment, and (with Space Age) food with its spoilage. They also check that a request depot with no room fetches nothing, and that a freighter destroyed on its way is replaced. A request changed to another item mid-trip must not load the old one. The freighter must stand about 1 second (50 to 70 ticks) at the provider's loading zone before it loads, and again at the request depot's before it unloads. When the road is cut behind a loaded freighter, the cargo must go back to the provider within 4 seconds (its 1-second stop to unload included), rather than after the freighter stands stuck. A road with a gap must be used within about 9 seconds of being mended (the round trip with its two 1-second stops), well before a delivery that waited out the 10-second retry cooldown could arrive. When the nearer of two providers is removed mid-trip, the same freighter must go on to the other one. When a request depot is removed mid-trip, its freighter must leave within 2 ticks. Of two providers, the one 8 tiles away in a straight line but 34 tiles by road must lose to one 16 tiles away on a straight road; and a request with no road route to any provider must never send a freighter. Blueprinting a request depot (7 wood, 3 freighters) must give the blueprint its request as a tag and its freighters as an insert plan, and a depot built from that ghost must ask for 7 wood and request 3 freighters. Matching a depot holding 1 freighter to 3 must request 2, and freighter requests that no longer fit after the slot is filled by hand must be trimmed. Copy and Paste settings, blueprint setup and building with tags need a player: `tests/lua/control-events.lua` fires them through `control.lua`. The freighter's collision box must be 75% of the measured 1.5 × 4.5 tiles. Depots lay road under their loading zone: a provider and a request depot whose road stops one tile short of each loading zone must still deliver. Removing depots must put back concrete and grass. Road that was already there, or a tile laid over the depot's road, must stay. Two depots loading from one tile must keep the road until the second goes, and nothing may be laid on water. Turning a depot, mining or covering its road by hand, and loading older saves need a player, so `tests/lua/depot-road.lua` checks those against a fake runtime. Request depots get freighters in their slot (3 unless a check needs otherwise). A request for 60 sticks, with 30 at a provider 10 tiles away and 40 at one 30 tiles away, must be met by two freighters leaving about a second apart, one to each provider, with all 5 back in the slot afterwards. A depot without freighters must send none and say so. Freighters put in the chest must move to the slot. On one road, a request depot set to request from buffer depots must take its 20 copper cable from a buffer 20 tiles away rather than a provider 10 tiles away, while a buffer beside it fills its 15 from the provider only. A request depot for 10 stone must take them all from a provider 30 tiles away at priority 9, none from one 10 tiles away at priority 2. Liquid depots must deliver 1200 water in loads of 500, take 300 steam from a liquid buffer at its 500 degrees rather than from a nearer liquid provider, and get freighters from robots through their truck chest. Freighters ctrl+clicked into a depot holding 95 must fill it to 100 and give the other 10 back, leaving none in the chest, while 20 iron plates moved in with them stay in the chest. Request depots destroyed or removed by script must leave all their freighters on the ground, including freighters still in a destroyed depot's chest (100 in a full slot plus 2 in the chest), and the remote interface must not overfill the slot. Freighters requested as from remote view must be capped at the slot's room, cancellable, and delivered into the slot by real construction robots from a storage chest (a powered roboport is built for this); a removal marked and cancelled must put its freighter back, and 2 freighters marked for removal must be carried back to storage by the robots. Mining a depot (refund to the miner) and clicking the slot need a player: `tests/lua/logistics.lua` and `tests/lua/control-events.lua` cover those, including that a freighter ghost requests freighters and that remote view never moves items by hand. Nothing may be left on the ground. Requests for unknown items, or with a count that isn't a number, are refused without changing the request; clones keep their request; and road is laid from a ghost on grass but not on water. The run lasts until the deliveries finish (at most 1,700 ticks).

The request panel needs a player, so check it in the graphical client. Open a request depot, choose an item and amount in the panel on the right of its window, and watch the status light beside them: hover it to check its tooltip shows the status in words, and that its colour follows (green while stocked or on its way, yellow while something is in the way, red when no provider has the item, grey with nothing requested). Then use Copy and Paste settings onto another request depot.

The headless server can't show sprites. So `tools/test_mod_setup.py` checks the depots' default orientation and loading zones with Lua 5.2: south by default, turning with the depot, and never on a pipe tile. In the graphical client, check that each depot's loading zone marking lies on the right side and stays there as you rotate the depot.

It runs with the base game only and, if your Factorio includes Space Age and the mods it needs, again with Space Age. The free headless server is enough. To look around yourself, open the newest save under `.local/mod-check/` in the full game with that run's `config.ini` and `mods` folder (see the depot instructions below).

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

## Recording results

Add a short entry to [test-results.md](test-results.md) for each test run. Include the commit tested, Factorio version, OS and graphics backend, then a passed, failed or untested result for each check. Attach screenshots to the pull request instead of committing them. Only images used by the README belong in `docs/images/`.
