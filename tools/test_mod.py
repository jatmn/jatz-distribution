#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Load the packaged mod in Factorio and check that everything can be crafted, placed and driven.

Builds the mod zip with tools/package_mod.py, installs it in an isolated workspace
under .local/mod-check/ with the check mod from tests/factorio/, creates a save
(placing every depot in four directions with pipes and a fuelled, driven
freighter) and runs it for a few seconds. Runs once with the base game only and,
when the installation includes them, once more with the Space Age expansion mods.
Works with the free headless server.

python3 tools/test_mod.py --factorio /path/to/factorio/bin/x64/factorio
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from package_mod import build

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / 'tests/factorio/jatz-distribution-check_0.1.0'
# Expansion mods shipped with the game; Factorio enables installed ones unless told otherwise.
EXPANSION = ('elevated-rails', 'quality', 'recycler', 'space-age')
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
    expansion = [name for name in EXPANSION if (data / name / 'info.json').exists()]
    setups = {'base game': False, **({'Space Age': True} if expansion else {})}
    failed = False
    for label, with_expansion in setups.items():
        failed |= not check(binary, data, expansion, with_expansion, label)
    raise SystemExit(1 if failed else 0)


def check(binary, data, expansion, with_expansion, label):
    parent = ROOT / '.local/mod-check'
    parent.mkdir(parents=True, exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix='run-', dir=parent))
    mods = workspace / 'mods'
    mods.mkdir()
    package, _ = build(mods)
    shutil.copytree(CHECK, mods / CHECK.name)
    enabled = {name: True for name in ('base', 'jatz-distribution', 'jatz-distribution-check')}
    enabled.update({name: with_expansion for name in expansion})
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
    loaded = sorted(set(line.split('Loading mod ')[1].split(' ')[0]
                        for line in (workspace / 'create.log').read_text().splitlines() if 'Loading mod ' in line))
    if not driven or not report_path.exists():
        for log in ('create.log', 'drive.log'):
            if (workspace / log).exists():
                print(f'--- {log}\n' + (workspace / log).read_text()[-6000:])
        print(f'{label}: FAILED. Evidence kept at {workspace}')
        return False
    report = json.loads(report_path.read_text())
    report['loaded_mods'] = loaded
    wrong = {key: report.get(key) for key, value in EXPECTED.items() if report.get(key) != value}
    if wrong or report.get('driven_tiles', 0) <= 1 or ('space-age' in loaded) != with_expansion:
        print(f'{label}: FAILED with {wrong or report}. Evidence kept at {workspace}')
        return False
    (workspace / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'{label}: {package.name} passed: {report["placed"]} depots placed, {report["rotations"]} rotations, '
          f'{report["pipe_connections"]} pipe connections, {report["free_recipes"]} free recipes, '
          f'freighter drove {report["driven_tiles"]:.1f} tiles. Mods loaded: {", ".join(loaded)}')
    return True


if __name__ == '__main__':
    main()
