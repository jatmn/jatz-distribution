# SPDX-License-Identifier: LGPL-3.0-only
"""Wreck each master into its remnants (build_remnants.py) and render them with the shared renderer.

Every assets/depots/remnants/<name>/asset.json (and the freighter's, in
assets/quinityn-freighter/remnants/, so each art area holds its own wrecks) names its master, the assembly to turn, the wreck profile and
seed, and its directions. The wreck goes to <name>/masters/wreck.blend, which isn't
committed: the committed master and build_remnants.py are its source. Run from anywhere:

  python3 assets/depots/tools/render_remnants.py            # add --name cargo for one

Like render_depots.py, it stops if the local renders came from other inputs: delete that
remnant's masters/ and frames/ and run it again.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
TOOLS = ROOT / 'tools'
BUILDER = TOOLS / 'build_remnants.py'
RENDERER = REPO / 'assets/quinityn-freighter/tools/render_directions.py'
# Each art area's wrecks, next to the master they are made from.
FOLDERS = (REPO / 'assets/depots/remnants', REPO / 'assets/quinityn-freighter/remnants')


def wrecks(name=None):
    """Every wreck's asset.json (or the one named), in a stable order."""
    found = sorted(path for folder in FOLDERS for path in folder.glob('*/asset.json'))
    return [path for path in found if name is None or path.parent.name == name]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs(metadata_path, resolution, samples):
    """What a render of these remnants depends on; package_remnants.py checks it.

    The whole asset.json counts: its root, directions, projection and size change the renders,
    its sheet_order the sheets.
    """
    meta = json.loads(metadata_path.read_text())
    return {'asset_sha256': sha256(metadata_path), 'master': meta['master'], 'master_sha256': sha256(REPO / meta['master']),
            'builder_sha256': sha256(BUILDER), 'renderer_sha256': sha256(RENDERER),
            'profile': meta['profile'], 'seed': meta['seed'], 'resolution': resolution, 'samples': samples}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--blender', default='blender')
    parser.add_argument('--samples', type=int, default=64)
    parser.add_argument('--workers', type=int, default=2)
    parser.add_argument('--threads', type=int, default=6)
    parser.add_argument('--name')
    args = parser.parse_args()
    variants = wrecks(args.name)
    assert variants, 'No remnants found'

    def render(metadata_path):
        folder = metadata_path.parent
        meta = json.loads(metadata_path.read_text())
        for name in ['masters/exr', 'masters/shadow-silhouettes', 'masters/layers', 'frames', 'sheets', 'previews']:
            (folder / name).mkdir(parents=True, exist_ok=True)
        stamp = inputs(metadata_path, meta['master_size'], args.samples)
        record = folder / 'masters/render-inputs.json'
        if record.exists() and json.loads(record.read_text()) != stamp:
            raise RuntimeError(f'Delete the earlier renders before rendering changed inputs: {folder}')
        record.write_text(json.dumps(stamp, indent=2) + '\n')
        wreck = folder / 'masters/wreck.blend'
        logs = REPO / '.local/remnant-render-logs'
        logs.mkdir(parents=True, exist_ok=True)
        with (logs / f'{meta["name"]}.log').open('w') as log:
            subprocess.run([args.blender, '-b', str(REPO / meta['master']), '--python-exit-code', '1',
                            '--python', str(BUILDER), '--', '--profile', meta['profile'],
                            '--seed', str(meta['seed']), '--output', str(wreck)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
            subprocess.run([args.blender, '-b', str(wreck), '--python-exit-code', '1', '--python', str(RENDERER), '--',
                            '--asset-root', str(folder), '--root-object', meta['root'],
                            '--direction-count', str(len(meta['directions'])),
                            '--projection-y-scale', str(meta['projection_y_scale']),
                            '--start', '0', '--end', str(len(meta['directions'])),
                            '--resolution', str(meta['master_size']), '--samples', str(args.samples),
                            '--threads', str(args.threads)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        for direction in range(len(meta['directions'])):
            assert (folder / f'masters/exr/direction-{direction:02}.exr').exists()
            assert (folder / f'masters/shadow-silhouettes/direction-{direction:02}.png').exists()
        print('RENDERED', meta['name'], flush=True)

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        list(executor.map(render, variants))


if __name__ == '__main__':
    main()
