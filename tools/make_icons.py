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
"""
import hashlib
import json
from pathlib import Path

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


def sources(root=REPO):
    """(icon folder, icon file name, preview sheet, frame box) for every icon the mod uses."""
    freighter = root / 'assets/quinityn-freighter'
    yield (freighter / 'icons', 'quinityn-freighter.png', freighter / 'sheets/freighter-preview.png',
           frame_box(FREIGHTER_DIRECTION, 8))
    depots = root / 'assets/depots'
    for role in ROLES:
        yield (depots / 'icons', f'{role}-depot.png', depots / role / '3/sheets/preview.png',
               frame_box(DEPOT_DIRECTION, 4))


def padded_art(sheet, box):
    """The frame's visible pixels, centered on a transparent square that includes the margin.

    Every mipmap level is scaled from this one square, so each level is an exact
    half-size copy of the previous one, margin included.
    """
    image = Image.open(sheet).convert('RGBA').crop(box)
    mask = image.getchannel('A').point(lambda alpha: 255 if alpha >= ALPHA_THRESHOLD else 0)
    art = image.crop(mask.getbbox())
    side = round(max(art.size) / (1 - 2 * MARGIN))
    square = Image.new('RGBA', (side, side))
    square.paste(art, ((side - art.width) // 2, (side - art.height) // 2))
    return square


def scaled(square, size):
    """square scaled to size px, resampled with premultiplied alpha (no dark fringes)."""
    return square.convert('RGBa').resize((size, size), Image.Resampling.LANCZOS).convert('RGBA')


def icon(sheet, box):
    """A 64 px icon with its three custom mipmaps, laid out as Factorio expects."""
    square = padded_art(sheet, box)
    sizes = [ICON_SIZE >> level for level in range(MIPMAPS)]
    sheet = Image.new('RGBA', (sum(sizes), ICON_SIZE))
    x = 0
    for size in sizes:
        sheet.paste(scaled(square, size), (x, 0))
        x += size
    return sheet


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(root=REPO):
    records = {}
    for folder, name, sheet, box in sources(root):
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / name
        icon(sheet, box).save(target, optimize=True)
        records.setdefault(folder, {})[name] = {
            'source': sheet.relative_to(root).as_posix(),
            'source_frame': list(box),
            'source_sha256': sha256(sheet),
            'sha256': sha256(target),
            'icon_size': ICON_SIZE,
            'mipmaps': MIPMAPS,
        }
        print(f'{target.relative_to(root)} from {sheet.relative_to(root)} frame {box}')
    for folder, record in records.items():
        (folder / 'icons.json').write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
