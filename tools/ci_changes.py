#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Select CI surfaces from the complete Git diff, without API file-list limits."""
import argparse
import os
import subprocess

CHECKS = ('lua', 'python', 'workflows')


def classify(paths):
    checks = dict.fromkeys(CHECKS, False)
    for path in paths:
        if path in {'.github/workflows/ci.yml', 'tools/ci_changes.py'}:
            return dict.fromkeys(checks, True)
        if path.endswith('.lua') or path in {
            '.luacheckrc', '.stylua.toml', '.github/workflows/lua.yml'
        }:
            checks['lua'] = True
        if path.endswith('.py') or path in {'.ruff.toml', '.github/workflows/python.yml'}:
            checks['python'] = True
        if path.startswith('.github/workflows/'):
            checks['workflows'] = True
    return checks


def changed_paths(base, head='HEAD'):
    # Disabling rename detection includes both the old and new surfaces. NUL
    # separators preserve filenames with whitespace/newlines. Git errors fail CI.
    result = subprocess.check_output([
        'git', 'diff', '--no-renames', '--name-only', '-z', base, head, '--'
    ])
    return [os.fsdecode(path) for path in result.split(b'\0') if path]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    args = parser.parse_args()
    for check, enabled in classify(changed_paths(args.base)).items():
        print(f'{check}={str(enabled).lower()}')
