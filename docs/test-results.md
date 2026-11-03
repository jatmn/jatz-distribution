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
| New freighter collision box (1.5 × 4.5 tiles, measured from the sprites) in the graphical client | Untested |
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
| Road cut behind a loaded freighter: all 30 gears go back to the provider, none to the request, provider cooled down | Passed |
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
| Selection and collision boxes | **Failed** in this artwork fixture, which inherits the base car's boxes (they cover only the middle of the truck). The mod's freighter now uses a 1.5 × 4.5 tile box measured from the sprites; that still needs a graphical check (see Mod above). |
| Wheel animation | Not implemented yet (one static frame per direction) |

![Default and alternate trucks driving](images/freighter-driving.jpg)
