#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Load the packaged mod in Factorio and check that everything can be crafted, placed and driven.

Builds the mod zip with tools/package_mod.py, installs it in an isolated workspace
under .local/mod-check/ with the check mod from tests/factorio/, creates a save
(placing every depot in four directions with pipes and a fuelled, driven
freighter) and runs it for a few seconds. Runs once with the base game only and,
when the installation includes Space Age and everything it needs, once more with
Space Age. Also checks that every item, recipe and entity name the game shows has
an English translation. Works with the free headless server.

python3 tools/test_mod.py --factorio /path/to/factorio/bin/x64/factorio
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from package_mod import build

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / 'tests/factorio/jatz-distribution-check_0.1.0'
OURS = ('jatz-distribution', 'jatz-distribution-check')
# Dependency prefixes Factorio loads with the mod: required ('' and '~') and recommended ('+').
LOADED_WITH = re.compile(r'^\s*(?:~|\+)?\s*([A-Za-z0-9_-]+)')
EXPECTED = {'free_recipes': 8, 'ghosts': 28, 'placed': 28, 'rotations': 112, 'pipe_connections': 20}


def run(command, log, timeout=300):
    with log.open('w') as handle:
        return subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT, timeout=timeout).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--factorio', required=True, type=Path)
    parser.add_argument('--data-dir', type=Path)
    args = parser.parse_args()
    binary = args.factorio.expanduser().resolve()
    data = args.data_dir.resolve() if args.data_dir else binary.parents[2] / 'data'
    if not binary.is_file() or not (data / 'base/info.json').exists():
        parser.error('Factorio executable or data directory missing')
    bundled = bundled_mods(data)
    space_age = enabled_with('space-age', bundled)
    setups = {'base game': {'base'}, **({'Space Age': space_age} if space_age else {})}
    if not space_age:
        print('Space Age, or a mod it needs, is not installed: checking the base game only.')
    failed = False
    for label, enabled in setups.items():
        failed |= not check(binary, data, bundled, enabled, label)
    raise SystemExit(1 if failed else 0)


def bundled_mods(data):
    """The mods shipped in the data directory (base, Space Age and its parts), with their info.json."""
    return {path.parent.name: json.loads(path.read_text()) for path in data.glob('*/info.json')
            if path.parent.name != 'core'}


def enabled_with(name, bundled):
    """name and every bundled mod Factorio loads with it, or None if one is missing."""
    found, pending = set(), [name]
    while pending:
        mod = pending.pop()
        if mod in found:
            continue
        if mod not in bundled:
            return None
        found.add(mod)
        for dependency in bundled[mod].get('dependencies', []):
            if dependency.lstrip().startswith(('!', '?', '(?)')):
                continue
            match = LOADED_WITH.match(dependency)
            if match:
                pending.append(match.group(1))
    return found


def locale_keys(root=ROOT):
    """section.key for every English translation in the mod."""
    keys = set()
    for path in (root / 'locale/en').glob('*.cfg'):
        section = ''
        for line in path.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if line.startswith('[') and line.endswith(']'):
                section = line[1:-1]
            elif '=' in line and not line.startswith((';', '#')):
                keys.add(f'{section}.{line.split("=", 1)[0]}')
    return keys


def check(binary, data, bundled, enabled_mods, label):
    parent = ROOT / '.local/mod-check'
    parent.mkdir(parents=True, exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix='run-', dir=parent))
    mods = workspace / 'mods'
    mods.mkdir()
    package, _ = build(mods)
    shutil.copytree(CHECK, mods / CHECK.name)
    # List every bundled mod explicitly: Factorio enables installed ones that aren't listed.
    enabled = {name: name in enabled_mods for name in sorted(bundled)}
    enabled.update({name: True for name in OURS})
    (mods / 'mod-list.json').write_text(json.dumps({'mods': [
        {'name': name, 'enabled': state} for name, state in enabled.items()]}))
    write = workspace / 'write'
    write.mkdir()
    config = workspace / 'config.ini'
    config.write_text(f'[path]\nread-data={data.as_posix()}\nwrite-data={write.as_posix()}\n')
    save = workspace / 'jatz-distribution-check.zip'
    command = [str(binary), '--config', str(config), '--mod-directory', str(mods)]
    report_path = write / 'script-output/jatz-distribution-check.json'
    created = run(command + ['--create', str(save)], workspace / 'create.log')
    driven = created == 0 and save.exists() and run(
        command + ['--benchmark', str(save), '--benchmark-ticks', '180', '--benchmark-runs', '1'],
        workspace / 'drive.log') == 0
    # Factorio logs a checksum for every active mod, including ones without data stage files.
    loaded = sorted(set(re.findall(r'Checksum (?:for|of) ([A-Za-z0-9_-]+): \d+$',
                                   (workspace / 'create.log').read_text(), re.MULTILINE)))
    if not driven or not report_path.exists():
        for log in ('create.log', 'drive.log'):
            if (workspace / log).exists():
                print(f'--- {log}\n' + (workspace / log).read_text()[-6000:])
        print(f'{label}: FAILED. Evidence kept at {workspace}')
        return False
    report = json.loads(report_path.read_text())
    report['loaded_mods'] = loaded
    wrong = {key: report.get(key) for key, value in EXPECTED.items() if report.get(key) != value}
    expected_mods = sorted(enabled_mods | set(OURS) | {'core'})
    translations = locale_keys()
    untranslated = sorted({key for names in report.get('localised_names', {}).values()
                           for key in names.values() if key not in translations})
    if wrong or report.get('driven_tiles', 0) <= 1 or loaded != expected_mods or untranslated:
        problems = wrong or {'loaded': loaded, 'expected': expected_mods, 'untranslated': untranslated,
                             'driven_tiles': report.get('driven_tiles')}
        print(f'{label}: FAILED with {problems}. Evidence kept at {workspace}')
        return False
    (workspace / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'{label}: {package.name} passed: {report["placed"]} depots placed, {report["rotations"]} rotations, '
          f'{report["pipe_connections"]} pipe connections, {report["free_recipes"]} free recipes, '
          f'freighter drove {report["driven_tiles"]:.1f} tiles. Mods loaded: {", ".join(loaded)}')
    return True


if __name__ == '__main__':
    main()
