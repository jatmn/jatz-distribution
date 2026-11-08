#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Check the Blender sources against the records of what was rendered and inspected from them.

Blender isn't needed. The render, packaging and inspection tools record the SHA-256
of the .blend they used, so a model that changed without re-rendering, re-packaging
or re-inspecting no longer matches its records. Also checks that every .blend was
saved uncompressed by Blender 4.3, that the in-game icons follow Factorio's icon layout
and were made from the current sprites, and that the frozen 1x1 archive is unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zlib

REPO = Path(__file__).resolve().parents[1]
# 64-bit little-endian file saved by Blender 4.3, without compression.
BLEND_HEADER = b'BLENDER-v403'
RENDER_AGAIN = 'render and package it again (assets/depots/README.md, "Re-rendering the sprites")'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


AREAS = {'freighter': 'assets/quinityn-freighter', 'depots': 'assets/depots'}
# The 1x1 road network monitor, built, rendered and packaged with the depots (no geometry or
# junction inspection: it has no loading path or pipes).
MONITOR = 'road-monitor/1/asset.json'


def tracked_blends(root, directory):
    try:
        listed = subprocess.check_output(['git', 'ls-files', '-z', '--', f'{directory}/*.blend'], cwd=root,
                                         stderr=subprocess.DEVNULL)
        return sorted(root / name for name in listed.decode().split('\0') if name)
    except (OSError, subprocess.CalledProcessError):
        return sorted((root / directory).rglob('*.blend'))


def check_headers(root, directory, errors):
    for path in tracked_blends(root, directory):
        with path.open('rb') as handle:
            header = handle.read(len(BLEND_HEADER))
        if header != BLEND_HEADER:
            errors.append(f'{path.relative_to(root)}: header {header!r} is not {BLEND_HEADER!r}; '
                          'save it with Blender 4.3.2 and "Compress" turned off')


def expect(errors, record, field, actual, model, fix):
    if record.get(field) != actual:
        errors.append(f'{model}: {field} in its record does not match the committed file; {fix}')


def by_role(path):
    return {entry['role']: entry for entry in load(path).get('results', []) if entry.get('size') == 3}


def check_depots(root, errors):
    depots = root / 'assets/depots'
    packaged, geometry = by_role(depots / 'validation.json'), by_role(depots / 'geometry-validation.json')
    junctions = by_role(depots / 'junction-validation.json')
    for meta_path in sorted(depots.glob('*/3/asset.json')):
        meta = load(meta_path)
        role, source = meta['role'], depots / meta['source']
        model = source.relative_to(root)
        if not source.is_file():
            errors.append(f'{meta_path.relative_to(root)}: source {meta["source"]} is missing')
            continue
        digest = sha256(source)
        expect(errors, load(meta_path.parent / 'validation.json'), 'source_sha256', digest, model,
               f'{role}/3/validation.json is from an older model; {RENDER_AGAIN}')
        expect(errors, packaged.get(role, {}), 'source_sha256', digest, model,
               f'validation.json is from an older model; {RENDER_AGAIN}')
        expect(errors, geometry.get(role, {}), 'source_sha256', digest, model,
               'run assets/depots/tools/inspect_depots.py in Blender')
        if meta['ports']:
            expect(errors, junctions.get(role, {}), 'source_sha256', digest, model,
                   'run assets/depots/tools/inspect_junctions.py in Blender')
    monitor = depots / MONITOR
    if monitor.is_file():
        meta = load(monitor)
        source = depots / meta['source']
        model, digest = source.relative_to(root), sha256(source)
        entry = next((entry for entry in load(depots / 'validation.json').get('results', [])
                      if entry.get('role') == meta['role'] and entry.get('size') == meta['size']), {})
        expect(errors, load(monitor.parent / 'validation.json'), 'source_sha256', digest, model,
               f'{meta["role"]}/{meta["size"]}/validation.json is from an older model; {RENDER_AGAIN}')
        expect(errors, entry, 'source_sha256', digest, model, f'validation.json is from an older model; {RENDER_AGAIN}')
    connector = depots / 'source/pipe-connector.blend'
    model, digest = connector.relative_to(root), sha256(connector)
    record = load(depots / 'connectors/validation.json')
    fix = 'render and package the connector again (assets/depots/README.md)'
    expect(errors, record, 'source_sha256', digest, model, fix)
    expect(errors, record, 'renderer_sha256', sha256(depots / 'tools/render_connector.py'),
           'assets/depots/tools/render_connector.py', fix)
    expect(errors, load(depots / 'junction-validation.json'), 'connector_source_sha256', digest, model,
           'run assets/depots/tools/inspect_junctions.py in Blender')


# What destroyed depots and freighters leave: wrecks of the masters made by build_remnants.py,
# rendered with the shared renderer. Each area keeps its own wrecks (assets/<area>/remnants/), and
# CI's art checkout of an area also fetches the other area's tools/, so both are here to hash.
REMNANT_BUILDER = 'assets/depots/tools/build_remnants.py'
RENDERER = 'assets/quinityn-freighter/tools/render_directions.py'
REMNANT_LAYERS = ('shadow', 'base', 'mask-cab', 'mask-trim', 'mask-cargo')


def check_remnants(root, area, errors):
    """Each of the area's wrecks was rendered from the committed master, asset.json, builder and renderer."""
    for meta_path in sorted((root / AREAS[area] / 'remnants').glob('*/asset.json')):
        meta, folder = load(meta_path), meta_path.parent
        shown = folder.relative_to(root)
        fix = (f'render and package it again (assets/depots/tools/render_remnants.py --name {folder.name}, '
               'then package_remnants.py)')
        record = load(folder / 'validation.json')
        master = root / meta['master']
        if not master.is_file():
            errors.append(f'{shown}: master {meta["master"]} is missing')
            continue
        for field, actual in (('asset_sha256', sha256(meta_path)), ('master', meta['master']),
                              ('master_sha256', sha256(master)),
                              ('builder_sha256', sha256(root / REMNANT_BUILDER)),
                              ('renderer_sha256', sha256(root / RENDERER))):
            if record.get(field) != actual:
                errors.append(f'{shown}: its sprites are from another {field} than the committed one; {fix}')
        for layer in REMNANT_LAYERS:
            if not (folder / f'sheets/{layer}.png').is_file():
                errors.append(f'{shown}/sheets/{layer}.png: missing; {fix}')


def check_freighter(root, errors):
    asset = root / 'assets/quinityn-freighter'
    source = asset / 'source/quinityn-freighter.blend'
    model, digest = source.relative_to(root), sha256(source)
    # Render provenance: package_sprites.py copies the model hash that render_freighter.py
    # recorded at render time. Refreshing the inspection or checksums can't update it.
    expect(errors, load(asset / 'validation.json'), 'source_sha256', digest, model,
           'its sprites are from an older model; render with assets/quinityn-freighter/tools/render_freighter.py '
           'and package again (assets/quinityn-freighter/README.md)')
    expect(errors, load(asset / 'geometry-validation.json'), 'model_sha256', digest, model,
           'run assets/quinityn-freighter/tools/inspect_geometry.py in Blender')
    expect(errors, load(asset / 'asset.json'), 'concept_sha256', sha256(asset / 'source/approved-concept.png'),
           'assets/quinityn-freighter/source/approved-concept.png', 'the approved concept must stay unchanged')
    # validate_assets.py records every model, sprite and preview; tool code is not checked here.
    for name, recorded in load(asset / 'checksums.json').items():
        path = asset / name
        if path.suffix in {'.blend', '.png', '.webp'}:
            if not path.is_file():
                errors.append(f'{path.relative_to(root)}: listed in checksums.json but missing')
            elif sha256(path) != recorded:
                errors.append(f'{path.relative_to(root)}: does not match checksums.json; re-render and run '
                              'assets/quinityn-freighter/tools/validate_assets.py (never hand-edit sprites)')


def check_archive(root, errors):
    archive = root / 'assets/depots/archive/1x1'
    manifest = load(archive / 'manifest.json')
    listed = {entry['path'] for entry in manifest['files']}
    for entry in manifest['files']:
        path = archive / entry['path']
        if not path.is_file():
            errors.append(f'{path.relative_to(root)}: missing from the frozen 1x1 archive')
        elif path.stat().st_size != entry['bytes'] or sha256(path) != entry['sha256']:
            errors.append(f'{path.relative_to(root)}: changed; the 1x1 archive is frozen (AGENTS.md)')
    allowed = {'README.md', 'manifest.json'}
    for path in sorted(archive.rglob('*')):
        relative = path.relative_to(archive).as_posix()
        if path.is_file() and relative not in listed and relative not in allowed and not relative.startswith('tools/'):
            errors.append(f'{path.relative_to(root)}: not in the frozen 1x1 archive manifest')


# The icon format the prototypes declare (icon_size = 64 in prototypes/constants.lua; the Mod
# tests keep the two equal): 64 px plus three custom mipmaps, each half the previous size,
# top-aligned with no padding, as Factorio 2.1 documents (types/IconData).
ICON_SIZE = 64
MIPMAPS = 4
SLOTS = [(sum(ICON_SIZE >> n for n in range(level)), ICON_SIZE >> level) for level in range(MIPMAPS)]
ICON_WIDTH = sum(size for _, size in SLOTS)
VISIBLE = 16  # alpha at or above this counts as visible art


def required_icons(root, area):
    """The icons the mod needs for an area, from the entities themselves rather than icons.json."""
    if area == 'freighter':
        return {'quinityn-freighter.png'}
    depots = root / 'assets/depots'
    icons = {f'{load(path)["role"]}-depot.png' for path in depots.glob('*/3/asset.json')}
    return icons | ({'road-monitor.png'} if (depots / MONITOR).is_file() else set())


def png_rgba(path):
    """(width, height, rows of RGBA bytes) for an 8-bit, non-interlaced RGBA PNG, or None otherwise."""
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    position, header, compressed = 8, None, b''
    while position + 8 <= len(data):
        length, kind = struct.unpack('>I4s', data[position:position + 8])
        body = data[position + 8:position + 8 + length]
        if kind == b'IHDR':
            header = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            compressed += body
        position += 12 + length
    if header is None or header[2:] != (8, 6, 0, 0, 0):
        return None
    width, height = header[:2]
    try:
        raw = zlib.decompress(compressed)
    except zlib.error:
        return None
    stride, rows, previous = width * 4, [], bytearray(width * 4)
    for y in range(height):
        start = y * (stride + 1)
        kind, row = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if len(row) != stride or kind > 4:
            return None
        for x in range(stride):  # undo the PNG scanline filter
            left = row[x - 4] if x >= 4 else 0
            up, corner = previous[x], previous[x - 4] if x >= 4 else 0
            if kind == 1:
                row[x] = (row[x] + left) & 255
            elif kind == 2:
                row[x] = (row[x] + up) & 255
            elif kind == 3:
                row[x] = (row[x] + (left + up) // 2) & 255
            elif kind == 4:
                estimate = left + up - corner
                distances = (abs(estimate - left), abs(estimate - up), abs(estimate - corner))
                row[x] = (row[x] + (left, up, corner)[distances.index(min(distances))]) & 255
        rows.append(bytes(row))
        previous = row
    return width, height, rows


def icon_layout_problems(path):
    """What, if anything, stops a PNG from being a valid 64 px icon with its three mipmaps."""
    decoded = png_rgba(path)
    if decoded is None:
        return ['must be an 8-bit RGBA PNG']
    width, height, rows = decoded
    if (width, height) != (ICON_WIDTH, ICON_SIZE):
        return [f'must be {ICON_WIDTH}x{ICON_SIZE} ({ICON_SIZE} px with {MIPMAPS - 1} mipmaps), found {width}x{height}']
    problems = []
    for x, size in SLOTS:
        if not any(rows[y][(x + column) * 4 + 3] >= VISIBLE for y in range(size) for column in range(size)):
            problems.append(f'the {size} px level is blank')
    outside = any(row[column * 4 + 3] for y, row in enumerate(rows) for column in range(width)
                  if not any(x <= column < x + size and y < size for x, size in SLOTS))
    if outside:
        problems.append('has pixels outside the mipmap slots')
    return problems


def check_icons(root, area, errors):
    """Every icon the mod needs exists, has Factorio's icon layout, and is current with its sprite sheet."""
    folder = root / AREAS[area] / 'icons'
    record_path = folder / 'icons.json'
    remake = 'run tools/make_icons.py (never edit icons by hand)'
    records = load(record_path)
    for name in sorted(required_icons(root, area) - set(records)):
        errors.append(f'{(folder / name).relative_to(root)}: required by the mod but not in {record_path.name}; {remake}')
    for name, record in sorted(records.items()):
        icon, source = folder / name, root / record['source']
        shown = icon.relative_to(root)
        if not icon.is_file():
            errors.append(f'{shown}: missing; {remake}')
            continue
        if (record.get('icon_size'), record.get('mipmaps')) != (ICON_SIZE, MIPMAPS):
            errors.append(f'{shown}: recorded as {record.get("icon_size")} px with {record.get("mipmaps")} levels; '
                          f'the mod uses {ICON_SIZE} px with {MIPMAPS} levels; {remake}')
        for problem in icon_layout_problems(icon):
            errors.append(f'{shown}: {problem}; {remake}')
        if not source.is_file() or sha256(source) != record['source_sha256']:
            errors.append(f'{shown}: made from an older {record["source"]}; {remake}')
        if sha256(icon) != record['sha256']:
            errors.append(f'{shown}: does not match {record_path.name}; {remake}')
    for icon in sorted(folder.glob('*.png')):
        if icon.name not in records:
            errors.append(f'{icon.relative_to(root)}: not in {record_path.name}; {remake}')


def check_loading_zone(root, errors):
    """The loading zone marking is a 64 px tile, not blank, and current with the script that draws it."""
    folder = root / 'assets/depots/loading-zone'
    remake = 'run assets/depots/tools/make_loading_zone.py (never edit it by hand)'
    record = load(folder / 'loading-zone.json')['loading-zone.png']
    image, generator = folder / 'loading-zone.png', root / record['generator']
    shown = image.relative_to(root)
    decoded = png_rgba(image) if image.is_file() else None
    if decoded is None:
        errors.append(f'{shown}: must be an 8-bit RGBA PNG; {remake}')
        return
    width, height, rows = decoded
    if (width, height) != (64, 64) or record.get('size') != 64:
        errors.append(f'{shown}: must be 64x64 (one tile at scale 0.5), found {width}x{height}; {remake}')
    if not any(row[column * 4 + 3] >= VISIBLE for row in rows for column in range(width)):
        errors.append(f'{shown}: is blank; {remake}')
    if not generator.is_file() or sha256(generator) != record['generator_sha256']:
        errors.append(f'{shown}: drawn by an older {record["generator"]}; {remake}')
    if sha256(image) != record['sha256']:
        errors.append(f'{shown}: does not match loading-zone.json; {remake}')


def check(root, areas=tuple(AREAS)):
    errors = []
    for area in areas:
        try:
            check_headers(root, AREAS[area], errors)
            check_icons(root, area, errors)
            check_remnants(root, area, errors)
            if area == 'freighter':
                check_freighter(root, errors)
            else:
                check_depots(root, errors)
                check_loading_zone(root, errors)
                check_archive(root, errors)
        except FileNotFoundError as missing:
            name = Path(missing.filename).resolve()
            shown = name.relative_to(root) if name.is_relative_to(root) else name
            errors.append(f'{shown}: missing; the {area} records, models and sprites must all be committed')
    return errors


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=REPO)
    parser.add_argument('--area', choices=AREAS, help='check one area (default: both)')
    args = parser.parse_args()
    errors = check(args.root.resolve(), (args.area,) if args.area else tuple(AREAS))
    for error in errors:
        print(f'::error::{error}')
    if errors:
        raise SystemExit(1)
    print('Blender sources, render and inspection records, and the 1x1 archive are consistent.')
