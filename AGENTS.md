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

`main` branch protection is kept in `.github/main-ruleset.json`, matching yuoki-quinityn: no deleting or force-pushing `main`, and changes go through pull requests with all review threads resolved. GitHub only enforces rulesets on private repositories with a paid plan, so apply it when the repository goes public (or the plan is upgraded). The same command applies later edits to the file. It updates the ruleset with the file's name if one exists, creates it otherwise, and stops if the name matches more than one ruleset:

```sh
REPO=jatmn/jatz-distribution FILE=.github/main-ruleset.json
NAME=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$FILE")
if IDS=$(gh api --paginate "repos/$REPO/rulesets?includes_parents=false" --jq ".[] | select(.name == \"$NAME\") | .id"); then
  case $(printf '%s' "$IDS" | grep -c .) in
    0) gh api -X POST "repos/$REPO/rulesets" --input "$FILE" ;;
    1) gh api -X PUT "repos/$REPO/rulesets/$IDS" --input "$FILE" ;;
    *) echo "Several rulesets are named '$NAME' ($IDS); delete the extras first." >&2; false ;;
  esac
else
  echo "Could not list existing rulesets; nothing was changed." >&2; false
fi
```

Pullfrog (`.github/workflows/pullfrog.yml`) runs an AI agent only when the owner posts a new issue or PR comment whose first line is `@pullfrog <instruction>`. `tools/pullfrog_command.py` checks that before any credentials are used; run `python3 tools/test_pullfrog_command.py` after changing either file.
