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
import hashlib
import os
from pathlib import Path
import tempfile
import zipfile

from release_metadata import package_metadata

REPO = Path(__file__).resolve().parents[1]
# Every sprite layer the helpers draw; the preview atlases are for people, not the game.
LAYERS = ('base', 'mask-cab', 'mask-trim', 'mask-cargo', 'shadow')
# The road tile's variants, transitions and item icon (prototypes/roads.lua).
ROAD_ART = tuple(f'{name}.png' for name in ('slag1', 'slag2', 'slag4', 'concrete-inner-corner', 'concrete-outer-corner',
                                             'concrete-side', 'concrete-u', 'concrete-o', 'pslag_icon'))


def mod_files(root=REPO):
    # thumbnail.png is shown in the in-game mod browser and on the mod portal (tools/make_icons.py).
    files = [root / name for name in ('info.json', 'thumbnail.png', 'settings.lua', 'data.lua', 'data-final-fixes.lua',
                                      'control.lua', 'COPYING', 'COPYING.LESSER', 'NOTICE', 'changelog.txt')]
    files += sorted((root / 'prototypes').glob('*.lua'))
    files += sorted((root / 'scripts').glob('*.lua'))
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
    files += [depots / 'loading-zone/loading-zone.png']
    # The road art is Yuoki's (CC BY-NC-SA 4.0), so its licence ships beside it.
    roads = root / 'assets/roads/yuoki-railways'
    files += [roads / name for name in ROAD_ART + ('Licence.txt',)]
    missing = [str(path.relative_to(root)) for path in files if not path.is_file()]
    if missing:
        raise SystemExit('Missing mod files: ' + ', '.join(missing))
    return files


def build(output, root=REPO):
    info, notes = package_metadata(root)
    overrides = {'changelog.txt': notes.encode()}
    if info['version'] != json.loads((root / 'info.json').read_text())['version']:
        overrides['info.json'] = (json.dumps(info, indent=2) + '\n').encode()
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
                relative = path.relative_to(root).as_posix()
                entry = zipfile.ZipInfo(f'{folder}/{relative}', date_time=(1980, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o644 << 16
                archive.writestr(entry, overrides.get(relative, path.read_bytes()))
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
    (output / 'SHA256SUMS').write_text(f'{hashlib.sha256(target.read_bytes()).hexdigest()}  {target.name}\n')
    return target, len(files)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--output', type=Path, default=REPO / 'dist')
    args = parser.parse_args()
    target, count = build(args.output)
    print(f'{target.relative_to(REPO) if target.is_relative_to(REPO) else target}: {count} files, '
          f'{target.stat().st_size / 2**20:.1f} MiB')
