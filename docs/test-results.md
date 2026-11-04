# Test results

Latest in-game results for the current artwork. The full screenshots and reports from every test round are kept in the private `jatz-distribution-archive` repository.

## Mod: passed (automated)

**November 3, 2026.** `tools/test_mod.py` with Factorio 2.1.24 (build 87808) headless on Linux, loading the packaged `jatz-distribution_0.1.0.zip`. It ran once with the base game only and once with Space Age, and both passed:

| Check | Result |
| --- | --- |
| All 9 recipes (seven depots, the freighter, road) available from the start and free | Passed |
| Each of the 7 depots placed in all 4 directions, as a ghost and for real (28 each) | Passed |
| Full rotation of every placed depot (112 steps) | Passed |
| All 20 pipe ports connect; containers hold items, tanks hold fluid | Passed |
| A character enters the fuelled freighter and drives it (28.5 tiles in 2 seconds) | Passed |
| Freighter at 75% size (sprites and boxes; box 1.125 × 3.375 tiles, checked headless) in the graphical client | Untested |
| New 64 px icons in the graphical client: depots face south and the freighter heads south-east | **Passed:** checked by the owner on November 3, 2026, in the inventory and Factoriopedia |
| Loading zone marking in the graphical client: one tile beyond the footprint on the loading side, south when placed unrotated, worn rather than bright white | **Passed:** checked by the owner on November 3, 2026 (Provider depots on desert) |
| Marking drawn above decoratives (plants, ground cover): moved from `decals` to `ground-patch-higher2` after the owner saw plants drawn over it | Untested since the change |
| Decorative rocks drawn over the marking (`floor`/`object` layers): building or turning a depot now clears decoratives overlapping its loading zone tile. Covered by the automated check (28 zones cleared, decoratives beyond kept) | Untested in the graphical client |
| Menu placement in the graphical client: our row directly above the car and tank row, ordered provider, request, buffer, liquid provider, liquid request, liquid buffer, fuel, freighter | **Passed:** checked by the owner on November 3, 2026, alongside the Yuoki mods |
| Delivery over road: a provider with 50 iron plates and a request for 30, 20 tiles apart, joined by a U-shaped road with concrete on the straight line. A freighter drove out and back along the road (10-tile detour) and the request depot received exactly 30; the provider kept 20 | Passed |
| Freighters stay on road: every 10 ticks, all four corners of every delivering freighter stood on road (45 samples) | Passed |
| A request depot whose loading zone is an isolated road tile receives nothing and reports no route; one without road at its loading zone sends no freighter and says so | Passed |
| Cargo keeps item data: modular armor arrives with its solar panel; with Space Age, food that left 50% spoiled arrives at least as spoiled | Passed |
| A request depot with no room fetches nothing (provider keeps all 50 copper, status "full") | Passed |
| A freighter destroyed on its way is replaced, and the request is filled (30 steel) | Passed |
| A request changed from plastic to circuits mid-trip loads no plastic | Passed |
| Road cut behind a loaded freighter: all 30 gears go back to the provider, none to the request, provider cooled down; the cut is noticed in 2 ticks (it used to take about 6 s of standing stuck) | Passed |
| Mending a gap in a road: delivery done 195 ticks (about 3 s, round trip included) after the repair, instead of waiting out the retry cooldown | Passed |
| Nearer of two providers removed mid-trip: the same freighter goes on to the other one and delivers | Passed |
| Request depot removed mid-trip: its freighter leaves at once and the provider keeps its stock | Passed |
| Provider nearest by road chosen: 8 tiles away in a straight line but 34 by road loses to 16 tiles on a straight road (all 10 coal from the farther one) | Passed |
| No road route to any provider: no freighter is sent at all | Passed |
| Depot road: laid under each depot's loading zone (over grass, which it hides); road ending one tile short of both depots' zones delivers (5 poles) | Passed |
| Depot road removed with its depot, putting back concrete and grass; existing road and a tile laid over depot road stay; a shared tile keeps its road until the second depot goes; nothing laid on water | Passed |
| Depot road when turning a depot, and mining or covering it by hand (Lua checks against a fake runtime; needs a player in game) | Passed headless; untested in the graphical client |
| Depot road art blending into player road, in the graphical client | Untested |
| Freighter slot: two freighters sent 60 ticks apart, one to each of two providers (30 + 30 sticks), all 5 back in the slot; no freighters, no trips (status "Waiting: no freighters"); freighters in the chest move to the slot; a destroyed request depot drops all 102 of its freighters (full slot of 100 plus 2 still in its chest) and a script-removed one its 3; the remote interface adds only up to the slot's limit of 100; 25 freighters are requested and taken away across several chest stacks | Passed |
| Mining a request depot hands all its freighters (slot and out) to the miner; the slot's one-stack limit counts freighters out; a freighter destroyed on the road is lost (Lua checks against a fake runtime) | Passed headless |
| Freighters requested as from remote view: 4 requested, a further request capped at the 5 that fit, cancelled (9) and 3 requested again; construction robots deliver them from storage into the slot (4 there, 2 left in storage) | Passed |
| Freighters taken away by robots (remote-view right-click): a removal marked and cancelled puts its freighter back; 2 marked are carried back to storage (slot 2, storage 4) | Passed |
| Slot clicks routed through control.lua: a freighter ghost requests (right-click: one), an empty cursor in remote view cancels, a remote right-click removes (again: cancels), remote view never moves items by hand; pipette over the slot picks up a freighter or its ghost, and only over the slot (Lua checks against a fake runtime) | Passed headless |
| Status light in the request panel (green, yellow, red, grey, with the status as tooltip), in the graphical client | Untested |
| Blueprint of a request depot keeps its request (tag) and freighters (insert plan for 3); the ghost built from it asks for 7 wood with 3 freighters requested; matching 1 to 3 requests 2; requests over the limit after filling by hand are trimmed (6 + 7 in → 3) | Passed |
| Copy and Paste settings, blueprint setup and building from a tagged ghost, routed through control.lua (Lua checks against a fake runtime) | Passed headless |
| Copy and Paste settings, copy and paste, and blueprints of request depots, in the graphical client | Untested |
| Ctrl+click of freighters into a request depot: 95 + 15 fills the slot to 100 and gives 10 back, none left in the chest; iron plates moved in with them stay in the chest; routed through control.lua for inventory changes and ctrl+click on the depot | Passed headless |
| A freighter request Factorio drops when part of it is filled by hand (5 asked, 1 put in) is requested again for the rest (4), also for a depot built over a blueprint ghost without its tags; taking freighters away stops topping up | Passed headless; the first fix failed in the owner's game (ghost built by hand, no tags), fixed since |
| Ctrl+click of freighters, and of other items, into a request depot, in the graphical client | Untested |
| Compact freighter line: the slot shows freighters at home, the line beside it how many are out ("3 out", always); full breakdown as tooltip, in the graphical client | Untested |
| Freighter slot in the request panel in the graphical client: ghost requests and robot removal in remote view, pipette (Q) over the slot | **Passed:** checked by the owner on November 3, 2026 |
| Nothing left on the ground by any check | Passed |
| Unknown items and non-numeric counts are refused without changing the request; a cloned request depot keeps its request; clearing works | Passed |
| Road laid from a ghost on grass; refused on water | Passed |
| A save made by the PR's first version, with a freighter on its way, loads and finishes the delivery | Passed (one-off check) |
| Road tile art, transitions and the item icon in the graphical client | Untested |
| Request panel beside the request depot's window (item, amount, status), and Copy and Paste settings between request depots | **Passed:** the owner reported the first version working in game on November 3, 2026; the panel is unchanged since |

## Depots: passed

**November 3, 2026.** Tested artwork commit `b3159d0`. Environment: Factorio 2.1.24 (build 87808) full client, Windows 11, Direct3D 11, AMD Radeon 780M.

![All seven depots in four rotations, in game](images/depots-all-rotations.jpg)

| Check | Result |
| --- | --- |
| All seven designs in all four rotations | Passed |
| Pipes: all 20 vanilla pipe connections join the building; the 172 unused edge positions stay unconnected; covers and connector overlap match the vanilla assembler | Passed |
| Placement: 28 held placements, 112 rotation steps, 28 blueprint ghosts, adjacent fit, overlap rejection | Passed |
| Save and reload, with a second launch | Passed |
| Independent role, clamp and housing colors; grayscale masks | Passed |
| Shadows (including at night), cargo openings, freighter and player beside every loading face | Passed |
| Liquid Buffer bolted pipe adapters, at play zoom and in four housing colors | Passed |
| Fuel depot hopper interior (hidden behind a closed hatch) | Untested |
| Automated dispatch, cargo transfer and one-way fluid flow | Not implemented yet |

![Paint layers changed one at a time](images/depots-paint-channels.jpg)

## Freighter: passed, with one known issue

**November 1, 2026.** Tested artwork commit `bc9dfc0`. Environment: Factorio 2.1.24 (build 87808) full client, Windows 11, Direct3D 11, AMD Radeon 780M.

![Default, alternate and single-layer colors](images/freighter-palettes.jpg)

| Check | Result |
| --- | --- |
| All 64 directions at two zoom levels match the exported frames, including the 63→0 wrap | Passed |
| In-game size (20% smaller than the first version) | Passed |
| Armored cab, fan, glass and wear details | Passed |
| Tint isolation (default, alternate, white, black and each layer alone) | Passed |
| Shadows at eight compass headings and at night | Passed |
| Driving forward, in full circles and in reverse | Passed |
| Selection and collision boxes | **Failed** in this artwork fixture, which inherits the base car's boxes (they cover only the middle of the truck). The mod's freighter now uses a 1.5 × 4.5 tile box measured from the sprites (scaled with the sprites to 75% in game); that still needs a graphical check (see Mod above). |
| Wheel animation | Not implemented yet (one static frame per direction) |

![Default and alternate trucks driving](images/freighter-driving.jpg)
