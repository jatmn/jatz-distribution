#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Draw the 1x1 loading-zone ground marking shown on each depot's loading side.

A simplified "no parking - loading zone" sign painted on the ground: a red
border and a red circle with a slash over a black P, on off-white paint that is
grimy, oil-stained, scuffed by tyres, scratched and chipped down to the ground.
Every shape is drawn here, with no font or source image, and a fixed seed makes
the output identical on every run, so this script is the marking's source.

Writes loading-zone/loading-zone.png (64 x 64 RGBA: one tile at scale 0.5) and
loading-zone/loading-zone.json, which records this script's and the image's
SHA-256 for tools/check_blender_sources.py. Run with the repository's .venv:

    .venv/bin/python assets/depots/tools/make_loading_zone.py
"""
import hashlib
from io import BytesIO
import json
import math
import os
from pathlib import Path
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'loading-zone'
SIZE = 64  # pixels; one tile at sprite scale 0.5
DRAW = 512  # drawn at 8x, then reduced, for smooth edges
SEED = 1705

RED = np.array([150, 42, 34], float)
BLACK = np.array([28, 26, 24], float)
PAINT = np.array([196, 190, 172], float)  # off-white, never bright white
DIRT = np.array([70, 60, 45], float)
OIL = np.array([30, 28, 26], float)
SCRATCH = np.array([110, 104, 92], float)


def value_noise(cells, seed):
    grid = np.random.default_rng(seed).random((cells + 1, cells + 1))
    image = Image.fromarray((grid * 255).astype(np.uint8)).resize((DRAW, DRAW), Image.Resampling.BICUBIC)
    return np.asarray(image, float) / 255


def fbm(seed, octaves=((4, .5), (9, .25), (23, .15), (61, .1))):
    """Layered smooth noise in [0, 1]."""
    total = sum(value_noise(cells, seed + index) * weight for index, (cells, weight) in enumerate(octaves))
    return total / sum(weight for _, weight in octaves)


def shape(draw):
    """A mask in [0, 1] of whatever draw() paints."""
    mask = Image.new('L', (DRAW, DRAW), 0)
    draw(ImageDraw.Draw(mask))
    return np.asarray(mask, float) / 255


def marking():
    """The full-size marking as RGBA."""
    s, c = DRAW, DRAW / 2
    rng = np.random.default_rng(SEED)
    inset, inner = s * 0.06, s * 0.13
    plate = shape(lambda d: d.rounded_rectangle([inset, inset, s - inset, s - inset], radius=s * 0.07, fill=255))
    border = plate - shape(lambda d: d.rounded_rectangle([inner, inner, s - inner, s - inner], radius=s * 0.04,
                                                          fill=255))
    radius, width = s * 0.27, s * 0.055
    disc = shape(lambda d: d.ellipse([c - radius, c - radius, c + radius, c + radius], fill=255))
    ring = disc - shape(lambda d: d.ellipse([c - radius + width, c - radius + width, c + radius - width,
                                             c + radius - width], fill=255))

    def letter_p(d):
        left, right, top, bottom = c - s * .11, c - s * .045, c - s * .17, c + s * .17
        d.rectangle([left, top, right, bottom], fill=255)
        d.rounded_rectangle([left, top, c + s * .12, c + s * .03], radius=s * .1, fill=255)

    counter = shape(lambda d: d.rounded_rectangle([c - s * .045, c - s * .115, c + s * .06, c - s * .025],
                                                  radius=s * .045, fill=255))
    letter = np.clip(shape(letter_p) - counter, 0, 1)
    reach = radius - width / 2
    offset = math.cos(math.radians(45)) * reach
    slash = shape(lambda d: d.line([c - offset, c - offset, c + offset, c + offset], fill=255, width=int(width))) * disc

    grime = fbm(10)
    rgb = np.zeros((s, s, 3)) + PAINT * (0.78 + 0.3 * grime)[..., None]
    for layer, colour in ((border, RED), (ring, RED), (letter * (1 - slash), BLACK), (slash, RED)):
        rgb = rgb * (1 - layer[..., None]) + colour * layer[..., None] * (0.85 + 0.25 * grime[..., None])

    dirt = np.clip((fbm(40, ((3, .6), (7, .3), (19, .1))) - .45) * 2.2, 0, 1)[..., None]
    rgb = rgb * (1 - .45 * dirt) + DIRT * .45 * dirt
    y, x = np.mgrid[0:s, 0:s]
    oil = (np.exp(-(((x - s * .66) / (s * .12)) ** 2 + ((y - s * .7) / (s * .08)) ** 2)) * (.6 + .4 * fbm(77)))[..., None]
    rgb = rgb * (1 - .55 * oil) + OIL * .55 * oil

    scuffs = Image.new('L', (s, s), 0)
    draw = ImageDraw.Draw(scuffs)
    for _ in range(7):  # soft dark tyre marks
        start = rng.uniform(.1, .9) * s
        draw.line([0, start, s, start + rng.uniform(-.25, .25) * s], fill=int(rng.uniform(30, 70)),
                  width=int(rng.uniform(6, 16)))
    rgb *= (1 - .5 * np.asarray(scuffs.filter(ImageFilter.GaussianBlur(5)), float) / 255)[..., None]

    scratches = Image.new('L', (s, s), 0)
    draw = ImageDraw.Draw(scratches)
    for _ in range(40):
        x0, y0 = rng.uniform(0, s, 2)
        angle, length = rng.uniform(0, math.pi), rng.uniform(.03, .15) * s
        draw.line([x0, y0, x0 + math.cos(angle) * length, y0 + math.sin(angle) * length],
                  fill=int(rng.uniform(60, 140)), width=1)
    scratched = (np.asarray(scratches, float) / 255)[..., None]
    rgb = rgb * (1 - .35 * scratched) + SCRATCH * .35 * scratched

    # Chipped paint lets the ground show through, more so near the worn edges.
    edge = np.minimum.reduce([x, y, s - 1 - x, s - 1 - y]) / s
    chipped = (fbm(120, ((11, .5), (27, .3), (70, .2))) + (0.12 - edge).clip(0) * 2.5) > .66
    alpha = plate * np.where(chipped, .15, 1.0) * (0.9 + 0.1 * grime)
    rgb = rgb * (1 + .08 * (fbm(200, ((90, 1),)) - .5))[..., None]
    pixels = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
    return Image.fromarray(pixels, 'RGBA')


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


def main():
    OUTPUT.mkdir(exist_ok=True)
    # Reduced with premultiplied alpha, so chipped edges don't darken.
    tile = marking().convert('RGBa').resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert('RGBA')
    encoded = BytesIO()
    tile.save(encoded, format='PNG', optimize=True)
    replace_atomically(OUTPUT / 'loading-zone.png', encoded.getvalue())
    record = {
        'loading-zone.png': {
            'generator': Path(__file__).relative_to(ROOT.parents[1]).as_posix(),
            'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'sha256': hashlib.sha256(encoded.getvalue()).hexdigest(),
            'size': SIZE,
        }
    }
    replace_atomically(OUTPUT / 'loading-zone.json', (json.dumps(record, indent=2) + '\n').encode())
    print(f'{(OUTPUT / "loading-zone.png").relative_to(ROOT.parents[1])}: {SIZE} x {SIZE}')


if __name__ == '__main__':
    main()
