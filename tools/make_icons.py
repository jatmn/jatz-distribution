#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Make the in-game icons from the committed game sprites.

Each icon shows the entity as it looks in game: a depot facing south (the third
frame of its north/east/south/west preview sheet) and the freighter heading
south-east (frame 24 of its 64 directions: 135 degrees clockwise from north).

Factorio 2.1 expects 64 px icons and accepts custom mipmaps in the same file:
each level is half the size of the previous, aligned to the top, with no
padding (docs: types/IconData). Each icon is 120 x 64 px: 64 px at (0, 0),
32 at (64, 0), 16 at (96, 0) and 8 at (112, 0), each scaled straight from
the full-size frame for clarity at small sizes. Use it with icon_size = 64.

Each icons/icons.json records the source sheet, the frame used, and both SHA-256
hashes, so tools/check_blender_sources.py catches icons left behind by a re-render
or edited by hand. Run after re-rendering or re-packaging the sprites:

    .venv/bin/python tools/make_icons.py

With --check it writes nothing and fails unless every committed icon has exactly the
pixels made from its sprite sheet; CI runs that whenever an area's art changes.
"""
import argparse
import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import tempfile

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
ICON_SIZE = 64
MIPMAPS = 4
# Transparent border around the art, as a fraction of the icon size (4 px at 64 px). It keeps
# the art and the outline Factorio draws around icons (draw_background) inside the frame.
MARGIN = 1 / 16
ALPHA_THRESHOLD = 8  # ignore near-invisible pixels when finding the art's bounds
FRAME = 512  # game frame size in the preview sheets
FREIGHTER_DIRECTION = 24  # south-east: 64 directions, clockwise from north
DEPOT_DIRECTION = 2  # south: sheets are ordered north, east, south, west
ROLES = ('provider', 'request', 'buffer', 'fuel', 'liquid-provider', 'liquid-request', 'liquid-buffer')


def frame_box(direction, columns):
    """The (left, top, right, bottom) of a direction's frame in a sheet with that many columns."""
    x, y = (direction % columns) * FRAME, (direction // columns) * FRAME
    return (x, y, x + FRAME, y + FRAME)


def sources(root=REPO, areas=('freighter', 'depots')):
    """(icon folder, icon file name, preview sheet, frame box) for every icon the mod uses."""
    if 'freighter' in areas:
        freighter = root / 'assets/quinityn-freighter'
        yield (freighter / 'icons', 'quinityn-freighter.png', freighter / 'sheets/freighter-preview.png',
               frame_box(FREIGHTER_DIRECTION, 8))
    if 'depots' in areas:
        depots = root / 'assets/depots'
        for role in ROLES:
            yield (depots / 'icons', f'{role}-depot.png', depots / role / '3/sheets/preview.png',
                   frame_box(DEPOT_DIRECTION, 4))


def padded_art(sheet_bytes, box, label):
    """The frame's visible pixels, centered on a transparent square that includes the margin.

    Every mipmap level is scaled from this one square, so each level is an exact
    half-size copy of the previous one, margin included.
    """
    image = Image.open(BytesIO(sheet_bytes)).convert('RGBA').crop(box)
    mask = image.getchannel('A').point(lambda alpha: 255 if alpha >= ALPHA_THRESHOLD else 0)
    bounds = mask.getbbox()
    if bounds is None:
        raise SystemExit(f'{label}: frame {box} has no visible pixels; refusing to make a blank icon')
    art = image.crop(bounds)
    side = round(max(art.size) / (1 - 2 * MARGIN))
    square = Image.new('RGBA', (side, side))
    square.paste(art, ((side - art.width) // 2, (side - art.height) // 2))
    return square


def scaled(square, size):
    """square scaled to size px, resampled with premultiplied alpha (no dark fringes)."""
    return square.convert('RGBa').resize((size, size), Image.Resampling.LANCZOS).convert('RGBA')


def icon(sheet_bytes, box, label):
    """A 64 px icon with its three custom mipmaps, laid out as Factorio expects."""
    square = padded_art(sheet_bytes, box, label)
    sizes = [ICON_SIZE >> level for level in range(MIPMAPS)]
    sheet = Image.new('RGBA', (sum(sizes), ICON_SIZE))
    x = 0
    for size in sizes:
        sheet.paste(scaled(square, size), (x, 0))
        x += size
    return sheet


def replace_atomically(target, data):
    """Write data to target via a temporary file in the same folder, so target is never partial."""
    handle, temporary = tempfile.mkstemp(prefix=f'.{target.name}-', suffix='.tmp', dir=target.parent)
    try:
        with os.fdopen(handle, 'wb') as stream:
            stream.write(data)
        umask = os.umask(0)
        os.umask(umask)
        os.chmod(temporary, 0o666 & ~umask)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def check(root, areas):
    """Fail unless every committed icon has exactly the pixels made from its sprite sheet."""
    stale = []
    for folder, name, sheet, box in sources(root, areas):
        expected = np.asarray(icon(sheet.read_bytes(), box, sheet.relative_to(root)))
        actual = np.asarray(Image.open(folder / name).convert('RGBA'))
        if actual.shape != expected.shape or not np.array_equal(actual, expected):
            stale.append(str((folder / name).relative_to(root)))
    if stale:
        raise SystemExit('Not made from the current sprite sheets: ' + ', '.join(stale)
                         + '; run tools/make_icons.py and commit the result (never edit icons by hand)')
    print('Every icon matches its sprite sheet')


def main(root=REPO, areas=('freighter', 'depots')):
    records = {}
    for folder, name, sheet, box in sources(root, areas):
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / name
        # Hash and decode the same bytes, so the record names exactly what the icon was made from.
        sheet_bytes = sheet.read_bytes()
        encoded = BytesIO()
        icon(sheet_bytes, box, sheet.relative_to(root)).save(encoded, format='PNG', optimize=True)
        replace_atomically(target, encoded.getvalue())
        records.setdefault(folder, {})[name] = {
            'source': sheet.relative_to(root).as_posix(),
            'source_frame': list(box),
            'source_sha256': hashlib.sha256(sheet_bytes).hexdigest(),
            'sha256': hashlib.sha256(encoded.getvalue()).hexdigest(),
            'icon_size': ICON_SIZE,
            'mipmaps': MIPMAPS,
        }
        print(f'{target.relative_to(root)} from {sheet.relative_to(root)} frame {box}')
    for folder, record in records.items():
        replace_atomically(folder / 'icons.json', (json.dumps(record, indent=2) + '\n').encode())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true', help='compare with the committed icons; write nothing')
    parser.add_argument('--root', type=Path, default=REPO, help='repository checkout holding the art')
    parser.add_argument('--area', choices=('freighter', 'depots'), help='only this area (default: both)')
    args = parser.parse_args()
    areas = (args.area,) if args.area else ('freighter', 'depots')
    if args.check:
        check(args.root.resolve(), areas)
    else:
        main(args.root.resolve(), areas)
