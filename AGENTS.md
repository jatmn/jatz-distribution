# Contributor and agent rules

Jat'z Distribution is an in-development Factorio 2.1 mod. The artwork is finished and tested in game. Mod code (dispatch, cargo transfer, recipes) is the next stage.

## Where things are

- `README.md`: project overview and roadmap.
- `assets/quinityn-freighter/README.md` and `assets/depots/README.md`: what each asset folder holds, how to use the sprites in Factorio, and how to edit and re-render the models. Read the relevant one before changing artwork or tools.
- `docs/testing.md`: how to test in Factorio. Record outcomes in `docs/test-results.md`.
- `concepts/`: approved concept art. Preserve it unchanged.

## Artwork rules

- The `.blend` files under each `source/` folder are the masters. Edit them, then re-render. Never hand-edit sprites.
- The builder scripts (`build_master.py`, `build_depots.py`, `build_connector.py`) **overwrite** the `.blend` files. Carry manual edits into the builder, or don't run it.
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
| Mod | Everything else that isn't documentation: the mod source at the repository root | Lua and Python lint |
| Repository | `.github/`, the other `tools/` | Python lint, the `tools/test_*.py` repository tests, actionlint |

- Documentation (`README.md`, `AGENTS.md`, `docs/`, `concepts/`, licence files) runs no area checks.
- Shared lint configuration (`.luacheckrc`, `.stylua.toml`, `.ruff.toml`, `.gitattributes`) re-checks every area in full. Editing `ci.yml`, `area.yml` or the router runs everything.
- **Lua:** Lua 5.2 syntax, Luacheck and StyLua. Pull requests check the area's changed `.lua` files; pushes to `main` check all of them.
- **Python:** syntax and Ruff (syntax errors and Pyflakes). The frozen 1×1 archive tools are exempt from Pyflakes.
- **Blender sources** (`tools/check_blender_sources.py`, no Blender needed): every `.blend` is saved uncompressed by Blender 4.3; each model matches the hashes in its render, packaging and inspection records; freighter sprites match `checksums.json`; and the 1×1 archive matches its manifest. Re-render, re-package and re-inspect after editing a model, so the records follow it.
- The routing job runs `git diff --check` on every change, except binary files.

**Downloads stay small.** CI checks out text only: blobs over 256 KiB and the binary types in `.gitattributes` are never downloaded, and an area's art is fetched only for its Blender sources check. So text files must stay under 256 KiB; mark larger generated files as `binary` in `.gitattributes` (the routing job fails with that advice otherwise). Keep the checkout exclusions in `ci.yml` and `area.yml` equal to the binary patterns in `.gitattributes`; `tools/test_ci_changes.py` checks that they match.

**A green `CI result` only vouches for the PR's own workflow.** `pull_request` runs use the workflows from the PR, so a PR that edits `.github/workflows/`, `tools/ci_changes.py` or the tools they call can change what is checked, or skip it. Review those changes line by line before merging, whatever CI says; only the owner merges.

Before pushing, format Lua with `stylua --config-path .stylua.toml <files>`, and run `luacheck`, `ruff check --config .ruff.toml` and the relevant `tools/test_*.py`. The tool versions are pinned in the workflow files. When an area or check is added or renamed, update `tools/ci_changes.py`, `tools/test_ci_changes.py` and the jobs in `ci.yml` together. The depot packagers generate `depot-definitions.lua` and `depot-pipe-pictures.lua` through `assets/depots/tools/depot_lua.py`, already in StyLua format; `tools/test_depot_lua.py` requires the committed files to match.

## Licensing

The project is licensed LGPL-3.0-only. `COPYING.LESSER` and `COPYING` hold the license texts, and `NOTICE` lists third-party material. Keep all three at the repository root and in every release.

- Code adapted from Transport Drones (LGPL-3.0) is allowed. Each adapted file keeps LGPL-3.0 and starts with the attribution header from `NOTICE`, giving the upstream path and commit plus what changed and when. List the file under "Adapted files" in `NOTICE` in the same commit.
- Don't copy Transport Drones graphics; its readme credits them to a separate artist.
- Don't copy code from any other mod unless its license is compatible with LGPL-3.0. Record any such code in `NOTICE`.
- Don't add third-party artwork (Yuoki sprites, Factorio Wiki images and similar) to the repository. Link to it instead.
- Shipped graphics must be this project's own work, rendered from its Blender sources.
- New Lua and Python source files begin with `-- SPDX-License-Identifier: LGPL-3.0-only` or `# SPDX-License-Identifier: LGPL-3.0-only`. If the file has a `#!` shebang, the shebang stays on line 1 (it only works there) and the SPDX line comes directly after it.
- The mod package includes `COPYING`, `COPYING.LESSER` and `NOTICE`. It excludes `concepts/`, `docs/`, `tests/`, `tools/`, Blender sources and asset tools.

## Repository

Keep the repository private until the owner decides to publish it. Releases also need the owner's go-ahead.

Branch rules are kept as two rulesets matching yuoki-quinityn:
- `.github/main-ruleset.json`: no deleting or force-pushing `main`, and changes go through pull requests with all review threads resolved.
- `.github/ci-ruleset.json`: the `CI result` check must pass.

GitHub only enforces rulesets on private repositories with a paid plan, so apply them when the repository goes public (or the plan is upgraded), and again after editing either file. `python3 tools/apply_rulesets.py` needs `gh` signed in with admin rights. It creates a missing ruleset, updates an existing one by name, and keeps only the oldest if two runs created duplicates; a failed lookup changes nothing.

Pullfrog (`.github/workflows/pullfrog.yml`) runs an AI agent only when the owner posts a new issue or PR comment whose first line is `@pullfrog <instruction>`. `tools/pullfrog_command.py` checks that before any credentials are used; run `python3 tools/test_pullfrog_command.py` after changing either file.
