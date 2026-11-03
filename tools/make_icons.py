#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Make the in-game icons from the committed presentation renders.

Factorio 2.1 expects 64 px icons and accepts custom mipmaps in the same file:
each level is half the size of the previous, aligned to the top, with no
padding (docs: types/IconData). Each icon is 120 x 64 px: 64 px at (0, 0),
32 at (64, 0), 16 at (96, 0) and 8 at (112, 0), each scaled straight from
the render for clarity at small sizes. Use it with icon_size = 64.

Each icons/icons.json records the source render's SHA-256 and the icon's, so
tools/check_blender_sources.py catches icons left behind by a re-render or
edited by hand. Run after re-rendering a presentation render:

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
ROLES = ('provider', 'request', 'buffer', 'fuel', 'liquid-provider', 'liquid-request', 'liquid-buffer')


def sources(root=REPO):
    """(icon folder, icon file name, source render) for every icon the mod uses."""
    freighter = root / 'assets/quinityn-freighter'
    yield freighter / 'icons', 'quinityn-freighter.png', freighter / 'masters/hero-default-palette.png'
    depots = root / 'assets/depots'
    for role in ROLES:
        yield depots / 'icons', f'{role}-depot.png', depots / role / '3/masters/hero-default-palette.png'


def padded_art(render):
    """The render's visible pixels, centered on a transparent square that includes the margin.

    Every mipmap level is scaled from this one square, so each level is an exact
    half-size copy of the previous one, margin included.
    """
    image = Image.open(render).convert('RGBA')
    mask = image.getchannel('A').point(lambda alpha: 255 if alpha >= ALPHA_THRESHOLD else 0)
    art = image.crop(mask.getbbox())
    side = round(max(art.size) / (1 - 2 * MARGIN))
    square = Image.new('RGBA', (side, side))
    square.paste(art, ((side - art.width) // 2, (side - art.height) // 2))
    return square


def scaled(square, size):
    """square scaled to size px, resampled with premultiplied alpha (no dark fringes)."""
    return square.convert('RGBa').resize((size, size), Image.Resampling.LANCZOS).convert('RGBA')


def icon(render):
    """A 64 px icon with its three custom mipmaps, laid out as Factorio expects."""
    square = padded_art(render)
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
    for folder, name, render in sources(root):
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / name
        icon(render).save(target, optimize=True)
        records.setdefault(folder, {})[name] = {
            'source': render.relative_to(root).as_posix(),
            'source_sha256': sha256(render),
            'sha256': sha256(target),
            'icon_size': ICON_SIZE,
            'mipmaps': MIPMAPS,
        }
        print(f'{target.relative_to(root)} from {render.relative_to(root)}')
    for folder, record in records.items():
        (folder / 'icons.json').write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
