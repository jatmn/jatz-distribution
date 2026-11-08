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

The mod's thumbnail.png, shown in the in-game mod browser and on the mod portal,
is the freighter icon's frame at the 144 x 144 px Factorio 2.1 asks for
(auxiliary/mod-structure), with the same margin and no mipmaps.

Technology icons (technology/, for prototypes/technologies.lua) are made the same way at
256 px, the size Factorio's technology screen draws, with no mipmaps: the 512 px game frames
keep them sharp where a scaled-up 64 px icon is blurred. Use them with icon_size = 256.

Each icons/icons.json and technology/icons.json records the source sheet, the frame used, and both SHA-256
hashes, so tools/check_blender_sources.py catches icons left behind by a re-render
or edited by hand. Run after re-rendering or re-packaging the sprites:

    .venv/bin/python tools/make_icons.py

With --check it writes nothing and fails unless every committed icon and the thumbnail have exactly the
pixels made from its sprite sheet; CI runs that whenever an area's art changes.
"""
import argparse
from functools import partial
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
TECHNOLOGY_SIZE = 256
FREIGHTER_DIRECTION = 24  # south-east: 64 directions, clockwise from north
DEPOT_DIRECTION = 2  # south: sheets are ordered north, east, south, west
THUMBNAIL_SIZE = 144  # Factorio's mod thumbnail size
ROLES = ('provider', 'request', 'buffer', 'fuel', 'liquid-provider', 'liquid-request', 'liquid-buffer')
# The 1x1 road network monitor, built in the depots' finish, as players place it: facing north,
# its gauge window toward them.
MONITOR, MONITOR_DIRECTION = 'road-monitor', 0
# The 1x1 road tunnel portal, built the same way, facing south: its mouth toward the player.
TUNNEL, TUNNEL_DIRECTION = 'road-tunnel', 2


def frame_box(direction, columns):
    """The (left, top, right, bottom) of a direction's frame in a sheet with that many columns."""
    x, y = (direction % columns) * FRAME, (direction // columns) * FRAME
    return (x, y, x + FRAME, y + FRAME)


def sources(root=REPO, areas=('freighter', 'depots')):
    """(icon folder, icon file name, preview sheet, frame box, size, mipmap levels) for every icon
    the mod uses: the in-game icons, then the technology icons."""
    if 'freighter' in areas:
        freighter = root / 'assets/quinityn-freighter'
        sheet, box = freighter / 'sheets/freighter-preview.png', frame_box(FREIGHTER_DIRECTION, 8)
        yield (freighter / 'icons', 'quinityn-freighter.png', sheet, box, ICON_SIZE, MIPMAPS)
        yield (freighter / 'technology', 'quinityn-freighter.png', sheet, box, TECHNOLOGY_SIZE, 1)
    if 'depots' in areas:
        depots = root / 'assets/depots'
        for role in ROLES:
            yield (depots / 'icons', f'{role}-depot.png', depots / role / '3/sheets/preview.png',
                   frame_box(DEPOT_DIRECTION, 4), ICON_SIZE, MIPMAPS)
        yield (depots / 'icons', f'{MONITOR}.png', depots / MONITOR / '1/sheets/preview.png',
               frame_box(MONITOR_DIRECTION, 4), ICON_SIZE, MIPMAPS)
        yield (depots / 'icons', f'{TUNNEL}.png', depots / TUNNEL / '1/sheets/preview.png',
               frame_box(TUNNEL_DIRECTION, 4), ICON_SIZE, MIPMAPS)
        # Liquid freight research (the liquid depots) and fluid capacity research.
        yield (depots / 'technology', 'liquid-provider-depot.png', depots / 'liquid-provider/3/sheets/preview.png',
               frame_box(DEPOT_DIRECTION, 4), TECHNOLOGY_SIZE, 1)
        # Road network monitor research.
        yield (depots / 'technology', f'{MONITOR}.png', depots / MONITOR / '1/sheets/preview.png',
               frame_box(MONITOR_DIRECTION, 4), TECHNOLOGY_SIZE, 1)
        # Road tunnels research.
        yield (depots / 'technology', f'{TUNNEL}.png', depots / TUNNEL / '1/sheets/preview.png',
               frame_box(TUNNEL_DIRECTION, 4), TECHNOLOGY_SIZE, 1)


def thumbnail_source(root=REPO):
    """(thumbnail path, preview sheet, frame box): the freighter as its icon shows it."""
    _, _, sheet, box, _, _ = next(sources(root, ('freighter',)))
    return root / 'thumbnail.png', sheet, box


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


def icon(sheet_bytes, box, label, size=ICON_SIZE, mipmaps=MIPMAPS):
    """An icon of `size` px with its custom mipmaps (mipmaps - 1 of them), laid out as Factorio expects."""
    square = padded_art(sheet_bytes, box, label)
    sizes = [size >> level for level in range(mipmaps)]
    sheet = Image.new('RGBA', (sum(sizes), size))
    x = 0
    for level_size in sizes:
        sheet.paste(scaled(square, level_size), (x, 0))
        x += level_size
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


def thumbnail(sheet_bytes, box, label):
    """The mod thumbnail: the frame's art on a transparent 144 px square."""
    return scaled(padded_art(sheet_bytes, box, label), THUMBNAIL_SIZE)


def images(root, areas):
    """(target, make, sheet, box) for every icon (in-game and technology) of the areas, and the thumbnail with the freighter."""
    for folder, name, sheet, box, size, mipmaps in sources(root, areas):
        yield folder / name, partial(icon, size=size, mipmaps=mipmaps), sheet, box
    if 'freighter' in areas:
        target, sheet, box = thumbnail_source(root)
        yield target, thumbnail, sheet, box


def check(root, areas):
    """Fail unless every committed icon and the thumbnail have exactly the pixels made from their sprite sheet."""
    stale = []
    for target, make, sheet, box in images(root, areas):
        expected = np.asarray(make(sheet.read_bytes(), box, sheet.relative_to(root)))
        actual = np.asarray(Image.open(target).convert('RGBA')) if target.is_file() else None
        if actual is None or actual.shape != expected.shape or not np.array_equal(actual, expected):
            stale.append(str(target.relative_to(root)))
    if stale:
        raise SystemExit('Not made from the current sprite sheets: ' + ', '.join(stale)
                         + '; run tools/make_icons.py and commit the result (never edit icons by hand)')
    print('Every icon matches its sprite sheet')


def main(root=REPO, areas=('freighter', 'depots')):
    records = {}
    for folder, name, sheet, box, size, mipmaps in sources(root, areas):
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / name
        # Hash and decode the same bytes, so the record names exactly what the icon was made from.
        sheet_bytes = sheet.read_bytes()
        encoded = BytesIO()
        icon(sheet_bytes, box, sheet.relative_to(root), size, mipmaps).save(encoded, format='PNG', optimize=True)
        replace_atomically(target, encoded.getvalue())
        records.setdefault(folder, {})[name] = {
            'source': sheet.relative_to(root).as_posix(),
            'source_frame': list(box),
            'source_sha256': hashlib.sha256(sheet_bytes).hexdigest(),
            'sha256': hashlib.sha256(encoded.getvalue()).hexdigest(),
            'icon_size': size,
            'mipmaps': mipmaps,
        }
        print(f'{target.relative_to(root)} from {sheet.relative_to(root)} frame {box}')
    for folder, record in records.items():
        replace_atomically(folder / 'icons.json', (json.dumps(record, indent=2) + '\n').encode())
    if 'freighter' in areas:
        target, sheet, box = thumbnail_source(root)
        encoded = BytesIO()
        thumbnail(sheet.read_bytes(), box, sheet.relative_to(root)).save(encoded, format='PNG', optimize=True)
        replace_atomically(target, encoded.getvalue())
        print(f'{target.relative_to(root)} from {sheet.relative_to(root)} frame {box}')


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
