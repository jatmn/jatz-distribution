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

The warm-up lets traffic reach a steady state before measuring (Transport Drones sends one drone per depot per second, so its fleets take about two minutes to get going). Results are only comparable on the same preset and the same map: changing `presets.lua` or `layout.lua` means recording the baseline again.

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

Recorded on November 5, 2026: Jat'z Distribution `df05b7e` (0.1.1, with fuel, research, circuit conditions and cargo paint) against Transport Drones 2.1.4 (Klonan/Transport_Drones `2.1-update` branch, commit `c5d0ce2`, the source of the 2.1.4 release). Factorio 2.1.24 headless, base game only, on Linux with an AMD Ryzen 7 8845HS (16 threads) and 30 GB of memory. Both mods ran with their default settings, and nothing is researched. Transport Drones' request depots were kept fuelled, so its fuel bookkeeping ran but no fuel deliveries did; Jat'z freighters filled up at the Fuel depots.

### Stress (one run each)

| | Mean update | UPS | Script | Pathfinder | p99 | Max | Vehicles out | Delivered/min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Transport Drones 2.1.4 | 21.968 | 46 | 0.410 | 1.041 | 27.655 | 40.396 | 12,962 | 972,180 |
| Jat'z Distribution `df05b7e` | 18.237 | 55 | 16.029 | 0.462 | 894.990 | 1,251.193 | 1,575 | 2,347,200 |

### Standard (three runs each, medians): what pull requests run

| | Mean update | UPS | Script | Pathfinder | p99 | Max | Run spread | Vehicles out | Delivered/min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Transport Drones 2.1.4 | 3.651 | 274 | 0.107 | 0.285 | 5.820 | 9.178 | 0.025 | 3,744 | 199,620 |
| Jat'z Distribution `df05b7e` | 1.086 | 921 | 0.664 | 0.048 | 32.136 | 49.827 | 0.023 | 412 | 484,320 |

The first baseline (November 4, `e157cec`, before fuel) had Jat'z at 39.638 ms mean and a 2,800.848 ms worst tick on the stress map, and 1.538 ms and 73.421 ms on the standard map. `--compare e157cec` on the standard map gives 1.630 ms before and 1.056 ms after (-35.2%), with the worst tick from 73.724 to 45.566 ms. It comes with far fewer deliveries, though: freighters drive at half their old speed since #31, and items delivered per minute fell from 1,173,360 to 484,320 with about the same number of freighters out, so the drop isn't a fix of the dispatch cost (still every request depot in one tick, below). Transport Drones' numbers match the first baseline's within run-to-run noise.

### What the baseline shows

- **Transport Drones' cost is its drones.** Almost all of its time is the engine moving about 13,000 units (`entityUpdate`); its script stays under half a millisecond.
- **Jat'z Distribution's cost is its script, and it comes in spikes.** It keeps far fewer freighters on the road (each trip carries up to 10 stacks, and the request depot's 48-slot chest limits what is still needed), yet on the stress map every request depot's once-a-second dispatch runs in the same tick and that tick takes over a second. Each dispatch ranks every provider on the surface, and each provider's unpromised stock is worked out by looking at every trip in the game, so the work grows with request depots × providers × trips. Each dispatch also counts the freighters in the request depot's chest slot by slot, more than once. Between those ticks the game is fast. Issue #37 tracks the fix; the benchmark and the CI emulation measure each step.
- Jat'z delivers more per vehicle (10-stack trips against Transport Drones' single stacks), so compare `Delivered/min` alongside the times.

## Pull requests

Every pull request that changes the mod includes the before and after table from `tools/benchmark_ups.py --compare origin/main`, run on the contributor's machine (`.github/pull_request_template.md`). Because both columns come from the same machine, the percentage change in Mean update, and the p99 and Max, are what reviewers judge; the baseline above shows where those numbers sit against Transport Drones on the stress map. A change that adds work per depot, freighter or trip should also be tried on `--preset stress`.

## CI: the UPS benchmark check

CI has no Factorio, so its **UPS benchmark** check runs `tools/emulate_ups.py --base <base>` for pull requests that change the mod and adds its table to the check's summary and to a comment on the pull request (one comment, edited on later pushes; pull requests from forks get a read-only token, so for them the table is only in the summary). `tests/lua/ups-emulator.lua` loads the real `control.lua` and `scripts/` with Lua 5.2 against a fake runtime on the same map, with the same stocking: path requests are answered a tick later with the shortest road route, freighters drive it at the speed the mod gives them (so fuel burns, and a dry freighter crawls), stop commands complete after their wait, and `on_tick` runs every tick before the `on_nth_tick` handlers, as in the game. There are no enemies, so impact checks find nothing. It counts the Lua instructions the mod executes, per tick, including the fake inventory and item stack calls it makes (a rough stand-in for what those API calls cost in the game) but not the engine's work the fake does for it (path answers, freighter movement) or the benchmark's stocking: the mean, the 99th percentile and the worst tick. Instruction counts don't depend on the machine, so before and after differ only by the change (repeated runs agree to within about 0.01%). It also reports path requests and unit commands, which stand for engine work the emulation can't time.

It can't measure the engine's own cost (pathfinding, unit movement), so it complements the in-game benchmark rather than replacing it. A rise of more than 5% in the mean or worst tick is flagged as a warning; the check fails only if the emulator itself breaks on the pull request. To run it locally: `python3 tools/emulate_ups.py --base origin/main` (`--preset quick` takes about a second, `standard` about 15 seconds).
