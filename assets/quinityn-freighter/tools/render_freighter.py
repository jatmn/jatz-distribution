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


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--blender', default='blender')
    parser.add_argument('--threads', type=int, default=8)
    args = parser.parse_args()
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
    base = [args.blender, '-b', str(SOURCE), '--python-exit-code', '1', '--python', str(RENDERER), '--']
    subprocess.run(base + ['--start', '0', '--end', '64', '--resolution', '1024', '--samples', '48',
                           '--threads', str(args.threads)], check=True)
    subprocess.run(base + ['--hero', '--resolution', '2048', '--samples', '96', '--threads', str(args.threads)],
                   check=True)
    print('RENDERED freighter from', expected['source_sha256'])


if __name__ == '__main__':
    main()
