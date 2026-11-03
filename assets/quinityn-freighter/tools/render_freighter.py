# SPDX-License-Identifier: LGPL-3.0-only
"""Render the freighter's 64 directions and hero, recording which model they came from.

Writes masters/render-inputs.json (the model's SHA-256 and the render settings)
before rendering. package_sprites.py refuses renders without a matching record and
copies the model's hash into validation.json, which tools/check_blender_sources.py
compares with the committed model. The renderer skips existing outputs, so this
driver refuses to resume over renders from another, or an unknown, model.

python3 assets/quinityn-freighter/tools/render_freighter.py [--blender PATH]
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'source/quinityn-freighter.blend'
RENDERER = ROOT / 'tools/render_directions.py'
RECORD = ROOT / 'masters/render-inputs.json'
OUTPUTS = ('masters/exr', 'masters/shadow-silhouettes')


def stamp(resolution, samples):
    return {'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
            'renderer_sha256': hashlib.sha256(RENDERER.read_bytes()).hexdigest(),
            'resolution': resolution, 'samples': samples}


def blender_executable(name):
    """The absolute path of the Blender executable to run, or a clear error."""
    found = shutil.which(name)
    if not found:
        raise SystemExit(f'Blender executable not found: {name!r}. Install Blender 4.3.2 or pass '
                         '--blender /path/to/blender.')
    return str(Path(found).resolve())


def render(blender, options):
    """Run the shared renderer on the freighter model in background Blender."""
    command = [blender, '-b', str(SOURCE), '--python-exit-code', '1', '--python', str(RENDERER), '--', *options]
    # An argument list with shell=False: no shell parses these values, so there is nothing to
    # inject into and shlex quoting would corrupt them. The executable is resolved above from
    # the operator's own --blender choice; the paths come from this repository.
    subprocess.run(command, check=True)  # nosemgrep: python.lang.security.audit.dangerous-subprocess-use-audit, python.lang.security.audit.dangerous-subprocess-use-tainted-env-args


def positive(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError('must be at least 1')
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--blender', default='blender', help='Blender 4.3.2 executable (default: blender on PATH)')
    parser.add_argument('--threads', type=positive, default=8)
    args = parser.parse_args()
    # Check every input before writing anything.
    blender = blender_executable(args.blender)
    expected = stamp(1024, 48)
    existing = [path for name in OUTPUTS if (ROOT / name).is_dir() for path in (ROOT / name).iterdir()]
    if RECORD.exists():
        if json.loads(RECORD.read_text()) != expected:
            raise SystemExit(f'{RECORD} is from another model, renderer or setting. Delete '
                             f'{", ".join(OUTPUTS)} and {RECORD.name} under {ROOT}, then render again.')
    elif existing:
        raise SystemExit(f'Renders of unknown origin exist under {ROOT / "masters"}. Delete '
                         f'{", ".join(OUTPUTS)} there, then render again.')
    for name in OUTPUTS:
        (ROOT / name).mkdir(parents=True, exist_ok=True)
    RECORD.write_text(json.dumps(expected, indent=2) + '\n')
    threads = str(args.threads)
    render(blender, ['--start', '0', '--end', '64', '--resolution', '1024', '--samples', '48', '--threads', threads])
    render(blender, ['--hero', '--resolution', '2048', '--samples', '96', '--threads', threads])
    print('RENDERED freighter from', expected['source_sha256'])


if __name__ == '__main__':
    main()
