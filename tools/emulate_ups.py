#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""UPS benchmark for CI: compare the mod's script cost with a base revision, without Factorio.

Runs tests/lua/ups-emulator.lua (Lua 5.2) on the benchmark map, once with the mod's
control.lua, scripts/ and prototypes/ at --base and once with the working tree, and
reports the Lua instructions the mod's own code executes per tick: the mean, the 99th
percentile and the worst tick (the once-a-second dispatch spikes), plus its calls into
the runtime's functions. Instruction counts don't depend on the machine, and the fake
runtime's own work is never counted (tools/test_emulate_ups.py checks that), so a
difference is the change's own; they don't include the engine's pathfinding and
movement, which only tools/benchmark_ups.py measures in the game.

python3 tools/emulate_ups.py --base origin/main [--preset standard] [--summary FILE]

CI's "UPS benchmark" check runs this for pull requests that change the mod, adds the
table to its summary and posts it as a pull request comment (--comment writes the
comment's text; the workflow posts it, editing its earlier comment on later pushes). A rise of more than --warn percent in the mean or worst tick is flagged as a
warning; the job fails only if the emulator itself fails on the working tree.
"""
import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
EMULATOR = ROOT / 'tests/lua/ups-emulator.lua'
# What the mod's runtime is made of: the emulator loads these from each tree.
RUNTIME = ('control.lua', 'scripts', 'prototypes')
# Marks the workflow's comment so later pushes edit it instead of adding another.
COMMENT_MARKER = '<!-- ups-benchmark -->'
TIMEOUT = 1800  # seconds an emulation may take
METRICS = (('instructions_per_tick', 'Mean per tick'), ('instructions_p99', 'p99 tick'),
           ('instructions_max', 'Worst tick'), ('api_calls_per_tick', 'API calls per tick'),
           ('path_requests', 'Path requests'),
           ('commands', 'Unit commands'), ('vehicles_out', 'Freighters out'), ('delivered', 'Items delivered'))


def start(mod_root, preset, lua):
    """Starts the emulator on a mod tree; finish() waits for its report."""
    return subprocess.Popen([lua, str(EMULATOR), str(mod_root), preset], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)


def finish(process, deadline):
    with process:
        try:
            stdout, stderr = process.communicate(timeout=max(deadline - time.monotonic(), 0))
        except BaseException:
            process.kill()
            raise
    if process.returncode != 0:
        raise RuntimeError(stderr.strip() or stdout.strip())
    return json.loads(stdout.strip().splitlines()[-1])


def stop(process):
    """Kills an emulator that hasn't been waited for, and reaps it."""
    if process.returncode is None:
        with process:
            process.kill()


def emulate(mod_root, preset, lua):
    return finish(start(mod_root, preset, lua), time.monotonic() + TIMEOUT)


def extract(revision, target):
    """The mod's runtime files at a Git revision."""
    archive = subprocess.run(['git', '-C', str(ROOT), 'archive', '--format=tar', revision, '--', *RUNTIME],
                             capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(target, filter='data')


def table(preset, before, after, warn):
    lines = [f'Engine-free emulation, preset `{preset}`: Lua instructions the mod\'s own code runs per tick (lower is '
             'better), and its calls into the runtime\'s functions. Machine-independent; the game\'s pathfinding and '
             'movement are not included.', '',
             '| | Before | After | Change |', '| --- | --- | --- | --- |']
    flagged = []
    for key, label in METRICS:
        old, new = (before or {}).get(key), after[key]
        if old is None:
            lines.append(f'| {label} | n/a | {new:,.0f} | |')
            continue
        change = (new / old - 1) * 100 if old else 0.0
        lines.append(f'| {label} | {old:,.0f} | {new:,.0f} | {change:+.1f}% |')
        if key in ('instructions_per_tick', 'instructions_max') and change > warn:
            flagged.append(f'{label} {change:+.1f}%')
    return '\n'.join(lines), flagged


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--base', help='Git revision to compare with')
    parser.add_argument('--preset', default='standard', choices=('quick', 'standard', 'stress'))
    parser.add_argument('--summary', type=Path, help='append the Markdown table to this file')
    parser.add_argument('--comment', type=Path, help='write the pull request comment (Markdown) here')
    parser.add_argument('--warn', type=float, default=5.0, help='flag rises above this many percent')
    parser.add_argument('--lua', default='lua5.2')
    args = parser.parse_args()
    before, note = None, ''
    if args.base:
        # The two Lua processes use independent trees and run at once, on separate cores. If the
        # working tree's fails, the base's is stopped rather than waited for.
        with tempfile.TemporaryDirectory() as directory:
            deadline = time.monotonic() + TIMEOUT
            candidate, baseline, failure = start(ROOT, args.preset, args.lua), None, None
            try:
                try:
                    extract(args.base, directory)
                    baseline = start(directory, args.preset, args.lua)
                except subprocess.CalledProcessError as error:
                    failure = error
                after = finish(candidate, deadline)
                if baseline:
                    try:
                        before = finish(baseline, deadline)
                    except RuntimeError as error:
                        failure = error
            finally:
                for process in (candidate, baseline):
                    if process:
                        stop(process)
            if failure:
                note = f'\n\nThe base revision could not be emulated: {str(failure).splitlines()[-1]}'
    else:
        after = emulate(ROOT, args.preset, args.lua)
    markdown, flagged = table(args.preset, before, after, args.warn)
    markdown += note
    print(markdown)
    if args.summary:
        with args.summary.open('a') as handle:
            handle.write('## UPS benchmark\n\n' + markdown + '\n')
    if args.comment:
        if before is None:
            verdict = 'Could not compare with the base: only this pull request\'s numbers are shown.'
        elif flagged:
            verdict = ('**Script cost rose:** ' + ', '.join(flagged) + '. Check it in the game with '
                       '`tools/benchmark_ups.py --compare`.')
        else:
            verdict = f'No rise above {args.warn:g}% in the mean or worst tick.'
        repository = os.environ.get('GITHUB_REPOSITORY', 'jatmn/jatz-distribution')
        server = os.environ.get('GITHUB_SERVER_URL', 'https://github.com')
        args.comment.write_text(f'{COMMENT_MARKER}\n## UPS benchmark\n\n{verdict}\n\n{markdown}\n\n'
                                'This is CI\'s engine-free estimate. The in-game before and after table from '
                                '`tools/benchmark_ups.py --compare origin/main` (pull request template) is still '
                                f'required; see [docs/benchmark.md]({server}/{repository}/blob/main/docs/benchmark.md).\n')
    for item in flagged:
        print(f'::warning title=UPS benchmark::{item} against {args.base} in the engine-free emulation; '
              'run tools/benchmark_ups.py --compare in the game to confirm.')


if __name__ == '__main__':
    main()
