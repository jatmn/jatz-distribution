#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Create or update the repository's branch rulesets from .github/*-ruleset.json.

Needs the GitHub CLI (gh), signed in with admin rights to the repository. GitHub
only enforces rulesets on public repositories or with a paid plan.

Each file's ruleset is matched by name. A missing ruleset is created; an existing
one is updated, so rerunning applies later edits. If several share the name (two
concurrent runs can each create one), every run keeps the oldest (lowest ID),
deletes the rest and applies the file to it, so concurrent runs converge on one.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
FILES = ('.github/main-ruleset.json', '.github/ci-ruleset.json')


def gh(*args):
    result = subprocess.run(['gh', 'api', *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f'gh api {" ".join(args)} failed: {result.stderr.strip() or result.stdout.strip()}')
    return result.stdout


def ids_named(repository, name):
    listed = gh('--paginate', f'repos/{repository}/rulesets?includes_parents=false', '--jq', '.[] | {id, name}')
    return sorted(entry['id'] for entry in map(json.loads, filter(None, listed.splitlines()))
                  if entry['name'] == name)


def apply(repository, path):
    name = json.loads(path.read_text(encoding='utf-8'))['name']
    ids = ids_named(repository, name)
    if not ids:
        gh('-X', 'POST', f'repos/{repository}/rulesets', '--input', str(path))
        # List again: a concurrent run may have created one too.
        ids = ids_named(repository, name)
    if not ids:
        raise RuntimeError(f'{name!r} was created but is not listed')
    keep, *extras = ids
    for extra in extras:
        try:
            gh('-X', 'DELETE', f'repos/{repository}/rulesets/{extra}')
        except RuntimeError as error:
            if '404' not in str(error):  # another run already removed it
                raise
    gh('-X', 'PUT', f'repos/{repository}/rulesets/{keep}', '--input', str(path))
    remaining = ids_named(repository, name)
    if remaining != [keep]:
        raise RuntimeError(f'expected only ruleset {keep} named {name!r}, found {remaining}')
    return keep


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--repo', default='jatmn/jatz-distribution')
    args = parser.parse_args()
    failed = False
    for name in FILES:
        try:
            print(f'{name}: applied as ruleset {apply(args.repo, REPO / name)}')
        except (RuntimeError, OSError, ValueError, KeyError) as error:
            print(f'{name}: not applied: {error}', file=sys.stderr)
            failed = True
    raise SystemExit(1 if failed else 0)


if __name__ == '__main__':
    main()
