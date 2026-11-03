#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Check the Blender sources against the records of what was rendered and inspected from them.

Blender isn't needed. The render, packaging and inspection tools record the SHA-256
of the .blend they used, so a model that changed without re-rendering, re-packaging
or re-inspecting no longer matches its records. Also checks that every .blend was
saved uncompressed by Blender 4.3, and that the frozen 1x1 archive is unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parents[1]
# 64-bit little-endian file saved by Blender 4.3, without compression.
BLEND_HEADER = b'BLENDER-v403'
RENDER_AGAIN = 'render and package it again (assets/depots/README.md, "Re-rendering the sprites")'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


AREAS = {'freighter': 'assets/quinityn-freighter', 'depots': 'assets/depots'}


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
    connector = depots / 'source/pipe-connector.blend'
    model, digest = connector.relative_to(root), sha256(connector)
    record = load(depots / 'connectors/validation.json')
    fix = 'render and package the connector again (assets/depots/README.md)'
    expect(errors, record, 'source_sha256', digest, model, fix)
    expect(errors, record, 'renderer_sha256', sha256(depots / 'tools/render_connector.py'),
           'assets/depots/tools/render_connector.py', fix)
    expect(errors, load(depots / 'junction-validation.json'), 'connector_source_sha256', digest, model,
           'run assets/depots/tools/inspect_junctions.py in Blender')


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


def check(root, areas=tuple(AREAS)):
    errors = []
    for area in areas:
        try:
            check_headers(root, AREAS[area], errors)
            if area == 'freighter':
                check_freighter(root, errors)
            else:
                check_depots(root, errors)
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
