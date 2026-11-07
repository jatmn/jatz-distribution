#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Measure how much game update time Jat'z Distribution's deliveries cost (UPS).

Builds the benchmark map from tests/factorio/ups-benchmark_0.1.0 (a road maze with 1- and
5-tile roads, dead ends, U and S bends, depots 1 to 500 tiles apart and 5 to 100
freighters per request depot, on one to three surfaces), runs it headless with
Factorio's --benchmark, skips the warm-up and reports the time per tick.

Before and after a change, on your own machine (what a pull request needs):

    python3 tools/benchmark_ups.py --factorio /path/to/factorio --compare origin/main

That packages the mod at the given Git revision and at the working tree, and runs them
alternately (--runs each), so both meet the same machine state. Paste the Markdown table it
prints into the pull request. --transport-drones PATH benchmarks Transport Drones on the same
map instead (the baseline in docs/benchmark.md). Workspaces live under .local/ups-benchmark/.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import zipfile

from package_mod import build

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / 'tests/factorio/ups-benchmark_0.1.0'
PRESETS = ('quick', 'standard', 'stress')
# The seed of nauvis, the one surface the benchmark mod doesn't build itself. Without one, every
# save gets a random nauvis, some with biters near the spawn and some without, and freighters
# look for enemy units to run over only while there are some: the script cost moved by about
# 0.45 ms a tick between saves of the same code. This one has biters (35 enemy units in the
# measured window), as a real game does, so that cost is always in the numbers.
NAUVIS_SEED = 1340776561
# Timings kept from each tick (Factorio's debug view names); wholeUpdate is the whole game update.
# --benchmark-verbose is given "all": in 2.1.24 a list of names crashes the game after the run.
COLUMNS = ('wholeUpdate', 'scriptUpdate', 'pathFinder', 'commander', 'entityUpdate')


def preset_ticks(preset):
    """The preset's warm-up and measured ticks, read from presets.lua."""
    text = (BENCH / 'presets.lua').read_text()
    for line in text.splitlines():
        if line.strip().startswith(f'{preset} = preset('):
            values = dict(part.split(' = ') for part in line.split('{', 1)[1].split('}')[0].split(', '))
            return int(values['warmup']), int(values['ticks'])
    raise SystemExit(f'preset {preset} not found in presets.lua')


def run(command, log, timeout):
    with log.open('w') as handle:
        return subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT, timeout=timeout).returncode


def bundled_mods(data):
    return sorted(path.parent.name for path in data.glob('*/info.json') if path.parent.name != 'core')


def mod_name(path):
    """The mod name in a mod folder or zip."""
    if path.is_dir():
        return json.loads((path / 'info.json').read_text())['name']
    with zipfile.ZipFile(path) as archive:
        info = next(name for name in archive.namelist() if name.count('/') == 1 and name.endswith('/info.json'))
        return json.loads(archive.read(info))['name']


def prepare(label, mod, binary, data, preset, parent):
    """A workspace with `mod` (a zip or folder), the benchmark mod and a save of the built map."""
    workspace = Path(tempfile.mkdtemp(prefix=re.sub(r'[^A-Za-z0-9_.]+', '-', label).strip('-') + '-', dir=parent))
    mods = workspace / 'mods'
    mods.mkdir()
    if mod.is_dir():
        info = json.loads((mod / 'info.json').read_text())
        shutil.copytree(mod, mods / f'{info["name"]}_{info["version"]}')
    else:
        shutil.copy2(mod, mods / mod.name)
    bench = mods / BENCH.name
    shutil.copytree(BENCH, bench)
    (bench / 'selected-preset.lua').write_text(f'return {json.dumps(preset)}\n')
    enabled = {name: name == 'base' for name in bundled_mods(data)}
    enabled.update({mod_name(mod): True, 'ups-benchmark': True})
    (mods / 'mod-list.json').write_text(json.dumps({'mods': [
        {'name': name, 'enabled': state} for name, state in enabled.items()]}))
    write = workspace / 'write'
    write.mkdir()
    config = workspace / 'config.ini'
    config.write_text(f'[path]\nread-data={data.as_posix()}\nwrite-data={write.as_posix()}\n')
    command = [str(binary), '--config', str(config), '--mod-directory', str(mods)]
    save = workspace / 'ups-benchmark.zip'
    create = ['--create', str(save), '--map-gen-seed', str(NAUVIS_SEED)]
    if run(command + create, workspace / 'create.log', 1800) != 0 or not save.exists():
        print((workspace / 'create.log').read_text()[-4000:])
        raise SystemExit(f'{label}: creating the benchmark map failed, see {workspace}')
    return {'label': label, 'workspace': workspace, 'command': command, 'save': save, 'runs': []}


def parse_ticks(text):
    """Per-tick timings (ms) for each run in --benchmark-verbose output."""
    runs, header = [], None
    for line in text.splitlines():
        if line.startswith('run '):
            runs.append([])
        elif line.startswith('tick,'):
            header = line.rstrip(',').split(',')
        elif header and line.startswith('t') and line[1:2].isdigit():
            values = line.rstrip(',').split(',')
            row = {name: int(value) / 1e6 for name, value in zip(header[1:], values[1:]) if name in COLUMNS}
            row['tick'] = int(values[0][1:])
            runs[-1].append(row)
    return runs


def measure(variant, warmup, ticks, timeout):
    """One --benchmark run of the variant's save; appends its summary to variant['runs']."""
    log = variant['workspace'] / f'benchmark-{len(variant["runs"]) + 1}.log'
    command = variant['command'] + ['--benchmark', str(variant['save']), '--benchmark-ticks', str(warmup + ticks),
                                    '--benchmark-runs', '1', '--benchmark-verbose', 'all']
    if run(command, log, timeout) != 0:
        print(log.read_text()[-4000:])
        raise SystemExit(f'{variant["label"]}: benchmark failed, see {log}')
    rows = [row for row in parse_ticks(log.read_text())[-1] if row['tick'] >= warmup]
    if len(rows) < ticks * 0.9:
        raise SystemExit(f'{variant["label"]}: only {len(rows)} measured ticks in {log}')
    report = json.loads((variant['workspace'] / 'write/script-output/ups-benchmark.json').read_text())
    whole = sorted(row['wholeUpdate'] for row in rows)
    samples = [sample for sample in report['samples'] if sample['tick'] >= warmup]
    summary = {name: statistics.fmean(row[name] for row in rows) for name in COLUMNS}
    summary.update({
        'p99': whole[min(len(whole) - 1, int(len(whole) * 0.99))],
        'max': whole[-1],
        'vehicles': statistics.fmean(sample['vehicles'] for sample in samples) if samples else 0,
        'delivered': samples[-1]['delivered'] - samples[0]['delivered'] if len(samples) > 1 else 0,
        'delivered_minutes': (samples[-1]['tick'] - samples[0]['tick']) / 3600 if len(samples) > 1 else 0,
    })
    variant['map'] = report['summary']
    variant['runs'].append(summary)
    return summary


def combine(variant):
    """Median of each value over the variant's runs."""
    runs = variant['runs']
    result = {name: statistics.median(run[name] for run in runs) for name in runs[0]}
    result['spread'] = (max(run['wholeUpdate'] for run in runs) - min(run['wholeUpdate'] for run in runs))
    return result


def table(variants, preset, warmup, ticks):
    """A Markdown table of the variants' medians, with the change against the first."""
    first = combine(variants[0])
    lines = [f'Preset `{preset}`: {describe(variants[0]["map"])}; {warmup} warm-up ticks, {ticks} measured, '
             f'{len(variants[0]["runs"])} run(s) each. Times are ms per tick (median of runs).', '',
             '| | Mean update | UPS | Script | Pathfinder | p99 | Max | Run spread | Vehicles out | Delivered/min |',
             '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |']
    for variant in variants:
        result = combine(variant)
        change = ''
        if variant is not variants[0]:
            change = f' ({(result["wholeUpdate"] / first["wholeUpdate"] - 1) * 100:+.1f}%)'
        rate = result['delivered'] / result['delivered_minutes'] if result['delivered_minutes'] else 0
        lines.append(f'| {variant["label"]} | {result["wholeUpdate"]:.3f}{change} | {1000 / result["wholeUpdate"]:.0f} | '
                     f'{result["scriptUpdate"]:.3f} | {result["pathFinder"]:.3f} | {result["p99"]:.3f} | '
                     f'{result["max"]:.3f} | {result["spread"]:.3f} | {result["vehicles"]:.0f} | {rate:.0f} |')
    return '\n'.join(lines)


def describe(summary):
    # Providers keeping a minimum: only where the mod took the condition (summary from older maps: none).
    minimums = summary.get('minimums_set', 0)
    kept = f' ({minimums} keeping a minimum)' if minimums else ''
    return (f'{summary["surfaces"]} surface(s), {summary["providers"]} providers{kept}, {summary["requests"]} request depots, '
            f'{summary.get("fuel", 0)} fuel depots, '
            f'{summary["freighters_placed"]} of {summary["freighters"]} freighters placed, {summary["road_tiles"]} road tiles, '
            f'{summary["target"]} {summary["target_version"]}')


def package_revision(revision, parent):
    """The mod zip built by the revision's own packager, from a temporary Git worktree."""
    tree = Path(tempfile.mkdtemp(prefix='revision-', dir=parent))
    subprocess.run(['git', '-C', str(ROOT), 'worktree', 'add', '--detach', '--quiet', str(tree), revision], check=True)
    try:
        output = parent / f'{tree.name}-dist'
        subprocess.run([sys.executable, str(tree / 'tools/package_mod.py'), '--output', str(output)], check=True,
                       stdout=subprocess.DEVNULL)
        return next(output.glob('*.zip'))
    finally:
        subprocess.run(['git', '-C', str(ROOT), 'worktree', 'remove', '--force', str(tree)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--factorio', required=True, type=Path)
    parser.add_argument('--data-dir', type=Path)
    parser.add_argument('--preset', choices=PRESETS, default='standard')
    parser.add_argument('--runs', type=int, default=3, help='benchmark runs per variant (default 3)')
    parser.add_argument('--compare', metavar='REVISION', help='also benchmark this Git revision, as "before"')
    parser.add_argument('--transport-drones', type=Path, metavar='PATH',
                        help='benchmark this Transport Drones folder or zip instead of Jat\'z Distribution')
    parser.add_argument('--output', type=Path, help='write the results as JSON here')
    parser.add_argument('--timeout', type=int, default=3600, help='seconds allowed per benchmark run')
    args = parser.parse_args()
    binary = args.factorio.expanduser().resolve()
    data = args.data_dir.resolve() if args.data_dir else binary.parents[2] / 'data'
    if not binary.is_file() or not (data / 'base/info.json').exists():
        parser.error('Factorio executable or data directory missing')
    if args.compare and args.transport_drones:
        parser.error('--compare and --transport-drones are separate benchmarks')
    warmup, ticks = preset_ticks(args.preset)
    parent = ROOT / '.local/ups-benchmark'
    parent.mkdir(parents=True, exist_ok=True)
    variants = []
    if args.transport_drones:
        variants.append(prepare('transport-drones', args.transport_drones.resolve(), binary, data, args.preset, parent))
    else:
        if args.compare:
            before = package_revision(args.compare, parent)
            variants.append(prepare(f'before ({args.compare})', before, binary, data, args.preset, parent))
        current, _ = build(Path(tempfile.mkdtemp(prefix='dist-', dir=parent)))
        variants.append(prepare('after (working tree)' if args.compare else 'jatz-distribution', current, binary, data,
                                args.preset, parent))
    for index in range(args.runs):
        for variant in variants:
            result = measure(variant, warmup, ticks, args.timeout)
            print(f'{variant["label"]} run {index + 1}: {result["wholeUpdate"]:.3f} ms/tick, script '
                  f'{result["scriptUpdate"]:.3f}, {result["vehicles"]:.0f} vehicles out', flush=True)
    markdown = table(variants, args.preset, warmup, ticks)
    print('\n' + markdown)
    if args.output:
        args.output.write_text(json.dumps({
            'preset': args.preset, 'warmup': warmup, 'ticks': ticks,
            'variants': [{'label': variant['label'], 'map': variant['map'], 'runs': variant['runs'],
                          'median': combine(variant)} for variant in variants],
            'markdown': markdown}, indent=2) + '\n')


if __name__ == '__main__':
    main()
