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
- every recipe takes the ingredients, time and amount in `tools/test_mod.py`'s `RECIPES` (with Space Age, `RECIPES_SPACE_AGE`, which adds the freighter made with carbon, also unlocked by Freight system); the nine depot, freighter and road recipes are locked at the start; the Freight system technology (after Engine) unlocks the six item and fuel depot, freighter and road recipes while the three liquid depots stay locked until Liquid freight (after Freight system and Fluid handling), and the road network monitor until its own research (after Freight system and Circuit network); and the road item lays the road tile;
- freighter speed has four levels then an infinite one, and item capacity ten and fluid capacity ten, each after the last (fluid capacity after Liquid freight); the mod's research levels read the game's own technologies (an infinite level written to 7 counts 6, item capacity 1-2 counts 2, fluid capacity 1-3 counts 3); and a pair on a force with six speed and two capacity levels must send its freighter at 2.2 times the speed, slow it to 1.6 times on the road when speed level 4 is undone, and bring 400 iron plates (4 stacks) in its first load, 2000 in all;
- every depot can be placed, as a ghost and for real, in all four directions, and rotated through a full turn;
- every depot destroyed facing east, south and west leaves its own wreck (`jatz-<role>-depot-remnants`), facing as it did;
- each depot's pipe ports match the designed layout (written out in the check mod, independently of the generated data) and all 20 connect;
- containers hold items and tanks hold fluid (the Fuel depot both: its port and fluid are on the hidden tank under it);
- the freighter item doesn't place the car (the `jatz-freighter-drivable` startup setting is off by default), whose entity stays defined but hidden, and a character can enter a fuelled freighter made by script and drive it;
- every item, recipe and entity name the game shows has an English translation;
- our row sits directly above the car and tank row in the same tab, with the items in their intended order;
- building a depot clears decoratives from its loading zone tile and keeps those beyond it, for all 7 depots in all 4 directions;
- deliveries stay on road. A provider holding 50 iron plates and a request depot asking for 30 stand 20 tiles apart, joined by a U-shaped road that detours 10 tiles south over concrete. The request must receive exactly 30, the freighter must reach the bottom of the U, and every 10 ticks all four corners of every delivering freighter must be on road. A request depot whose loading zone is an isolated road tile must receive nothing and report no route, and one without road at its loading zone must send nothing. More pairs on straight roads check that armor arrives with its equipment, and (with Space Age) food with its spoilage. They also check that a request depot with no room fetches nothing, and that a freighter destroyed on its way is replaced: its request is filled by another freighter, and robots bring a replacement freighter. Enemies: a medium biter held still on a road must be run over (killed by the freighter's impact damage) while a player standing beside it is unhurt, and that request must still be filled. Behemoth biters set on another freighter must destroy it, and it must explode and leave the freighter's own wreck (`jatz-freighter-remnants`) where it died, facing the way it drove. Its depot must ask robots for a replacement at once, and the request must be filled by the depot's other freighters from what the provider has left. Freighters out must show up in the pollution statistics. A request changed to another item mid-trip must not load the old one. Two road networks with stone walls between them, joined by a road tunnel's two portals (which must pair up), must bring a request depot its 10 radars from the provider on the other network, its freighter seen going under ground (`jatz-freighter-drone-underground`). A request depot filled by script while its freighter is on the way out must let its promise go: the freighter turns home without coming near the provider 48 tiles away, which keeps all 20 stone furnaces. The freighter must stand about 1 second (50 to 70 ticks) at the provider's loading zone before it loads, and again at the request depot's before it unloads. It must arrive at the provider in the empty (light grey) paint, and loading iron plates must swap it for the freighter in their paint (iron ore's map color), which drives them home; water must have its own paint. On another pair, a freighter with a mild fire-like sticker stuck to it (hitting every 10 ticks) must load without being swapped, the same sticker still stuck to the same freighter, so its damage goes on untouched; once the sticker wears off it must take iron plates' paint on the road home, and deliver its 10 plates. In alt mode the freighter must show no icon when it reaches the provider empty and the iron plate icon when it gets home loaded, and a freighter carrying water must show the water icon; the freighter with the sticker must show it both before and after it is painted. When the road is cut behind a loaded freighter, the cargo must go back to the provider within 4 seconds (its 1-second stop to unload included), rather than after the freighter stands stuck. A road with a gap must be used within about 9 seconds of being mended (the round trip with its two 1-second stops), well before a delivery that waited out the 10-second retry cooldown could arrive. When the nearer of two providers is removed mid-trip, the same freighter must go on to the other one. When a request depot is removed mid-trip, its freighter must leave within 2 ticks. Of two providers, the one 8 tiles away in a straight line but 34 tiles by road must lose to one 16 tiles away on a straight road; and a request with no road route to any provider or buffer depot must never send a freighter. Blueprinting a request depot (7 wood, 3 freighters) must give the blueprint its request and its freighters as tags (no freighter insert plan), and a depot built from that ghost must ask for 7 wood and request 3 freighters. The blueprint must also hold the request and freighters as request settings for parametrisation (7 wood, 3 freighters); changed to 11 iron plates and 5 freighters, as parametrising them would, and pasted, the depot built from it must ask for 11 iron plates and 5 freighters, with no request settings left in the world. The freighters must be a number with no signal, so parametrising offers no item for them. Request settings beside a depot a script builds at once without tags must give it their request and freighters and go, and a request at a condition's int32 limit must go in the settings while one above it goes in tags only, the settings' tag setting it on a depot the blueprint is pasted over. A depot requesting freighter items as cargo with 3 freighters must keep both in its settings, and the depot built from them must ask for both. A blueprint of a depot with no request, pasted over one asking for 7 wood and 5 freighters, must clear both, and a forced paste of an item depot's blueprint over a liquid depot must leave its request and freighter requests alone. Matching a depot holding 1 freighter to 3 must request 2, and freighter requests that no longer fit after the slot is filled by hand must be trimmed. Copy and Paste settings, blueprint setup and building with tags need a player: `tests/lua/control-events.lua` fires them through `control.lua`. The freighter's collision box must be 75% of the measured 1.5 × 4.5 tiles. Depots lay road under their loading zone: a provider and a request depot whose road stops one tile short of each loading zone must still deliver. Removing depots must put back concrete and grass. Road that was already there, or a tile laid over the depot's road, must stay. Two depots loading from one tile must keep the road until the second goes, and nothing may be laid on water. Turning a depot, mining or covering its road by hand, and loading older saves need a player, so `tests/lua/depot-road.lua` checks those against a fake runtime. Request depots get freighters in their slot (3 unless a check needs otherwise). A request for 60 sticks, with 30 at a provider 10 tiles away and 40 at one 30 tiles away, must be met by two freighters leaving about a second apart, one to each provider, with all 5 back in the slot afterwards. A depot without freighters must send none and say so. Freighters put in the chest must move to the slot. On one road, a request depot set to request from buffer depots must take its 20 copper cable from a buffer 20 tiles away rather than a provider 10 tiles away, while a buffer beside it fills its 15 from the provider only. A request depot for 10 stone must take them all from a provider 30 tiles away at priority 9, none from one 10 tiles away at priority 2. A request depot set to full loads only, asking for 30 iron chests (less than a load, so a full load is all 30), must take all 30 from a provider 24 tiles away holding 40, none from one 10 tiles away holding 10. Liquid depots must deliver 1200 water in loads of 750, take 300 steam from a liquid buffer at its 500 degrees rather than from a nearer liquid provider, take 300 crude oil from a liquid buffer when not set to request from buffer depots and the only liquid provider is empty, and get freighters from robots through their truck chest. Freighters ctrl+clicked into a depot holding 95 must fill it to 100 and give the other 10 back, leaving none in the chest, while 20 iron plates moved in with them stay in the chest. Request depots destroyed or removed by script must leave all their freighters on the ground, including freighters still in a destroyed depot's chest (100 in a full slot plus 2 in the chest), and the remote interface must not overfill the slot. Freighters requested as from remote view must be capped at the slot's room, cancellable, and delivered into the slot by real construction robots from a storage chest (a powered roboport is built for this); a removal marked and cancelled must put its freighter back, and 2 freighters marked for removal must be carried back to storage by the robots. Mining a depot (refund to the miner) and clicking the slot need a player: `tests/lua/logistics.lua` and `tests/lua/control-events.lua` cover those, including that a freighter ghost requests freighters and that remote view never moves items by hand. Nothing may be left on the ground. Requests for unknown items, or with a count that isn't a number, are refused without changing the request; clones keep their request; road is laid from a ghost on grass but not on water; and nothing but belts, pipes, train tracks and vehicles can be placed on road: not a depot or its ghost (though one whose loading zone alone is on road can), a pole, an inserter or a chest; and road can't be laid under a pole, a closed gate or a gate standing open. Fuel: a freighter set to fuel for 10 tiles, sent to a provider 20 tiles east, must first stop at the Fuel depot 4 tiles west, take 5 of its 10 coal (20 MJ), then fetch its 10 iron ore and park with 19 MJ left; the first must show its fuel on hover as a yellow status (`custom_status`, read back) when it reaches that Fuel depot low; another must fill up with 50 of a Fuel depot's 100 petroleum gas (the mod's `data-final-fixes.lua` makes it burn at 0.4 MJ, as the base game has no burnable fluid) and fetch 10 copper ore; one with an empty tank, whose only Fuel depot holds stone, must stay home with the status `no-fuel` (yellow: its road reaches that Fuel depot, though Fuel depots with fuel stand on other roads) until coal is put in that depot at tick 300, then set off at once (its status `delivering` by tick 420, well before its 10-second wait ends), crawl there, fill up and fetch 10 sulfur. Every Fuel depot must get its hidden tank, facing as it does, and one turned by script must turn its tank within a second. A Fuel depot holding 10 coal and 1,234 water must keep both when cloned, whether alone (`LuaEntity::clone`, its new tank given the original's fluid) or with its hidden tank (`LuaSurface::clone_entities`, that tank kept), each clone with exactly one tank, and the original unchanged. Every depot must take a red wire in all four directions. A provider holding 30 iron chests and switched on only while its own contents hold more than 25, with two request depots for 10 each on its road, must send exactly one freighter: 10 delivered in all and 20 left, since the 20 left once the first freighter's 10 are counted are not more than 25. A provider switched off by its circuit condition (a combinator's signal-A > 0) must supply nothing, its request depot finding no provider, until the combinator switches it on at tick 300; a request depot switched off must send nothing, saying so, until then. A road network monitor beside one road must show the 1000 water of the liquid provider on that road but not the switched-off provider's stone walls, the request depot's, or the small lamps on another road, and after the deliveries the provider's 10 walls left. The switched-off provider's hover status must read "switched off by its circuit condition" with a red light, and go back to its own once switched on. Two more monitors on that road, reading what request depots hold and what they still need, must show no walls and 10 walls needed before tick 300, and 10 walls held and none needed after; an unknown reading must be refused. A provider holding 300 wood wired to one holding 2800 (the wire carries 3100), and another holding 300 wired to a road network monitor that counts the 2800, must both stay off for wood > 3000 read from the circuit network, and be on for wood > 2700; a provider reading its own 200 wood, with no wire, must be on for wood > 100 and off for wood > 300, and an unknown mode must be refused. 200 wood taken out of the wired depot in the same tick it is read (after the mod sampled it) must leave its condition reading the 2800 elsewhere, as the wire still carries its 300. Another force's provider on that road, holding 50 copper plates, must be left out of the monitor until its force merges into the player's at tick 299, then counted with no road or depot changing. A monitor counting a provider's 100 iron plates, cloned at tick 301 and wired to that provider, must put nothing on the wire before its first update (200, not 300), so the provider's iron plate > 0 read from the network must not hold. The run lasts until the deliveries finish (at most 1,700 ticks).

The cargo paint is only colors, so look at it in the graphical client too: freighters heading to a provider have light grey cargo bays, and ones coming back carry their load's color (blue-grey for iron plates, orange for copper, blue for water), with the cab and clamps unchanged.

The request panel needs a player, so check it in the graphical client. Open a liquid request depot and check your inventory is on the left of the tank window, and that ctrl-clicking a freighter there fills the slot (shift-click moves one stack). Open a request depot, choose an item and amount in the panel on the right of its window, and watch the status light beside them: hover it to check its tooltip shows the status in words, and that its colour follows (green while stocked or on its way, yellow while something is in the way, red when no provider or buffer depot has the item, grey with nothing requested). Then use Copy and Paste settings onto another request depot. Check the **Full loads only** checkbox on a request, a buffer, a liquid request and a liquid buffer depot: it sits under the request row (below **Request from buffer depots** on a request depot), its caption and tooltip fit the panel (the liquid tooltip names 500), and with it ticked while no provider holds a full load the light turns yellow and its tooltip reads "Waiting for a full load". Ticking it on one depot must show within half a second in another player's open panel of that depot, and pasting settings must carry it. Open a provider and a buffer depot and check the **Logistic robots can use it** checkbox under the priority slider: unticked on a new depot, its caption and tooltip fit the panel, and the depot's own window (a logistic container's, with a buffer depot's logistic requests) still has the panel on its right; ticked inside a roboport's range, robots take from it for a requester chest, and unticking stops them. Load a save made before provider and buffer depots were logistic containers and check its depots still face the way they did, with their contents and settings. Open a fuel depot and check the panel beside its window shows the fluid piped in and its amount, and that the flush button empties it. Hover a freighter on the road and check its fuel shows as a status line (green, yellow when low, red when dry); open a request depot and check the fuel line under its freighter slot, and its tooltip listing every freighter's fuel. Put a fuel item worth more than 20 MJ in a fuel depot (a mod's) and check the freighter's hover shows the whole amount after filling up, and still does on its next trip.

The headless server can't show sprites. So `tools/test_mod_setup.py` checks the depots' default orientation and loading zones with Lua 5.2: south by default, turning with the depot, and never on a pipe tile. In the graphical client, check that each depot's loading zone marking lies on the right side and stays there as you rotate the depot.

With `--mod path/to/Mining_Drones_2.1.1.zip` (or Mining Drones 2 Remastered's or Mining Drones Mod's zip, downloaded from the mod portal), that mod loads too, and a request depot must also fetch 30 of the 40 iron ore in a mining depot's output, from the road the mining depot lays behind it. With `--mod path/to/Milestones_1.5.2.zip`, Milestones must log that it loaded our preset addon when the game is created. Milestones only tracks forces with players, so whether the milestones are reached needs the graphical client: start a new game with Milestones, craft a freighter, and check that the "first freighter" milestone is announced and listed under Progress. Every run, with or without Milestones, also checks that each item in the addon is a real item. The option can be repeated for other mods, which then only have to load.

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

## Performance (UPS)

`tools/benchmark_ups.py` measures the game update time Jat'z Distribution's deliveries cost on a large generated road map, and `tools/emulate_ups.py` compares the mod's script cost with another revision without the game. Pull requests that change the mod must include the benchmark's before and after table. See [benchmark.md](benchmark.md).

## Recording results

Add a short entry to [test-results.md](test-results.md) for each test run. Include the commit tested, Factorio version, OS and graphics backend, then a passed, failed or untested result for each check. Attach screenshots to the pull request instead of committing them. Only images used by the README belong in `docs/images/`.
