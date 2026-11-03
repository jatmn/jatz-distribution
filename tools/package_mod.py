#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Build the installable mod zip, dist/jatz-distribution_<version>.zip.

The mod's root is the repository root, so the zip holds the mod source, the
Lua sprite helpers and only the game sprite sheets the helpers load, plus the
license files. Blender sources, tools, tests, docs and previews stay out
(see the licensing rules in AGENTS.md). Copy the zip into Factorio's mods folder.
"""
import argparse
import json
import os
from pathlib import Path
import tempfile
import zipfile

REPO = Path(__file__).resolve().parents[1]
# Every sprite layer the helpers draw; the preview atlases are for people, not the game.
LAYERS = ('base', 'mask-cab', 'mask-trim', 'mask-cargo', 'shadow')


def mod_files(root=REPO):
    files = [root / name for name in ('info.json', 'data.lua', 'COPYING', 'COPYING.LESSER', 'NOTICE')]
    files += sorted((root / 'prototypes').glob('*.lua'))
    files += sorted((root / 'locale').rglob('*.cfg'))
    freighter = root / 'assets/quinityn-freighter'
    files += [freighter / 'factorio/freighter-animation.lua', freighter / 'icons/quinityn-freighter.png']
    files += [freighter / f'sheets/freighter-{layer}.png' for layer in LAYERS]
    depots = root / 'assets/depots'
    files += sorted((depots / 'factorio').glob('*.lua'))
    for metadata in sorted(depots.glob('*/3/asset.json')):
        files += [metadata.parent / f'sheets/{layer}.png' for layer in LAYERS]
        # One icon per depot, named from the depot itself, so a missing icon stops the build.
        files += [depots / f'icons/{json.loads(metadata.read_text())["role"]}-depot.png']
    files += [depots / f'connectors/sheets/{layer}.png' for layer in ('base', 'shadow')]
    missing = [str(path.relative_to(root)) for path in files if not path.is_file()]
    if missing:
        raise SystemExit('Missing mod files: ' + ', '.join(missing))
    return files


def build(output, root=REPO):
    info = json.loads((root / 'info.json').read_text(encoding='utf-8'))
    folder = f'{info["name"]}_{info["version"]}'
    output.mkdir(parents=True, exist_ok=True)
    target = output / f'{folder}.zip'
    files = mod_files(root)
    # Write and verify a private temporary file, then atomically replace the zip, so an
    # interrupted or overlapping build never leaves a partial zip under the real name.
    handle, temporary = tempfile.mkstemp(prefix=f'.{folder}-', suffix='.zip.tmp', dir=output)
    os.close(handle)
    try:
        # Factorio expects one top-level folder inside the zip.
        with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                archive.write(path, f'{folder}/{path.relative_to(root).as_posix()}')
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None or len(archive.namelist()) != len(files):
                raise SystemExit(f'Archive verification failed: {target}')
        # mkstemp files are private; give the zip normal permissions from the umask.
        umask = os.umask(0)
        os.umask(umask)
        os.chmod(temporary, 0o666 & ~umask)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return target, len(files)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--output', type=Path, default=REPO / 'dist')
    args = parser.parse_args()
    target, count = build(args.output)
    print(f'{target.relative_to(REPO) if target.is_relative_to(REPO) else target}: {count} files, '
          f'{target.stat().st_size / 2**20:.1f} MiB')
