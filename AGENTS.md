# Contributor and agent rules

Jat'z Distribution is an in-development Factorio 2.1 mod. The artwork is finished and tested in game, the freighter and depots are placeable and drivable with free recipes, and freighters deliver items from provider to request depots, driving only on road. Fuel, buffer and liquid deliveries, and balanced recipes, are next.

## Where things are

- `README.md`: project overview and roadmap.
- `assets/quinityn-freighter/README.md`, `assets/depots/README.md` and `assets/roads/README.md`: what each asset folder holds, how to use the sprites in Factorio, and how to edit and re-render the models. Read the relevant one before changing artwork or tools.
- `docs/testing.md`: how to test in Factorio. Record outcomes in `docs/test-results.md`.
- `concepts/`: approved concept art. Preserve it unchanged.

## Mod source

- The repository root is the mod's root: `info.json`, `data.lua`, `data-final-fixes.lua`, `prototypes/`, `locale/`, and the runtime `control.lua` with `scripts/`.
- The prototypes load the sprite helpers and sheets straight from `assets/` (paths in `prototypes/constants.lua`), so art is never copied. `prototypes/depot-definitions.lua` exists because `depot-pictures.lua` loads its data from that name.
- Prefix every prototype name with `jatz-`, and keep player-facing text in `locale/en/`.
- Placed unrotated, every depot has its loading zone to the south (`prototypes/orientation.lua`). Cargo and Fuel depots are shown half a turn from their artwork, with ports turned too, so their opening faces south; liquid depots load opposite their north-facing pipes. The loading zone marking is each depot's `integration_patch`, so it rotates with the depot. It draws on `ground-patch-higher2`: above decoratives such as plants, below rails, belts, items, buildings and vehicles. Some decoratives (medium and big sand rocks) draw on `floor` or `object`, which no ground layer can beat, so `scripts/loading-zone.lua` removes decoratives overlapping the loading zone tile, as Factorio does under buildings. It does this whenever a depot is built by any means or turned, and for existing depots on first load. `tools/test_mod_setup.py` checks the layout with Lua 5.2.
- **Roads and deliveries.** `jatz-road` (`prototypes/roads.lua`) is a floor tile like stone path. `prototypes/off-road.lua`, run from `data-final-fixes.lua` so every mod's tiles are included, gives every other tile the `jatz_off_road` collision layer. The delivering freighter, `jatz-freighter-drone` (`prototypes/freighter-drone.lua`), is a hidden unit whose only collision layer is that one (tiles only), so the engine's pathfinder routes it over road and nothing else; there is no road-network bookkeeping in Lua. Keep its `path_resolution_modifier` at the default: at 1 the engine finds no path for its 0.8-tile box on a one-tile road. `scripts/logistics.lua` registers provider and request depots, and once a second sends a freighter from each short request depot's loading zone to the nearest provider holding the item (both loading zones must be road). The freighter loads up to ten stacks, brings them back, unloads and is removed. A failed route puts that provider on a 30-second cooldown for that request. One trip per request depot at a time; no fuel yet. The request panel (`scripts/request-gui.lua`) is a relative GUI on the request depot's own window. `control.lua` owns every event registration, since Factorio keeps one handler per event. The remote interface `jatz-distribution` (`set_request`, `get_request`, `get_status`) is what the check mod uses.
- Our crafting-menu and Factoriopedia row sits directly above the vanilla car and tank row. `data-final-fixes.lua` reads that row's group and order after every other mod has loaded and places ours just before it (`prototypes/placement.lua`). Item order within the row: provider, request, buffer, liquid provider, liquid request, liquid buffer, fuel, the freighter, then road.
- `python3 tools/package_mod.py` builds `dist/jatz-distribution_<version>.zip` from an explicit file list. Add new runtime files to it. Bump `version` in `info.json` for releases.
- After changing the mod, run `python3 tools/test_mod.py --factorio <factorio>` (the free headless server is enough). It loads the packaged zip with and without Space Age, and checks crafting, placement, rotation, pipes, driving, and deliveries over road (a U-shaped road that must be followed, an isolated road tile that must get nothing, and a depot without road that must send nothing, with every freighter checked to stand wholly on road). Extend `tests/factorio/jatz-distribution-check_0.1.0/control.lua` along with new behavior. Its `EXPECTED_PORTS` table is the designed pipe layout, kept separate from the generated data on purpose: update it only for a deliberate port change.

## Artwork rules

- The `.blend` files under each `source/` folder are the masters. Edit them, then re-render. Never hand-edit sprites.
- The builder scripts (`build_master.py`, `build_depots.py`, `build_connector.py`) **overwrite** the `.blend` files. Carry manual edits into the builder, or don't run it.
- In-game icons (`assets/*/icons/`) are made from the game sprites by `tools/make_icons.py`, so they match what players see: depots face south, and the freighter heads south-east. They're 64 px with three custom mipmaps (120 × 64 PNG, `icon_size = 64`), the layout Factorio 2.1 documents. Regenerate them whenever the sprite sheets change; never edit them by hand.
- Render intermediates (`masters/exr`, `masters/layers`, `masters/shadow-silhouettes`, `masters/render-inputs.json`, `frames/`) are generated and git-ignored. Commit only the resulting `sheets/`, previews and hero renders. The one exception is `assets/depots/connectors/frames/`, which the tools read and which stays tracked.
- Paint masks must stay neutral grayscale. Metal, tires, glass, copper, lights and lenses belong in the untinted base layer.
- **Freighter:** keep the eight wheels, three cargo bays, exposed power unit and cab/clamp/cargo paint split. Render all 64 directions from the same camera, pivot and light. Direction 0 is north, turning clockwise.
- **Depots:** keep the fixed camera, ground pivot, `PROJECTION | tile grid compensation` parent, `SOCKET` markers and pipe shape-key drivers. Pipes must visibly reach the tank. After changes, run the geometry and junction inspectors, the renderer and packager, and the depot test fixture.
- The 1×1 depots in `assets/depots/archive/1x1/` are retired. Keep them out of active builds and fixtures, and don't modify them.
- When changing the default palette, update every place it appears (listed in each asset README).

## Testing rules

- Factorio test runners (`tools/test_factorio.py`, `tools/test_depot_art.py`) build their workspaces under `.local/`. Never touch the user's normal Factorio mods, settings or saves. Unit tests that need scratch files use Python's `tempfile`, which cleans up after itself.
- Headless runs, HTML previews and contact sheets don't prove visual quality. Visual changes need a graphical-client check.
- Keep machine paths, Factorio binaries, logs, saves and Python environments out of commits.
- Screenshots go in the pull request, not the repository. Only images used by the README belong in `docs/images/`.

## Continuous integration

CI (`.github/workflows/ci.yml`) is based on yuoki-quinityn's, but routed by repository **area** so a change only runs the checks for what it touched. `tools/ci_changes.py` reads the complete diff and decides; `CI result` is the one stable check to require.

| Area | Paths | Checks (`.github/workflows/area.yml`) |
| --- | --- | --- |
| Freighter | `assets/quinityn-freighter/`, the freighter test mod, `tools/test_factorio.py`, `tools/prepare_test_mod.py` | Lua and Python lint; Blender sources check when models, images or records change |
| Depots | `assets/depots/` (with the 1×1 archive), the depot test mod, `tools/test_depot_art.py`, `tools/test_depot_lua.py` | Lua and Python lint; generated-Lua test; Blender sources check when models, images or records change |
| Mod | The mod source at the repository root, `tools/package_mod.py`, `tools/test_mod.py` and its check mod, plus anything else that isn't documentation | Lua and Python lint |
| Repository | `.github/`, the other `tools/` | Python lint, the `tools/test_*.py` repository tests, actionlint |

- Documentation (`README.md`, `AGENTS.md`, `docs/`, `concepts/`, licence files) runs no area checks.
- Shared lint configuration (`.luacheckrc`, `.stylua.toml`, `.ruff.toml`, `.gitattributes`) re-checks every area in full. Editing `ci.yml`, `area.yml` or the router runs everything.
- **Lua:** Lua 5.2 syntax, Luacheck and StyLua. Pull requests check the area's changed `.lua` files; pushes to `main` check all of them.
- **Python:** syntax and Ruff (syntax errors and Pyflakes). The frozen 1×1 archive tools are exempt from Pyflakes.
- **Blender sources** (`tools/check_blender_sources.py`, no Blender needed): every `.blend` is saved uncompressed by Blender 4.3; each model matches the hashes in its render, packaging and inspection records; freighter sprites match `checksums.json`; the freighter and every depot have an icon in Factorio's 120 × 64 mipmap layout (decoded and checked for blank levels and stray pixels), made from the current sprite sheets; the loading zone marking is a 64 px tile, not blank, and current with its drawing script; and the 1×1 archive matches its manifest. The art jobs then install the pinned numpy and Pillow, redraw the icons (`tools/make_icons.py --check`) and the marking (`make_loading_zone.py --check`), and require the committed pixels to match exactly. Re-render, re-package and re-inspect after editing a model, so the records follow it.
- The routing job runs `git diff --check` on every change, except binary files.

**Downloads stay small.** CI checks out text only: blobs over 256 KiB and the binary types in `.gitattributes` are never downloaded, and an area's art is fetched only for its Blender sources check. So text files must stay under 256 KiB; mark larger generated files as `binary` in `.gitattributes` (the routing job fails with that advice otherwise). Keep the checkout exclusions in `ci.yml` and `area.yml` equal to the binary patterns in `.gitattributes`; `tools/test_ci_changes.py` checks that they match.

**A green `CI result` only vouches for the PR's own workflow.** `pull_request` runs use the workflows from the PR, so a PR that edits `.github/workflows/`, `tools/ci_changes.py` or the tools they call can change what is checked, or skip it. Review those changes line by line before merging, whatever CI says; only the owner merges.

Before pushing, format Lua with `stylua --config-path .stylua.toml <files>`, and run `luacheck`, `ruff check --config .ruff.toml` and the relevant `tools/test_*.py`. The tool versions are pinned in the workflow files. When an area or check is added or renamed, update `tools/ci_changes.py`, `tools/test_ci_changes.py` and the jobs in `ci.yml` together. The depot packagers generate `depot-definitions.lua` and `depot-pipe-pictures.lua` through `assets/depots/tools/depot_lua.py`, already in StyLua format; `tools/test_depot_lua.py` requires the committed files to match.

## Licensing

The project is licensed LGPL-3.0-only. `COPYING.LESSER` and `COPYING` hold the license texts, and `NOTICE` lists third-party material. Keep all three at the repository root and in every release.

- Code adapted from Transport Drones (LGPL-3.0) is allowed. Each adapted file keeps LGPL-3.0 and starts with the attribution header from `NOTICE`, giving the upstream path and commit plus what changed and when. List the file under "Adapted files" in `NOTICE` in the same commit.
- Don't copy Transport Drones graphics; its readme credits them to a separate artist.
- Don't copy code from any other mod unless its license is compatible with LGPL-3.0. Record any such code in `NOTICE`.
- Don't add third-party artwork (Yuoki sprites, Factorio Wiki images and similar) to the repository. Link to it instead. The one exception, approved by the owner, is the Yuoki slag path art in `assets/roads/yuoki-railways/`, used for the road tile. It is CC BY-NC-SA 4.0, not LGPL: keep it unchanged, keep `Licence.txt` beside it and in the package, keep its `NOTICE` entry, and never use it commercially. Adding any other third-party art needs the owner's approval and the same treatment.
- Apart from that exception, shipped graphics must be this project's own work, rendered from its Blender sources or drawn by a committed, deterministic script that is their source (such as `assets/depots/tools/make_loading_zone.py`).
- New Lua and Python source files begin with `-- SPDX-License-Identifier: LGPL-3.0-only` or `# SPDX-License-Identifier: LGPL-3.0-only`. If the file has a `#!` shebang, the shebang stays on line 1 (it only works there) and the SPDX line comes directly after it.
- The mod package includes `COPYING`, `COPYING.LESSER`, `NOTICE` and the road art's `Licence.txt`. It excludes `concepts/`, `docs/`, `tests/`, `tools/`, Blender sources and asset tools.

## Repository

Keep the repository private until the owner decides to publish it. Releases also need the owner's go-ahead.

Branch rules are kept as two rulesets matching yuoki-quinityn:
- `.github/main-ruleset.json`: no deleting or force-pushing `main`, and changes go through pull requests with all review threads resolved.
- `.github/ci-ruleset.json`: the `CI result` check must pass.

GitHub only enforces rulesets on private repositories with a paid plan, so apply them when the repository goes public (or the plan is upgraded), and again after editing either file. `python3 tools/apply_rulesets.py` needs `gh` signed in with admin rights. It creates a missing ruleset, updates an existing one by name, and keeps only the oldest if two runs created duplicates; a failed lookup changes nothing.

Pullfrog (`.github/workflows/pullfrog.yml`) runs an AI agent only when the owner posts a new issue or PR comment whose first line is `@pullfrog <instruction>`. `tools/pullfrog_command.py` checks that before any credentials are used; run `python3 tools/test_pullfrog_command.py` after changing either file.
