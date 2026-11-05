#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Read a tiny real EXR through the production sprite extractor; no Blender needed."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


class ArtDependencies(unittest.TestCase):
    def test_exr_channels_produce_the_expected_sprite_layers(self):
        import numpy as np
        import OpenEXR
        from PIL import Image

        script = Path(__file__).resolve().parents[1] / 'assets/quinityn-freighter/tools/package_sprites.py'
        spec = importlib.util.spec_from_file_location('freighter_package', script)
        package = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(package)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'masters/exr').mkdir(parents=True)
            (root / 'masters/shadow-silhouettes').mkdir()
            channels = {f'Vehicle.Combined.{name}': np.full((4, 4), value, dtype=np.float32)
                        for name, value in [('R', .25), ('G', .25), ('B', .25), ('A', 1)]}
            channels.update({f'Vehicle.mask_{name}.V': np.full((4, 4), value, dtype=np.float32)
                             for name, value in [('cab', 1), ('trim', 0), ('cargo', 0)]})
            OpenEXR.File({}, channels).write(str(root / 'masters/exr/direction-00.exr'))
            Image.new('RGBA', (4, 4), (0, 0, 0, 255)).save(root / 'masters/shadow-silhouettes/direction-00.png')
            with patch.object(package, 'ROOT', root):
                result = package.extract(0, [(4, root / 'frames')])
            self.assertEqual(result['sizes'][4]['mask_pixels'], {'cab': 16, 'trim': 0, 'cargo': 0})
            self.assertEqual(result['sizes'][4]['alpha_max_error'], 0)
            self.assertEqual(len(list((root / 'frames').glob('*.png'))), 6)
            with Image.open(root / 'frames/mask-cab-00.png') as cab:
                self.assertEqual(cab.getpixel((0, 0)), (137, 137, 137, 255))
            with Image.open(root / 'frames/base-00.png') as base:
                self.assertEqual(base.getpixel((0, 0)), (0, 0, 0, 0))


if __name__ == '__main__':
    unittest.main()
