#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Keep release versions and Factorio notes consistent without changing gameplay."""
import argparse
from datetime import date
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SEPARATOR = '-' * 99 + '\n'
PENDING = SEPARATOR + 'Version: Unreleased\n'


def version_parts(value):
    if not isinstance(value, str) or not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', value):
        raise ValueError('Expected a three-component numeric version')
    parts = tuple(int(part) for part in value.split('.'))
    if max(parts) > 65535 or parts == (0, 0, 0):
        raise ValueError('Version is outside Factorio limits')
    return parts


def split_notes(text):
    if not text.startswith(PENDING):
        return None, text
    notes, separator, history = text[len(PENDING):].partition(SEPARATOR)
    if any(line.startswith('Date:') for line in notes.splitlines()):
        raise ValueError('Unreleased notes must not have a date')
    return notes, separator + history


def validate_notes(text, expected):
    """Check the documented Factorio changelog grammar, including numbered history."""
    sections = text.split(SEPARATOR)
    if sections.pop(0) or not sections:
        raise ValueError('Changelog needs 99-dash section separators')
    previous = None
    for section in sections:
        lines = section.splitlines()
        if not lines or not lines[0].startswith('Version: '):
            raise ValueError('A version must immediately follow each separator')
        version = version_parts(lines.pop(0)[9:])
        if previous is None and version != version_parts(expected):
            raise ValueError('Changelog top version does not match info.json')
        if previous is not None and version >= previous:
            raise ValueError('Changelog versions must be unique and newest first')
        previous = version
        category, has_entry, has_date, entries = None, False, False, set()
        for line in lines:
            if '\t' in line or line.rstrip() != line:
                raise ValueError('Changelog contains tabs or trailing whitespace')
            if not line:
                continue
            if line.startswith('Date: '):
                if has_date:
                    raise ValueError('Duplicate changelog date')
                has_date = True
            elif re.fullmatch(r'  \S.*:', line):
                category, has_entry = line[2:-1], False
            elif line.startswith('    - ') or line.startswith('      '):
                if category is None or (line.startswith('      ') and not has_entry):
                    raise ValueError('Changelog entry lacks a category or preceding entry')
                key = (category, line[6:])
                if key in entries:
                    raise ValueError('Duplicate changelog entry')
                entries.add(key)
                has_entry = True
            else:
                raise ValueError('Invalid changelog line')


def read_info(root):
    info = json.loads((root / 'info.json').read_text())
    version_parts(info['version'])
    if not re.fullmatch(r'[A-Za-z0-9_-]+', info['name']):
        raise ValueError('Invalid mod name')
    manifest = json.loads((root / '.github/release-please-manifest.json').read_text())
    if manifest.get('.') != info['version'] or (root / '.github/version.txt').read_text().strip() != info['version']:
        raise ValueError('Release version records must match info.json')
    return info


def package_metadata(root):
    info = read_info(root)
    text = (root / 'changelog.txt').read_text()
    notes, history = split_notes(text)
    validate_notes(history, info['version'])
    if notes is not None:
        major, minor, patch = version_parts(info['version'])
        info = {**info, 'version': f'{major}.{minor}.{patch + 1}'}
        version_parts(info['version'])
        validate_notes(SEPARATOR + f'Version: {info["version"]}\n' + notes + history, info['version'])
        text = SEPARATOR + f'Version: {info["version"]}\n  Info:\n    - Development snapshot.\n' + notes + history
        validate_notes(text, info['version'])
    return info, text


def finalize(root, day, source=None):
    info = read_info(root)
    day = date.fromisoformat(day).isoformat()
    path = root / 'changelog.txt'
    text = path.read_text()
    header = SEPARATOR + f'Version: {info["version"]}\n'
    notes, history = split_notes(text if source is None else source)
    if source is not None and text.startswith(header):
        prior_date = next((line[6:] for line in text[len(header):].split(SEPARATOR)[0].splitlines()
                           if line.startswith('Date: ')), None)
        if prior_date:
            day = date.fromisoformat(prior_date).isoformat()
    if notes is None and history.startswith(header):
        validate_notes(history, info['version'])
        return  # Keep the first preparation date, including on publication retries.
    body = notes if notes and notes.strip() else '  Info:\n    - No player-facing changes.\n'
    result = header + f'Date: {day}\n' + body + history
    validate_notes(result, info['version'])
    path.write_text(result)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--date', required=True, help='UTC release preparation date, YYYY-MM-DD')
    parser.add_argument('--notes-from', type=Path, help='Trusted main-branch player notes to refresh the release PR')
    args = parser.parse_args()
    finalize(ROOT, args.date, args.notes_from.read_text() if args.notes_from else None)
