# UPS benchmark

Players may run hundreds of depots and thousands of freighters on several surfaces for hundreds of hours, so the deliveries' cost per game tick matters as much as their behaviour. This page describes the benchmark, the baseline it was established with, and what pull requests must report.

## The map

`tests/factorio/ups-benchmark_0.1.0` builds the map when the save is created, from `layout.lua` and `presets.lua`. Both are plain Lua, so the in-game benchmark and the engine-free emulator build exactly the same map. On each surface (lab tiles, nothing else):

- a grid of junctions 16 tiles apart, joined by a randomised maze, so routes wind through U and S bends and branches end in dead ends;
- 12% of the remaining grid links added back as extra crossings, and dead-end spurs at 15% of junctions;
- every 8th grid line a 5-tile-wide road, with 30% of its links missing so traffic must drive around the gaps; all other roads 1 tile wide;
- provider and request depots in equal numbers beside 1-tile roads, with their loading zone on the road. 10% of request depots face a provider across the same road tile, so some deliveries cross a single tile; the rest go anywhere on the surface, up to about 500 tiles away in a straight line and much farther by road;
- 5 to 100 freighters (Transport Drones: drones) in each request depot; ten different items.

The benchmark mod keeps every depot busy: once a second each provider is filled up and each request depot is emptied, a sixtieth of the depots each tick, so demand never stops. Jat'z request depots ask for a full chest (48 stacks) of their item.

| Preset | Surfaces | Depots | Freighters | Road tiles | Warm-up | Measured |
| --- | --- | --- | --- | --- | --- | --- |
| `quick` | 1 (160 × 160) | 40 | 1,048 | 4,443 | 1,800 ticks | 1,800 ticks |
| `standard` | 2 (352 × 352) | 160 | 4,403 | 35,141 | 7,200 ticks | 3,600 ticks |
| `stress` | 3 (352 × 352) | 600 | 16,293 | 52,476 | 7,200 ticks | 3,600 ticks |

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

Recorded on November 4, 2026, Jat'z Distribution `e157cec` (0.1.1) against Transport Drones 2.1.4 (Klonan/Transport_Drones `2.1-update` branch, commit `c5d0ce2`, the source of the 2.1.4 release). Factorio 2.1.24 headless, base game only, on Linux with an AMD Ryzen 7 8845HS (16 threads) and 30 GB of memory. Transport Drones ran with its default settings; the benchmark kept its request depots fuelled, so its fuel bookkeeping ran but no fuel deliveries did (Jat'z freighters don't use fuel yet).

### Stress (one run each)

| | Mean update | UPS | Script | Pathfinder | p99 | Max | Vehicles out | Delivered/min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Transport Drones 2.1.4 | 23.116 | 43 | 0.424 | 1.032 | 27.740 | 38.842 | 12,962 | 985,620 |
| Jat'z Distribution 0.1.1 | 39.638 | 25 | 36.183 | 1.104 | 2,159.189 | 2,800.848 | 1,048 | 4,555,560 |

### Standard (three runs each, medians): what pull requests run

| | Mean update | UPS | Script | Pathfinder | p99 | Max | Run spread | Vehicles out | Delivered/min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Transport Drones 2.1.4 | 3.775 | 265 | 0.112 | 0.287 | 6.245 | 9.885 | 0.115 | 3,742 | 205,020 |
| Jat'z Distribution 0.1.1 | 1.538 | 650 | 0.934 | 0.139 | 56.836 | 73.421 | 0.125 | 445 | 1,146,000 |

### What the baseline shows

- **Transport Drones' cost is its drones.** Almost all of its time is the engine moving about 13,000 units (`entityUpdate`); its script stays under half a millisecond.
- **Jat'z Distribution's cost is its script, and it comes in spikes.** It keeps far fewer freighters on the road (about 3.5 per request depot: each trip carries up to 10 stacks, and the request depot's 48-slot chest limits what is still needed), yet on the stress map every request depot's once-a-second dispatch runs in the same tick and that tick takes 2 to 3 seconds. Each dispatch ranks every provider on the surface, and each provider's unpromised stock is worked out by looking at every trip in the game, so the work grows with request depots × providers × trips. Between those ticks the game is fast. This is the first thing to improve; the benchmark and the CI emulation measure each step.
- Jat'z delivers more per vehicle (10-stack trips against Transport Drones' single stacks), so compare `Delivered/min` alongside the times.

## Pull requests

Every pull request that changes the mod includes the before and after table from `tools/benchmark_ups.py --compare origin/main`, run on the contributor's machine (`.github/pull_request_template.md`). Because both columns come from the same machine, the percentage change in Mean update, and the p99 and Max, are what reviewers judge; the baseline above shows where those numbers sit against Transport Drones on the stress map. A change that adds work per depot, freighter or trip should also be tried on `--preset stress`.

## CI: the UPS benchmark check

CI has no Factorio, so its **UPS benchmark** check runs `tools/emulate_ups.py --base <base>` for pull requests that change the mod and adds its table to the check's summary and to a comment on the pull request (one comment, edited on later pushes; pull requests from forks get a read-only token, so for them the table is only in the summary). `tests/lua/ups-emulator.lua` loads the real `control.lua` and `scripts/` with Lua 5.2 against a fake runtime on the same map, with the same stocking: path requests are answered a tick later with the shortest road route, freighters drive it at their prototype's speed, stop commands complete after their wait. It counts the Lua instructions the mod executes (not the fake's), per tick: the mean, the 99th percentile and the worst tick. Instruction counts don't depend on the machine, so before and after differ only by the change (repeated runs agree to within about 0.01%). It also reports path requests and unit commands, which stand for engine work the emulation can't time.

It can't measure the engine's own cost (pathfinding, unit movement), so it complements the in-game benchmark rather than replacing it. A rise of more than 5% in the mean or worst tick is flagged as a warning; the check fails only if the emulator itself breaks on the pull request. To run it locally: `python3 tools/emulate_ups.py --base origin/main` (`--preset quick` takes about a second, `standard` about 15 seconds).
