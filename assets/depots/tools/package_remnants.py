# SPDX-License-Identifier: LGPL-3.0-only
"""Package the rendered remnants into game sheets with the shared sprite extractor.

Each wreck's sheets/<layer>.png is one row of 512 px frames, one per direction, in the
order the game turns the entity: north, then clockwise. asset.json's `directions` name the
artwork's directions as rendered; `sheet_order` (if given) says which rendered direction each
sheet frame is, for depots the mod shows half a turn round (prototypes/orientation.lua), whose
wreck facing north must be the artwork's south. validation.json records the inputs the
renders came from (master, wreck builder, seed), which tools/check_blender_sources.py compares
with the committed files.

  python3 assets/depots/tools/package_remnants.py            # add --name cargo for one
"""
import argparse
import importlib.util
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
spec = importlib.util.spec_from_file_location('shared_packager', REPO / 'assets/quinityn-freighter/tools/package_sprites.py')
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)
spec = importlib.util.spec_from_file_location('render_remnants', ROOT / 'tools/render_remnants.py')
render = importlib.util.module_from_spec(spec)
spec.loader.exec_module(render)
LAYERS = ['shadow', 'base', 'mask-cab', 'mask-trim', 'mask-cargo', 'preview']
BACKGROUND = (51, 54, 55, 255)


def package(folder):
    meta = json.loads((folder / 'asset.json').read_text())
    count = len(meta['directions'])
    order = meta.get('sheet_order', list(range(count)))
    assert sorted(order) == list(range(count))
    recorded = json.loads((folder / 'masters/render-inputs.json').read_text())
    expected = render.inputs(folder / 'asset.json', recorded['resolution'], recorded['samples'])
    assert recorded == expected, f'{folder.name}: the renders are from other inputs; render again'
    shared.ROOT = folder
    shared.PALETTE = meta['palette']
    size = meta['game_frame_size']
    checks = [shared.extract(direction, [(recorded['resolution'], folder / 'masters/layers'), (size, folder / 'frames')])
              for direction in range(count)]
    for layer in LAYERS:
        atlas = Image.new('RGBA', (size * count, size))
        for index, direction in enumerate(order):
            path = folder / f'frames/{layer}-{direction:02}.png'
            with Image.open(path) as image:
                assert image.mode == 'RGBA' and image.size == (size, size)
                alpha = np.asarray(image)[:, :, 3]
                assert alpha.max() > 0, f'Empty layer {path}'
                assert not np.any(alpha[[0, -1], :]) and not np.any(alpha[:, [0, -1]]), f'Clipped {path}'
                if layer.startswith('mask-'):
                    array = np.asarray(image)
                    assert np.array_equal(array[:, :, 0], array[:, :, 1]) and np.array_equal(array[:, :, 1], array[:, :, 2])
                atlas.paste(image, (index * size, 0))
        atlas.save(folder / f'sheets/{layer}.png')
    # Every sheet frame as the game draws it, shadow under the wreck, on the depot previews' grey,
    # named by the direction the entity faces and, if they differ, the artwork's direction it shows.
    tile = 256
    board = Image.new('RGBA', (tile * count, tile + 24), BACKGROUND)
    draw = ImageDraw.Draw(board)
    for index, direction in enumerate(order):
        name = meta['directions'][direction]
        if 'sheet_order' in meta:
            name = f'{meta["directions"][index]}: artwork {name}'
        frame = Image.new('RGBA', (size, size), BACKGROUND)
        frame.alpha_composite(Image.open(folder / f'frames/shadow-{direction:02}.png'))
        frame.alpha_composite(Image.open(folder / f'frames/preview-{direction:02}.png'))
        board.paste(frame.resize((tile, tile), Image.Resampling.LANCZOS), (index * tile, 24))
        draw.text((index * tile + 8, 6), name, fill='white')
    board.save(folder / 'previews/directions.png')
    result = {'name': meta['name'], **expected, 'directions': checks}
    (folder / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print('PACKAGED AND VALIDATED', meta['name'], flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--name')
    args = parser.parse_args()
    variants = [path.parent for path in render.wrecks(args.name)]
    assert variants, 'No remnants found'
    for folder in variants:
        package(folder)


if __name__ == '__main__':
    main()
