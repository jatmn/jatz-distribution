# Contributor and agent rules

Jat'z Distribution is a Factorio 2.1 road logistics mod, released on the [Factorio Mod Portal](https://mods.factorio.com/mod/jatz-distribution). Freighters deliver items from provider and buffer depots to request depots, and fluids between the liquid depots. They drive only on road, burn fuel and fill up at fuel depots by themselves. This file holds the rules for human and AI contributors. How each part of the mod works is in [`docs/design/`](docs/design/).

## Where things are

- `README.md`: the project overview. It follows the Mod Portal page (`portal/description.md`) in shorter form, so change both together.
- `portal/`: the Mod Portal page (summary, description and gallery), synced by each release (`tools/portal_page.py`, [`portal/README.md`](portal/README.md)). Keep its recipes, research and numbers in step with the mod.
- [`docs/guide.md`](docs/guide.md): the player guide. Update it with every player-facing change.
- [`docs/design/`](docs/design/): design notes for each subsystem (listed below). Read the relevant one before changing that subsystem, and update it in the same pull request.
- [`docs/runtime-state.md`](docs/runtime-state.md): freighter, fleet, undo and road states, save migration and the lifecycle invariants.
- [`docs/testing.md`](docs/testing.md): how to test, with and without Factorio. Record outcomes in [`docs/test-results.md`](docs/test-results.md), replacing the area's previous entry.
- [`docs/benchmark.md`](docs/benchmark.md): the UPS benchmark, its emulator and the recorded baseline.
- [`docs/releases.md`](docs/releases.md): Release Please, the changelog and Mod Portal publishing.
- [`assets/quinityn-freighter/README.md`](assets/quinityn-freighter/README.md), [`assets/depots/README.md`](assets/depots/README.md) (with the wrecks destroyed depots and freighters leave) and [`assets/roads/README.md`](assets/roads/README.md): what each asset folder holds, how the mod uses the sprites, and how to edit and re-render the models. Read the relevant one before changing artwork or tools.
- `concepts/`: approved concept art. Preserve it unchanged.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`SECURITY.md`](SECURITY.md): contribution guidance and private vulnerability reporting.

### Design notes

| Document | Covers |
| --- | --- |
| [Roads and deliveries](docs/design/roads-and-deliveries.md) | Road tiles and collision layers, road networks, picking a provider, trips, loading, road cuts, cargo, refunds, blueprints, undo, the depot panel |
| [Spreading the work](docs/design/spreading-the-work.md) | The once-a-second checks spread over ticks, search budgets, promise ledgers |
| [Fuel](docs/design/fuel.md) | Freighter tanks, burning, refueling legs, the Fuel depot |
| [Road tunnels](docs/design/road-tunnels.md) | Tunnel portals, planning a way through tunnels, driving underground |
| [Prototypes and placement](docs/design/prototypes-and-placement.md) | Art loaded from `assets/`, depot orientation and loading zone, depot road, freighter scale, the crafting-menu row |
| [Circuit network](docs/design/circuit-network.md) | Depot connectors and conditions, the road network monitor |
| [Logistic robots and replacing depots](docs/design/depots-robots-and-replacing.md) | Robot access, legacy depots, request and buffer depots replacing each other |
| [Compatibility](docs/design/compatibility.md) | Mining Drones and Milestones |
| [Research and recipes](docs/design/research-and-recipes.md) | The technology tree, research bonuses and every recipe |
| [Quality](docs/design/quality.md) | Requests by quality, better freighters and depots, quality upgrades |
| [Freighter network window](docs/design/network-window.md) | The shortcut window, its snapshots and layout guard |
| [Cargo paint](docs/design/cargo-paint.md) | Cargo colors from game data, painted drone prototypes, the `item-colors` mod data |

## Mod source

- The repository root is the mod's root: `info.json`, `settings.lua`, `data.lua`, `data-final-fixes.lua`, `prototypes/`, `locale/`, `migrations/` (prototype renames and one-time Lua scripts for saves from before), and the runtime `control.lua` with `scripts/`.
- The prototypes load the sprite helpers and sheets straight from `assets/` (paths in `prototypes/constants.lua`), so art is never copied.
- Prefix every prototype name with `jatz-`, and keep player-facing text in `locale/en/`.
- Use `scripts/trip-state.lua` for freighter lifecycle transitions, and keep engine effects in their domain owners ([`docs/runtime-state.md`](docs/runtime-state.md)).
- Changes take effect at once rather than waiting on timers: changing a request, laying road, or building, turning or flipping a depot clears cooldowns, and removed road makes the affected freighters plan again at their own next check ([roads and deliveries](docs/design/roads-and-deliveries.md)).
- Keep work done every tick from making garbage where it can: Lua's garbage collection is most of what still stutters on large maps, and its work per tick grows with what the mod allocates per tick ([spreading the work](docs/design/spreading-the-work.md)).
- **Check the Factorio 2.1 API, never assume it.** 2.1 removed and renamed much of 2.0's runtime API (`LuaEntity::fluidbox`, `defines.relative_gui_type.storage_tank_gui`, ...), and an unknown `defines` value or GUI filter only fails in game. Before using a runtime call, define, GUI parameter or prototype field, look it up in the 2.1 `runtime-api.json` / `prototype-api.json` (lua-api.factorio.com/latest) or the game's `data/changelog.txt`. The Lua harnesses' fakes accept anything unless made strict: `tests/lua/control-events.lua` holds 2.1's `defines.relative_gui_type` list and fails on any other name, and its fake GUI refuses a child named like a `LuaGuiElement` attribute or method (`items`, say), as the game does. Do the same for other API surfaces a change relies on.
- **Top-level locals.** Lua 5.2 compiles at most 200 active locals in one function, and a file's main chunk is one: every top-level `local` (constants and forward declarations too) stays active to the end of the file. `scripts/logistics.lua` once reached 200 and stopped the mod from loading, so it was split into modules (`impact`, `research`, `freighter-requests`, `blueprints`, `fuel`, `routes`, `cargo`, `circuit-switch`, `promises`). `logistics.lua` keeps the depots, trips, searches, dispatch and the `logistics.*` entry points, and hands each module the helpers it shares (`install`, binding them to locals of the same names). Code run for every freighter each second (`check_trip`) keeps calling locals, as do the busiest calls from searches (`enabled`, `promise`, `available`, kept as local aliases); don't turn those into table calls. New features belong in a module of their own, or the one whose subject they extend, called through its table; add a top-level `local` to `logistics.lua` only when a hot path needs it. `tools/test_mod_setup.py` fails when any `scripts/*.lua` has fewer than 20 top-level locals to spare: split the file further rather than work around it. A module that caches anything at file level must also be reloaded in `reset()` (`tests/lua/harness.lua`). The other compiler limits are far off: at most 255 upvalues a function (the most any function here uses is about 25) and 250 registers.
- `python3 tools/package_mod.py` builds `dist/jatz-distribution_<version>.zip`. It picks up `prototypes/`, `scripts/`, `locale/` and `migrations/` by glob; add new root files and new art to `mod_files()`.
- Release Please owns version bumps; follow [`docs/releases.md`](docs/releases.md) and put player-facing notes in a new `changelog/unreleased/<short-name>.txt`. Do not edit `changelog.txt` or version records in ordinary feature pull requests.
- After changing the mod, run `python3 tools/test_mod.py --factorio <factorio>` (the free headless server is enough; see [`docs/testing.md`](docs/testing.md)). Extend `tests/factorio/jatz-distribution-check_0.1.0/control.lua` along with new behavior. Its `EXPECTED_PORTS` table is the designed pipe layout, kept separate from the generated data on purpose: update it only for a deliberate port change.

## Artwork rules

- The `.blend` files under each `source/` folder are the masters. Edit them, then re-render. Never hand-edit sprites.
- The builder scripts (`build_master.py`, `build_depots.py`, `build_connector.py`) **overwrite** the `.blend` files. Carry manual edits into the builder, or don't run it.
- In-game icons (`assets/*/icons/`), and the 256 px technology icons (`assets/*/technology/`, no mipmaps), are made from the game sprites by `tools/make_icons.py`, so they match what players see: depots face south, and the freighter heads south-east. They're 64 px with three custom mipmaps (120 × 64 PNG, `icon_size = 64`), the layout Factorio 2.1 documents. Regenerate them whenever the sprite sheets change; never edit them by hand.
- The mod thumbnail (`thumbnail.png` at the repository root, shown in the in-game mod browser and on the mod portal) is made by the same `tools/make_icons.py` from the freighter icon's frame: 144 × 144 px, as Factorio 2.1 asks (auxiliary/mod-structure), with no mipmaps. It is in the package and in the freighter area, whose art check redraws it.
- Render intermediates (`masters/exr`, `masters/layers`, `masters/shadow-silhouettes`, `masters/render-inputs.json`, `frames/`, and the wrecks' `masters/wreck.blend`) are generated and git-ignored. Commit only the resulting `sheets/`, previews and hero renders. The one exception is `assets/depots/connectors/frames/`, which the tools read and which stays tracked.
- Paint masks must stay neutral grayscale. Metal, tires, glass, copper, lights and lenses belong in the untinted base layer.
- **Freighter:** keep the eight wheels, three cargo bays, exposed power unit and cab/clamp/cargo paint split. Render all 64 directions from the same camera, pivot and light. Direction 0 is north, turning clockwise. Change the in-game size with `constants.freighter_scale`, never in the artwork's helper.
- **Depots:** keep the fixed camera, ground pivot, `PROJECTION | tile grid compensation` parent, `SOCKET` markers and pipe shape-key drivers. Pipes must visibly reach the tank. After changes, run the geometry and junction inspectors, the renderer and packager, and the depot test fixture. The masters are lowered to 0.6 of their height above 0.75 (`assets/depots/tools/lower_depots.py`, the owner's choice, November 7, 2026, so they hide less of what stands behind them); a master rebuilt by `build_depots.py` must be lowered again.
- The 1×1 depots in `assets/depots/archive/1x1/` are retired. Keep them out of active builds and fixtures, and don't modify them.
- When changing the default palette, update every place it appears (listed in each asset README).

## Testing rules

- **UPS.** Players may run hundreds of depots and thousands of freighters on several surfaces for hundreds of hours, so performance is a requirement. A pull request that can change what the game does each tick includes the before and after table from `python3 tools/benchmark_ups.py --factorio <factorio> --compare origin/main` (the template's "UPS before and after" section). That covers `control.lua`, `scripts/`, `data-final-fixes.lua`, prototypes the game simulates (entities, units, tiles, collision layers), what runtime settings do, and the benchmark or emulator. Recipe, technology cost, locale, icon, artwork, documentation and tooling changes don't run it; write "Not applicable" and why (the owner, November 6, 2026). [`docs/benchmark.md`](docs/benchmark.md) has the full list. Changing a benchmark preset, the layout or `NAUVIS_SEED` invalidates the baseline in `docs/benchmark.md`, so re-record it in the same pull request. Keep the emulator's fakes in step with the runtime API the delivery code uses, and wrap every new fake function in `native` (computed properties in `properties`) so the fake's own work is never counted; `tools/test_emulate_ups.py` checks that.
- Factorio test runners (`tools/test_mod.py`, `tools/test_factorio.py`, `tools/test_depot_art.py`, `tools/benchmark_ups.py`) build their workspaces under `.local/`. Never touch the user's normal Factorio mods, settings or saves. Unit tests that need scratch files use Python's `tempfile`.
- Headless runs, HTML previews and contact sheets don't prove visual quality. Visual changes need a graphical-client check.
- Keep machine paths, Factorio binaries, logs, saves and Python environments out of commits.
- Screenshots go in the pull request, not the repository. Only images used by the README belong in `docs/images/`, and only the Mod Portal page's in `portal/gallery/` and `portal/images/`.

## Continuous integration

CI (`.github/workflows/ci.yml`) is routed by repository **area**, so a change only runs the checks for what it touched. `tools/ci_changes.py` reads the complete diff and decides; `CI result` is the one stable check to require. The routing job also runs `git diff --check` on every change, except binary files.

| Area | Paths | Checks (`.github/workflows/area.yml`) |
| --- | --- | --- |
| Freighter | `assets/quinityn-freighter/`, `thumbnail.png`, the freighter test mod, `tools/test_factorio.py`, `tools/prepare_test_mod.py` | Lua and Python lint; Blender sources check when models, images or records change |
| Depots | `assets/depots/` (with the 1×1 archive), the depot test mod, `tools/test_depot_art.py`, `tools/test_depot_lua.py` | Lua and Python lint; generated-Lua test; Blender sources check when models, images or records change |
| Mod | The mod source at the repository root, `tools/package_mod.py`, `tools/test_mod.py`, `tools/test_mod_setup.py` and the check mod, the UPS benchmark (`tools/benchmark_ups.py`, `tools/emulate_ups.py`, `tools/test_emulate_ups.py`, the benchmark mod, `tests/lua/ups-emulator.lua`), plus anything else that isn't documentation | Lua and Python lint; mod setup tests; for pull requests, the **UPS benchmark** check (`ups` in `ci.yml`): `tools/test_emulate_ups.py`, then the engine-free script cost against the base, in its summary and a pull request comment |
| Repository | `.github/`, `portal/`, `hk.pkl`, the other `tools/` | Python lint; `tools/test_ci_changes.py`, `test_pullfrog_command.py`, `test_check_blender_sources.py` and `test_apply_rulesets.py`; actionlint |

- Documentation (`README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, `docs/`, `concepts/`, licence files) runs no area checks.
- Shared lint configuration (`.luacheckrc`, `.stylua.toml`, `.ruff.toml`, `.gitattributes`) re-checks every area in full. Editing `ci.yml`, `area.yml` or the router runs everything.
- **Lua:** Lua 5.2 syntax, Luacheck and StyLua. Pull requests check the area's changed `.lua` files; pushes to `main` check all of them.
- **Python:** syntax and Ruff (syntax errors and Pyflakes). The frozen 1×1 archive tools are exempt from Pyflakes.
- **Blender sources** (`tools/check_blender_sources.py`, no Blender needed): every `.blend` is saved uncompressed by Blender 4.3; each model matches the hashes in its render, packaging and inspection records; each of the area's wrecks (`assets/<area>/remnants/`) was rendered from the committed `asset.json`, master, wreck builder and renderer (the art checkout also fetches the other area's `tools/` for them, and a change to `build_remnants.py` or `render_directions.py` runs both art checks); freighter sprites match `checksums.json`; the freighter and every depot have an icon in Factorio's 120 × 64 mipmap layout (decoded and checked for blank levels and stray pixels), made from the current sprite sheets; the loading zone marking is a 64 px tile, not blank, and current with its drawing script; and the 1×1 archive matches its manifest. The art jobs then install the pinned numpy, Pillow and OpenEXR, exercise the real EXR sprite extractor with a small fixture (`tools/test_art_dependencies.py`), redraw the icons (`tools/make_icons.py --check`) and the marking (`make_loading_zone.py --check`), and require the committed pixels to match exactly. Re-render, re-package and re-inspect after editing a model, so the records follow it.
- Changes to `requirements.txt` run both artwork checks, so dependency updates must reproduce the committed icons and marking.

**Downloads stay small for area checks.** Area jobs check out text only: blobs over 256 KiB and the binary types in `.gitattributes` are never downloaded, and an area's art is fetched only for its Blender sources check. So text files must stay under 256 KiB; mark larger generated files as `binary` in `.gitattributes` (the routing job fails with that advice otherwise). Keep the checkout exclusions in `ci.yml` and `area.yml` equal to the binary patterns in `.gitattributes`; `tools/test_ci_changes.py` checks that they match.

The **Installable package** job runs when the Mod or Repository area or either art check is selected (and not on Release Please's own version commit). It uses a full checkout, builds the ZIP and verifies its contents, version records and checksum, and runs `tools/test_releases.py` and `tools/test_portal_page.py`. It is included in `CI result`. Release automation is documented in [`docs/releases.md`](docs/releases.md).

**A green `CI result` only vouches for the PR's own workflow.** `pull_request` runs use the workflows from the PR, so a PR that edits `.github/workflows/`, `tools/ci_changes.py` or the tools they call can change what is checked, or skip it. Review those changes line by line before merging, whatever CI says; only the owner merges.

Before pushing, format Lua with `stylua --config-path .stylua.toml <files>`, and run `luacheck`, `ruff check --config .ruff.toml` and the relevant `tools/test_*.py`. The tool versions are pinned in the workflow files. When an area or check is added or renamed, update `tools/ci_changes.py`, `tools/test_ci_changes.py` and the jobs in `ci.yml` together. The depot packagers generate `depot-definitions.lua` and `depot-pipe-pictures.lua` through `assets/depots/tools/depot_lua.py`, already in StyLua format; `tools/test_depot_lua.py` requires the committed files to match.

## Licensing

The project is licensed LGPL-3.0-only. `COPYING.LESSER` and `COPYING` hold the license texts, and `NOTICE` lists third-party material. Keep all three at the repository root and in every release.

- Code adapted from Transport Drones (LGPL-3.0) is allowed. Each adapted file keeps LGPL-3.0 and starts with the attribution header from `NOTICE`, giving the upstream path and commit plus what changed and when. List the file under "Adapted files" in `NOTICE` in the same commit.
- Don't copy Transport Drones graphics; its readme credits them to a separate artist.
- Don't copy code from any other mod unless its license is compatible with LGPL-3.0. Record any such code in `NOTICE`.
- Don't add third-party artwork (Yuoki sprites, Factorio Wiki images and similar) to the repository. Link to it instead. The one exception, approved by the owner, is the Yuoki slag path art in `assets/roads/yuoki-railways/`, used for the road tile. It is CC BY-NC-SA 4.0, not LGPL: keep it byte-for-byte unchanged (`.gitattributes` exempts the folder from whitespace checks, since upstream's `Licence.txt` ends in a blank line), keep `Licence.txt` beside it and in the package, keep its `NOTICE` entry, and never use it commercially. Adding any other third-party art needs the owner's approval and the same treatment.
- Apart from that exception, shipped graphics must be this project's own work, rendered from its Blender sources or drawn by a committed, deterministic script that is their source (such as `assets/depots/tools/make_loading_zone.py`).
- New Lua and Python source files begin with `-- SPDX-License-Identifier: LGPL-3.0-only` or `# SPDX-License-Identifier: LGPL-3.0-only`. If the file has a `#!` shebang, the shebang stays on line 1 (it only works there) and the SPDX line comes directly after it.
- The mod package includes `COPYING`, `COPYING.LESSER`, `NOTICE` and the road art's `Licence.txt`. It excludes `concepts/`, `docs/`, `tests/`, `tools/`, Blender sources and asset tools.

## Repository

The repository is public. Releases need the owner's go-ahead. Report vulnerabilities privately using `SECURITY.md`; contribution guidance is in `CONTRIBUTING.md`.

Branch rules are kept as two rulesets, both applied and active:
- `.github/main-ruleset.json`: no deleting or force-pushing `main`, and changes go through pull requests with all review threads resolved.
- `.github/ci-ruleset.json`: the `CI result` check must pass.

After editing either file, run `python3 tools/apply_rulesets.py` (needs `gh` signed in with admin rights). It creates a missing ruleset, updates an existing one by name, and keeps only the oldest if two runs created duplicates; a failed lookup changes nothing.

Dependabot proposes weekly updates for pip and GitHub Actions (`.github/dependabot.yml`); review and test updates before merging. Keep GitHub secret scanning, push protection, private vulnerability reporting, and Python/Actions code scanning enabled. Code scanning runs from `.github/workflows/codeql.yml` (CodeQL advanced setup with the `security-and-quality` queries); keep CodeQL default setup off, since GitHub rejects advanced-setup results while it is on. Require approval for outside collaborators' workflow runs and keep action references pinned to commit SHAs.

Pullfrog (`.github/workflows/pullfrog.yml`) runs an AI agent only when the owner posts a new issue or PR comment whose first line is `@pullfrog <instruction>`. `tools/pullfrog_command.py` checks that before any credentials are used; run `python3 tools/test_pullfrog_command.py` after changing either file.
