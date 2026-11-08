#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Keep release versions and Factorio notes consistent without changing gameplay.

Player-facing notes for the next release live in changelog/unreleased/*.txt, one
file per change, so ordinary pull requests do not edit changelog.txt. The release
workflow folds those files into changelog.txt and then removes them.
"""
import argparse
from datetime import date
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SEPARATOR = '-' * 99 + '\n'
PENDING = SEPARATOR + 'Version: Unreleased\n'
NOTES = Path('changelog/unreleased')
# Factorio shows categories in this order. Names outside it follow, alphabetically.
CATEGORY_ORDER = (
    'Major Features', 'Features', 'Minor Features', 'Graphics', 'Sounds', 'Optimizations',
    'Balancing', 'Combat', 'Circuit Network', 'Changes', 'Bugfixes', 'Modding', 'Scripting',
    'Gui', 'Info',
)


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


def notes_dir(root):
    return root / NOTES


def fragment_files(directory):
    """Regular *.txt note files, or an empty list when the directory is absent."""
    if not directory.exists():
        return []
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError('changelog/unreleased must be a directory')
    files = []
    for path in sorted(directory.iterdir(), key=lambda item: item.name):
        if path.is_symlink() or not path.is_file() or path.suffix != '.txt':
            raise ValueError(f'Player notes must be .txt files in changelog/unreleased: {path.name}')
        files.append(path)
    return files


def released_history(text):
    notes, history = split_notes(text)
    if notes is not None:
        raise ValueError('Move player notes out of changelog.txt into changelog/unreleased/<name>.txt')
    return history


def category_rank(name):
    try:
        return (0, CATEGORY_ORDER.index(name))
    except ValueError:
        return (1, name)


def parse_fragment(text, label):
    if not text.endswith('\n'):
        raise ValueError(f'{label} must end with a newline')
    entries, order, current, has_entry = {}, [], None, False
    for line_number, line in enumerate(text.splitlines(), 1):
        if '\t' in line or line.rstrip() != line:
            raise ValueError(f'{label}:{line_number} contains tabs or trailing whitespace')
        if not line:
            continue
        if re.fullmatch(r'  \S.*:', line):
            if current is not None and not has_entry:
                raise ValueError(f'{label} category {current} has no entry')
            current, has_entry = line[2:-1], False
            if current not in entries:
                entries[current] = []
                order.append(current)
            continue
        if line.startswith('    - ') or line.startswith('      '):
            if current is None or (line.startswith('      ') and not has_entry):
                raise ValueError(f'{label}:{line_number} lacks a category or preceding entry')
            entries[current].append(line)
            has_entry = True
            continue
        raise ValueError(f'{label}:{line_number} is not a changelog entry')
    if current is None or not has_entry:
        raise ValueError(f'{label} has no changelog entries')
    return [(name, entries[name]) for name in order]


def assemble(files):
    grouped = {}
    for path in files:
        for category, lines in parse_fragment(path.read_text(), path.name):
            grouped.setdefault(category, []).extend(lines)
    parts = []
    for category in sorted(grouped, key=category_rank):
        parts.append(f'  {category}:\n' + '\n'.join(grouped[category]) + '\n')
    return ''.join(parts)


def collect_notes(directory):
    files = fragment_files(directory)
    if not files:
        return None
    return assemble(files)


def has_pending_notes(root):
    if split_notes((root / 'changelog.txt').read_text())[0] is not None:
        return True
    return bool(fragment_files(notes_dir(root)))


def load_pending(root, source):
    if source is None:
        return collect_notes(notes_dir(root)), released_history((root / 'changelog.txt').read_text())
    source = Path(source)
    if source.is_symlink() or not source.is_dir():
        raise ValueError('--notes-from must be a directory')
    changelog = source / 'changelog.txt'
    if changelog.is_symlink() or not changelog.is_file():
        raise ValueError('--notes-from must contain changelog.txt')
    return collect_notes(source / NOTES), released_history(changelog.read_text())


def clear_fragments(root):
    for path in fragment_files(notes_dir(root)):
        path.unlink()


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
    history = released_history(text)
    notes = collect_notes(notes_dir(root))
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
    notes, history = load_pending(root, source)
    fragment_files(notes_dir(root))  # Reject a symlink note directory before writing.
    if source is not None and text.startswith(header):
        prior_date = next((line[6:] for line in text[len(header):].split(SEPARATOR)[0].splitlines()
                           if line.startswith('Date: ')), None)
        if prior_date:
            day = date.fromisoformat(prior_date).isoformat()
    if notes is None and text.startswith(header):
        validate_notes(text, info['version'])
        clear_fragments(root)
        return  # Keep the first preparation date, including on publication retries.
    body = notes if notes and notes.strip() else '  Info:\n    - No player-facing changes.\n'
    result = header + f'Date: {day}\n' + body + history
    validate_notes(result, info['version'])
    path.write_text(result)
    clear_fragments(root)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--date', required=True, help='UTC release preparation date, YYYY-MM-DD')
    parser.add_argument('--notes-from', type=Path,
                        help='Directory with main changelog.txt and changelog/unreleased notes')
    args = parser.parse_args()
    finalize(ROOT, args.date, args.notes_from)
