# Contributing

Jat'z Distribution is an in-development Factorio 2.1 mod. Report ordinary bugs in [Issues](https://github.com/jatmn/jatz-distribution/issues), including the mod commit/version, Factorio version, other enabled mods, reproduction steps, and relevant redacted logs. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

Read [AGENTS.md](AGENTS.md) before changing code or artwork, and [docs/testing.md](docs/testing.md) for the game test setup. Propose larger gameplay or artwork changes in an issue first. Keep pull requests focused, explain the behavior changed, and include the checks you ran. The owner reviews and merges changes; outside contributors' workflow runs require approval.

Use the pinned tool versions in `.github/workflows/area.yml`. For repository-tool changes, run the relevant `tools/test_*.py`, Ruff, and actionlint. Lua changes need Lua 5.2 syntax checks, Luacheck, and StyLua; mod behavior changes also need the Factorio checks in AGENTS.md. A passing `CI result` does not replace review of changes to workflows or their scripts.

Dependabot proposes weekly updates for Python development packages and GitHub Actions. Updates still need review and CI; they are not merged automatically. A Pullfrog action update must also update `PULLFROG_VERSION` in `tools/pullfrog_command.py` and pass its authorization tests. Preserve commit-SHA action pins, checksum-verified tool downloads, and the owner-only Pullfrog trigger.

Do not commit credentials, local environment files, machine paths, game binaries, saves, or private logs. Disable Blender's filename/hostname metadata when producing preview renders. Preserve the artwork sources and pixel content when cleaning metadata. New source files and third-party material must follow the licensing rules in AGENTS.md and NOTICE.

Use Conventional Commit PR titles such as `fix: preserve freighter cargo` or `ci: update release checks`; Release Please uses them for GitHub release notes. Add player-facing changes to the top `Version: Unreleased` section of `changelog.txt`, under a Factorio category such as `  Bugfixes:` with entries beginning `    - `. Leave version numbers to the release PR. See [the release guide](docs/releases.md) for packaging, credentials and publication.
