# UPS benchmark

Players may run hundreds of depots and thousands of freighters on several surfaces for hundreds of hours, so the deliveries' cost per game tick matters as much as their behaviour. This page describes the benchmark, the baseline it was established with, and what pull requests must report.

## The map

`tests/factorio/ups-benchmark_0.1.0` builds the map when the save is created, from `layout.lua` and `presets.lua`. Both are plain Lua, so the in-game benchmark and the engine-free emulator build exactly the same map. On each surface (lab tiles, nothing else):

- a grid of junctions 16 tiles apart, joined by a randomised maze, so routes wind through U and S bends and branches end in dead ends;
- 12% of the remaining grid links added back as extra crossings, and dead-end spurs at 15% of junctions;
- every 8th grid line a 5-tile-wide road, with 30% of its links missing so traffic must drive around the gaps; all other roads 1 tile wide;
- provider and request depots in equal numbers beside 1-tile roads, with their loading zone on the road. 10% of request depots face a provider across the same road tile, so some deliveries cross a single tile; the rest go anywhere on the surface, up to about 500 tiles away in a straight line and much farther by road;
- 5 to 100 freighters (Transport Drones: drones) in each request depot; ten different items;
- Fuel depots, one for every ten depots, kept full of solid fuel. Jat'z freighters fill up there by themselves; Transport Drones keeps its drones' fuel in the request depot, so it doesn't build them. They are placed last, from a random stream of their own, so the other depots stand in exactly the same places for both mods.

The benchmark mod keeps every depot busy: once a second each provider and Fuel depot is filled up and each request depot is emptied, a sixtieth of the depots each tick, so demand never stops. Jat'z request depots ask for a full chest (48 stacks) of their item. A full tank lasts 2,000 tiles, longer than the measured window, so each Jat'z request depot's freighters start with part of a tank, spread evenly from 5% to full across the depots, as after hours of play; some of them go to fill up during the run.

| Preset | Surfaces | Depots | Freighters | Road tiles | Warm-up | Measured |
| --- | --- | --- | --- | --- | --- | --- |
| `quick` | 1 (160 × 160) | 40, and 4 Fuel depots | 1,048 | 4,443 | 1,800 ticks | 1,800 ticks |
| `standard` | 2 (352 × 352) | 160, and 16 Fuel depots | 4,403 | 35,141 | 7,200 ticks | 3,600 ticks |
| `stress` | 3 (352 × 352) | 600, and 60 Fuel depots | 16,293 | 52,476 | 7,200 ticks | 3,600 ticks |

The warm-up lets traffic reach a steady state before measuring (Transport Drones sends one drone per depot per second, so its fleets take about two minutes to get going). Results are only comparable on the same preset and the same map: changing `presets.lua`, `layout.lua` or the nauvis seed means recording the baseline again.

**Nauvis.** The benchmark builds its own surfaces, but nauvis, the game's first surface, still comes from the map generator, with biters. `tools/benchmark_ups.py` creates every save with the same seed (`NAUVIS_SEED`, passed as `--map-gen-seed`), so every save has the same nauvis: 35 enemy units near the spawn throughout the measured window, for both mods. Before the seed was fixed, each save got a random nauvis, and saves without biters measured about 0.45 ms less Jat'z script on the stress map, because freighters look for enemy units to run over only while there are some (issue #37). Biters are part of real games, so that cost is now always in the numbers.

## Running it

You need Factorio 2.1 (the free headless server is enough) and Python 3.

```sh
# Your branch against main, on your machine: what a pull request reports.
python3 tools/benchmark_ups.py --factorio /path/to/factorio/bin/x64/factorio --compare origin/main

# Only the working tree, or another preset.
python3 tools/benchmark_ups.py --factorio /path/to/factorio --preset stress --runs 1

# Transport Drones on the same map (a mod folder or zip), for the baseline.
python3 tools/benchmark_ups.py --factorio /path/to/factorio --preset stress --transport-drones /path/to/Transport_Drones
```

`--compare` packages the mod at the given revision with that revision's own `tools/package_mod.py` (from a temporary Git worktree) and the working tree with the current one, creates a save for each and runs them alternately, three runs each by default (`--runs`), so both meet the same machine state. Each run is Factorio's `--benchmark` over the warm-up plus measured ticks; only the measured ticks count. Workspaces, logs and saves stay under `.local/ups-benchmark/`. `--output FILE` also writes everything as JSON.

The table's columns, all medians over the runs:

| Column | Meaning |
| --- | --- |
| Mean update | Mean whole game update per tick, in ms. 16.67 ms is the most a tick can take for 60 UPS. |
| UPS | 1000 / Mean update: how fast this map alone could run. |
| Script | Mean `scriptUpdate`: all Lua, mostly the mod (the benchmark's own stocking is the same for every run). |
| Pathfinder | Mean `pathFinder`: the engine's path requests, including the mod's provider searches. |
| p99, Max | The 99th percentile and the slowest tick. A slow single tick is a visible stutter even when the mean is low. |
| Run spread | Slowest minus fastest run's mean: the noise on your machine. A change smaller than this isn't measurable. |
| Vehicles out | Mean freighters (drones) on the map, sampled every 10 s. |
| Delivered/min | Items emptied from request depots per minute. |

## Baseline

Recorded on November 6, 2026, all on nauvis seed 1340776561 (`NAUVIS_SEED`): Jat'z Distribution 0.1.1 making fewer engine objects per tick (mod code at `b0d2ac0`, run with `--compare` against `main` at `e207e78`, which has #49's spread checks), with the numbers from before #49 (`e54e75d`, recorded the same day), three runs each; fuel, research, circuit conditions and cargo paint; and Transport Drones 2.1.4 (Klonan/Transport_Drones `2.1-update` branch, commit `c5d0ce2`, the source of the 2.1.4 release), one stress run and three standard runs. Factorio 2.1.24 headless, base game only, on Linux with an AMD Ryzen 7 8845HS (16 threads) and 30 GB of memory. Both mods ran with their default settings, and nothing is researched. Transport Drones' request depots were kept fuelled, so its fuel bookkeeping ran but no fuel deliveries did; Jat'z freighters filled up at the Fuel depots.

### Stress (medians)

| | Mean update | UPS | Script | Pathfinder | p99 | Max | Vehicles out | Delivered/min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Transport Drones 2.1.4 | 21.806 | 46 | 0.411 | 1.024 | 26.925 | 37.561 | 12,961 | 985,560 |
| Jat'z Distribution (`b0d2ac0`) | 1.569 | 637 | 0.675 | 0.129 | 5.814 | 12.847 | 1,642 | 2,598,480 |
| Jat'z Distribution with #49 only (`e207e78`) | 2.550 | 392 | 1.033 | 0.341 | 11.442 | 18.858 | 1,640 | 2,474,400 |
| Jat'z Distribution before #49 (`e54e75d`) | 18.215 | 55 | 16.038 | 0.465 | 894.883 | 1,273.251 | 1,575 | 2,347,200 |

### Standard (three runs each, medians): what pull requests run

| | Mean update | UPS | Script | Pathfinder | p99 | Max | Run spread | Vehicles out | Delivered/min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Transport Drones 2.1.4 | 3.543 | 282 | 0.106 | 0.278 | 5.436 | 10.171 | 0.098 | 3,736 | 203,940 |
| Jat'z Distribution (`b0d2ac0`) | 0.433 | 2,308 | 0.149 | 0.019 | 1.341 | 2.414 | 0.012 | 388 | 701,040 |
| Jat'z Distribution with #49 only (`e207e78`) | 0.612 | 1,633 | 0.220 | 0.044 | 2.596 | 5.230 | 0.014 | 416 | 494,280 |
| Jat'z Distribution before #49 (`e54e75d`) | 1.050 | 952 | 0.635 | 0.047 | 31.510 | 44.944 | 0.012 | 412 | 484,320 |

Before #49, every request depot's once-a-second dispatch ran in the same tick, and each provider's unpromised stock was worked out by looking at every trip in the game. The earlier baselines (random nauvis) agree within noise: on November 5, `df05b7e` took 18.237 ms a tick on the stress map (worst tick 1,251.193 ms) and Transport Drones 21.968 ms. The first baseline (November 4, `e157cec`, before fuel) had Jat'z at 39.638 ms mean and a 2,800.848 ms worst tick on the stress map, and 1.538 ms and 73.421 ms on the standard map. `--compare e157cec` on the standard map gives 1.630 ms before and 1.056 ms after (-35.2%), with the worst tick from 73.724 to 45.566 ms. It comes with far fewer deliveries, though: freighters drive at half their old speed since #31, and items delivered per minute fell from 1,173,360 to 484,320 with about the same number of freighters out, so that drop wasn't a fix of the dispatch cost.

### What the baseline shows

- **Transport Drones' cost is its drones.** Almost all of its time is the engine moving about 13,000 units (`entityUpdate`); its script stays under half a millisecond.
- **Jat'z Distribution's script is now small and spread out.** It keeps far fewer freighters on the road (each trip carries up to 10 stacks, and the request depot's 48-slot chest limits what is still needed). Since the fix for issue #37 each depot and freighter is checked once a second in its own share of the second (AGENTS.md, **Spreading the work**), so the stress map's script takes under a millisecond a tick with no once-a-second spike. Its slowest ticks are Lua garbage collections in the mod's own state, whose last steps take longer the more engine objects the mod makes, so it makes few (AGENTS.md, **Spreading the work**): depots remember road lengths instead of asking the pathfinder for every search (each answer builds the whole route in the mod's state), and keep what they would otherwise read again. p99 is about 6 ms and the worst tick about 13 ms (`e207e78`: 11.4 and 18.9 ms). Remembered roads also free the pathfinder, so freighters set off sooner: 5% more delivered on the stress map, 42% more on the standard map with fewer freighters out.
- Jat'z delivers more per vehicle (10-stack trips against Transport Drones' single stacks), so compare `Delivered/min` alongside the times.

## Pull requests

Every pull request that changes the mod includes the before and after table from `tools/benchmark_ups.py --compare origin/main`, run on the contributor's machine (`.github/pull_request_template.md`). Because both columns come from the same machine, the percentage change in Mean update, and the p99 and Max, are what reviewers judge; the baseline above shows where those numbers sit against Transport Drones on the stress map. A change that adds work per depot, freighter or trip should also be tried on `--preset stress`.

## CI: the UPS benchmark check

CI has no Factorio, so its **UPS benchmark** check runs `tools/emulate_ups.py --base <base>` for pull requests that change the mod and adds its table to the check's summary and to a comment on the pull request (one comment, edited on later pushes; pull requests from forks get a read-only token, so for them the table is only in the summary). `tests/lua/ups-emulator.lua` loads the real `control.lua` and `scripts/` with Lua 5.2 against a fake runtime on the same map, with the same stocking: path requests are answered a tick later with the shortest road route, freighters drive it at the speed the mod gives them (so fuel burns, and a dry freighter crawls), stop commands complete after their wait, and `on_tick` runs every tick before the `on_nth_tick` handlers, as in the game. There are no enemies, so no freighter looks for any to run over. It counts exactly the Lua instructions the mod's own code executes in each measured tick, and nothing of the fake's: every function and computed property of the fake runtime is wrapped in one boundary that stops counting while the fake works (inventory loops, path answers, freighter movement) and takes off the boundary's own few instructions. It reports the mean, the 99th percentile and the worst tick. Instruction counts don't depend on the machine, so before and after differ only by the change, and repeated runs agree exactly. It also reports calls into the runtime's functions (`get_item_count`, `request_path`, `create_entity` and the like; property reads aren't counted), path requests and unit commands, which stand for work in the game's C++ that the emulation can't time. `tools/test_emulate_ups.py` checks the boundary: inert work added to a fake method or property must change nothing, and a loop added to a mod handler must add exactly its own instructions.

It can't measure the engine's own cost (pathfinding, unit movement), so it complements the in-game benchmark rather than replacing it. A rise of more than 5% in the mean or worst tick is flagged as a warning; the check fails only if the emulator itself breaks on the pull request. To run it locally: `python3 tools/emulate_ups.py --base origin/main` (`--preset quick` takes about a second, `standard` about 20 seconds, for each of the two revisions).
