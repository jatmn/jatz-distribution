#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Route CI by repository area, from the complete Git diff, without API file-list limits.

Areas: freighter (truck artwork and its test mod), depots (depot artwork, the
1x1 archive and their test mod), mod (the game mod source at the repository
root, its packager and its check: everything that isn't another area or
documentation) and repository (CI, workflows and repo tools). Each changed area gets its own CI job. An area's art check (Blender
sources against their render records) only runs when its art or records change.

--base BASE              print the routing as GitHub step outputs.
--select AREA --base BASE --event EVENT --output DIR
                         write the area's Lua and Python files for its CI job.
"""
import argparse
import os
from pathlib import Path, PurePosixPath
import subprocess

AREAS = ('freighter', 'depots', 'mod', 'repository')
EMPTY_TREE = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
NO_COMMIT = '0' * 40
# Changes that can alter any area's results: re-check every area, including art.
EVERYTHING = {'.github/workflows/ci.yml', '.github/workflows/area.yml', 'tools/ci_changes.py'}
# Shared lint configuration: every area's code is checked again, in full.
SHARED_LINT = {'.luacheckrc', '.stylua.toml', '.ruff.toml', '.gitattributes'}
DOCUMENTATION = {'README.md', 'AGENTS.md', 'CONTRIBUTING.md', 'SECURITY.md', 'NOTICE', 'COPYING',
                 'COPYING.LESSER', '.gitignore'}
ART_SUFFIXES = {'.blend', '.png', '.webp', '.json'}
# The art check, icon generator and their Python dependencies cover both art areas.
ART_TOOLS = {'tools/check_blender_sources.py', 'tools/make_icons.py', 'tools/test_art_dependencies.py', 'requirements.txt'}


def area_of(path):
    """The area a path belongs to, or None for documentation and concept art."""
    if path.startswith(('assets/quinityn-freighter/', 'tests/factorio/freighter-art-check_')) or path in {
        'tools/test_factorio.py', 'tools/prepare_test_mod.py'
    }:
        return 'freighter'
    if path.startswith(('assets/depots/', 'tests/factorio/depot-art-check_')) or path in {
        'tools/test_depot_art.py', 'tools/test_depot_lua.py'
    }:
        return 'depots'
    if path in {'tools/package_mod.py', 'tools/test_mod.py', 'tools/test_mod_setup.py'}:
        return 'mod'
    if path.startswith(('.github/', 'tools/')):
        return 'repository'
    if path in DOCUMENTATION or path.startswith(('docs/', 'concepts/')):
        return None
    return 'mod'


def touches_art(path):
    """Whether a change can invalidate the Blender sources check for its area."""
    suffix = PurePosixPath(path).suffix
    return (path.startswith('assets/') and suffix in ART_SUFFIXES
            or path.startswith('assets/depots/archive/')
            or path in {'assets/depots/tools/render_connector.py', 'assets/depots/tools/make_loading_zone.py',
                        # The art jobs run the sprite extractor (tools/test_art_dependencies.py).
                        'assets/quinityn-freighter/tools/package_sprites.py'})


def classify(paths):
    checks = dict.fromkeys(('freighter', 'freighter_art', 'depots', 'depots_art', 'mod', 'repository'), False)
    for path in paths:
        if path in EVERYTHING:
            return dict.fromkeys(checks, True)
        if path in SHARED_LINT:
            for area in AREAS:
                checks[area] = True
            continue
        if path in ART_TOOLS:
            checks.update(repository=True, freighter_art=True, depots_art=True)
            # The Mod tests check the prototypes' icon_size against the checker's icon format.
            checks['mod'] = checks['mod'] or path == 'tools/check_blender_sources.py'
            continue
        area = area_of(path)
        if area is None:
            continue
        checks[area] = True
        # The mod loads the Lua sprite helpers and depot data in assets/*/factorio/.
        if path.startswith('assets/') and '/factorio/' in path and path.endswith('.lua'):
            checks['mod'] = True
        if area in ('freighter', 'depots') and touches_art(path):
            checks[f'{area}_art'] = True
    # An art check runs inside its area's job.
    for area in ('freighter', 'depots'):
        checks[area] = checks[area] or checks[f'{area}_art']
    return checks


def git(*args):
    return subprocess.check_output(['git', *args])


def resolve_base(base):
    # A push that creates the branch has no previous commit: compare with the empty tree.
    return EMPTY_TREE if base == NO_COMMIT else base


def changed_paths(base, head='HEAD'):
    # Disabling rename detection includes both the old and new surfaces. NUL
    # separators preserve filenames with whitespace/newlines. Git errors fail CI.
    result = git('diff', '--no-renames', '--name-only', '-z', resolve_base(base), head, '--')
    return [os.fsdecode(path) for path in result.split(b'\0') if path]


def area_files(area, pattern, base=None):
    """Tracked files of an area matching a pattern; with base, only those added or changed since it."""
    if base is None:
        listed = git('ls-files', '-z', '--', pattern)
    else:
        listed = git('diff', '--no-renames', '--name-only', '--diff-filter=ACMRT', '-z',
                     resolve_base(base), 'HEAD', '--', pattern)
    return [name for name in (os.fsdecode(item) for item in listed.split(b'\0') if item) if area_of(name) == area]


def select(area, base, event, output):
    """Write NUL-separated Lua and Python file lists for an area's CI job."""
    # Always read the diff first, so an unknown base revision fails instead of linting nothing.
    changed = changed_paths(base)
    # Pull requests lint changed Lua; pushes and lint/formatter/toolchain changes lint all of it.
    full = event != 'pull_request' or any(path in EVERYTHING or path in SHARED_LINT for path in changed)
    lua = area_files(area, '*.lua', None if full else base)
    python = area_files(area, '*.py')
    output.mkdir(parents=True, exist_ok=True)
    for name, files in (('ci-lua-files', lua), ('ci-py-files', python)):
        (output / name).write_bytes(b''.join(os.fsencode(path) + b'\0' for path in files))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--base', required=True)
    parser.add_argument('--select', choices=AREAS)
    parser.add_argument('--event')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.select:
        if not args.event or not args.output:
            parser.error('--select needs --event and --output')
        select(args.select, args.base, args.event, args.output)
    else:
        for check, enabled in classify(changed_paths(args.base)).items():
            print(f'{check}={str(enabled).lower()}')
