#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Exercise check_blender_sources.py on a small synthetic repository; no Blender or real art needed."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
import zlib

from check_blender_sources import BLEND_HEADER, check

ARCHIVE = 'assets/depots/archive/1x1'


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode())
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record(path, data):
    write(path, json.dumps(data))


def png(width, height, color_type=6, slots=((0, 64), (64, 32), (96, 16), (112, 8)), filter_type=0, extra=None):
    """An 8-bit PNG (color type 6 is RGBA) with opaque squares in the given mipmap slots.

    filter_type applies one PNG scanline filter to every row, to exercise the checker's decoder.
    extra is an optional (x, y) pixel to make opaque as well.
    """
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    channels = {6: 4, 2: 3}[color_type]
    pixels = [[[0] * channels for _ in range(width)] for _ in range(height)]
    for x, size in slots:
        for y in range(min(size, height)):
            for column in range(x, min(x + size, width)):
                pixels[y][column] = [80, 120, 160, 255][:channels]
    if extra:
        pixels[extra[1]][extra[0]] = [255] * channels
    raw, previous = b'', [0] * (width * channels)
    for row in pixels:
        flat = [value for pixel in row for value in pixel]
        filtered = []
        for i, value in enumerate(flat):
            left = flat[i - channels] if i >= channels else 0
            up, corner = previous[i], previous[i - channels] if i >= channels else 0
            estimate = left + up - corner
            distances = (abs(estimate - left), abs(estimate - up), abs(estimate - corner))
            predictor = (0, left, up, (left + up) // 2, (left, up, corner)[distances.index(min(distances))])
            filtered.append((value - predictor[filter_type]) & 255)
        raw += bytes([filter_type] + filtered)
        previous = flat
    header = struct.pack('>IIBBBBB', width, height, 8, color_type, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(raw))
            + chunk(b'IEND', b''))


def make_icon(root, directory, name, source):
    """A 64 px icon with four mipmap levels (120 x 64) and its icons.json record."""
    render = root / source
    if not render.exists():
        write(render, b'presentation render')
    digest = write(root / directory / 'icons' / name, png(120, 64))
    record(root / directory / 'icons/icons.json', {name: {
        'source': source, 'source_sha256': hashlib.sha256(render.read_bytes()).hexdigest(),
        'sha256': digest, 'icon_size': 64, 'mipmaps': 4}})


def build(root):
    """A consistent repository: one fluid depot, the connector, the freighter and the archive."""
    shutil.rmtree(root / 'assets', ignore_errors=True)
    depots, freighter = root / 'assets/depots', root / 'assets/quinityn-freighter'
    fuel = write(depots / 'source/fuel-3.blend', BLEND_HEADER + b'fuel model')
    connector = write(depots / 'source/pipe-connector.blend', BLEND_HEADER + b'connector model')
    renderer = write(depots / 'tools/render_connector.py', 'print("render")\n')
    record(depots / 'fuel/3/asset.json', {'role': 'fuel', 'source': 'source/fuel-3.blend',
                                          'ports': [{'direction': 12, 'position': [-1, 0]}]})
    record(depots / 'fuel/3/validation.json', {'source_sha256': fuel})
    entry = {'role': 'fuel', 'size': 3, 'source_sha256': fuel}
    record(depots / 'validation.json', {'results': [entry]})
    record(depots / 'geometry-validation.json', {'results': [entry]})
    record(depots / 'junction-validation.json', {'connector_source_sha256': connector, 'results': [entry]})
    record(depots / 'connectors/validation.json', {'source_sha256': connector, 'renderer_sha256': renderer})
    model = write(freighter / 'source/quinityn-freighter.blend', BLEND_HEADER + b'truck model')
    concept = write(freighter / 'source/approved-concept.png', b'concept')
    sheet = write(freighter / 'sheets/freighter-base.png', b'sheet')
    record(freighter / 'validation.json', {'source_sha256': model, 'directions': []})
    record(freighter / 'geometry-validation.json', {'model_sha256': model})
    record(freighter / 'asset.json', {'concept_sha256': concept})
    record(freighter / 'checksums.json', {'source/quinityn-freighter.blend': model,
                                          'sheets/freighter-base.png': sheet, 'tools/x.py': 'not checked'})
    make_icon(root, 'assets/depots', 'fuel-depot.png', 'assets/depots/fuel/3/masters/hero-default-palette.png')
    make_icon(root, 'assets/quinityn-freighter', 'quinityn-freighter.png',
              'assets/quinityn-freighter/masters/hero-default-palette.png')
    generator = write(root / 'assets/depots/tools/make_loading_zone.py', 'print("draw")\n')
    marking = write(root / 'assets/depots/loading-zone/loading-zone.png', png(64, 64, slots=((0, 64),)))
    record(root / 'assets/depots/loading-zone/loading-zone.json', {'loading-zone.png': {
        'generator': 'assets/depots/tools/make_loading_zone.py', 'generator_sha256': generator,
        'sha256': marking, 'size': 64}})
    small = BLEND_HEADER + b'small model'
    digest = write(root / ARCHIVE / 'source/fuel-1.blend', small)
    write(root / ARCHIVE / 'README.md', 'archive\n')
    write(root / ARCHIVE / 'tools/build_depots.py', 'pass\n')
    record(root / ARCHIVE / 'manifest.json', {'source_commit': 'x', 'files': [
        {'path': 'source/fuel-1.blend', 'sha256': digest, 'bytes': len(small)}]})


class CheckerTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='jatz-blender-check-'))
        self.addCleanup(shutil.rmtree, self.root)
        build(self.root)

    def errors(self, *areas):
        return check(self.root, areas or ('freighter', 'depots'))

    def assertOneError(self, errors, *fragments):
        self.assertEqual(len(errors), 1, errors)
        for fragment in fragments:
            self.assertIn(fragment, errors[0])

    def test_consistent_repository_passes(self):
        self.assertEqual(self.errors(), [])

    def test_model_edited_without_rendering_or_inspecting(self):
        write(self.root / 'assets/depots/source/fuel-3.blend', BLEND_HEADER + b'edited fuel model')
        errors = self.errors('depots')
        # Its own packaging record, the combined packaging record, geometry and junction records.
        self.assertEqual(len(errors), 4, errors)
        self.assertTrue(all('fuel-3.blend' in error for error in errors), errors)
        self.assertTrue(any('render and package it again' in error for error in errors), errors)
        self.assertEqual(self.errors('freighter'), [])

    def test_connector_and_renderer_changes(self):
        write(self.root / 'assets/depots/tools/render_connector.py', 'print("changed")\n')
        self.assertOneError(self.errors('depots'), 'render_connector.py', 'renderer_sha256')
        build(self.root)
        write(self.root / 'assets/depots/source/pipe-connector.blend', BLEND_HEADER + b'edited connector')
        errors = self.errors('depots')
        self.assertEqual(len(errors), 2, errors)  # connector record and junction record
        self.assertTrue(all('pipe-connector.blend' in error for error in errors), errors)

    def test_wrong_blender_version_or_compression(self):
        for header in (b'BLENDER-v402', b'BLENDER17-01v0500', b'\x28\xb5\x2f\xfdcompressed'):
            with self.subTest(header=header):
                build(self.root)
                asset = self.root / 'assets/quinityn-freighter'
                digest = write(asset / 'source/quinityn-freighter.blend', header + b'truck model')
                # Keep the records current so that only the header is wrong.
                record(asset / 'validation.json', {'source_sha256': digest, 'directions': []})
                record(asset / 'geometry-validation.json', {'model_sha256': digest})
                checksums = json.loads((asset / 'checksums.json').read_text())
                checksums['source/quinityn-freighter.blend'] = digest
                record(asset / 'checksums.json', checksums)
                self.assertOneError(self.errors('freighter'), 'quinityn-freighter.blend', 'Blender 4.3.2')

    def test_freighter_model_revalidated_but_not_rendered(self):
        # Editing the model and refreshing the inspection and checksums, without
        # rendering, must still fail: only packaging records the rendered model.
        asset = self.root / 'assets/quinityn-freighter'
        digest = write(asset / 'source/quinityn-freighter.blend', BLEND_HEADER + b'edited truck model')
        record(asset / 'geometry-validation.json', {'model_sha256': digest})
        checksums = json.loads((asset / 'checksums.json').read_text())
        checksums['source/quinityn-freighter.blend'] = digest
        record(asset / 'checksums.json', checksums)
        self.assertOneError(self.errors('freighter'), 'quinityn-freighter.blend', 'sprites are from an older model',
                            'render_freighter.py')

    def test_freighter_sprite_or_concept_changed(self):
        write(self.root / 'assets/quinityn-freighter/sheets/freighter-base.png', b'hand edited')
        self.assertOneError(self.errors('freighter'), 'freighter-base.png', 'never hand-edit sprites')
        build(self.root)
        write(self.root / 'assets/quinityn-freighter/source/approved-concept.png', b'other concept')
        self.assertOneError(self.errors('freighter'), 'approved-concept.png', 'must stay unchanged')

    def test_frozen_archive(self):
        write(self.root / ARCHIVE / 'source/fuel-1.blend', BLEND_HEADER + b'changed small model')
        self.assertOneError(self.errors('depots'), 'fuel-1.blend', 'frozen')
        build(self.root)
        write(self.root / ARCHIVE / 'source/extra-1.blend', BLEND_HEADER)
        self.assertOneError(self.errors('depots'), 'extra-1.blend', 'not in the frozen 1x1 archive manifest')
        build(self.root)
        (self.root / ARCHIVE / 'source/fuel-1.blend').unlink()
        self.assertOneError(self.errors('depots'), 'fuel-1.blend', 'missing')
        # The archive's tools and README aren't in the manifest and may be edited.
        build(self.root)
        write(self.root / ARCHIVE / 'tools/build_depots.py', 'pass  # edited\n')
        write(self.root / ARCHIVE / 'README.md', 'edited\n')
        self.assertEqual(self.errors('depots'), [])

    def test_missing_record_is_reported_not_raised(self):
        (self.root / 'assets/quinityn-freighter/geometry-validation.json').unlink()
        self.assertOneError(self.errors('freighter'), 'geometry-validation.json', 'missing')

    def replace_icon(self, data):
        """Replace the depot icon, keeping its record's hash current so only the content is wrong."""
        icons = self.root / 'assets/depots/icons'
        digest = write(icons / 'fuel-depot.png', data)
        records = json.loads((icons / 'icons.json').read_text())
        records['fuel-depot.png']['sha256'] = digest
        record(icons / 'icons.json', records)
        return records

    def test_fully_transparent_icon_reports_every_level(self):
        self.replace_icon(png(120, 64, slots=()))
        errors = self.errors('depots')
        for size in (64, 32, 16, 8):
            self.assertTrue(any(f'the {size} px level is blank' in error for error in errors), errors)

    def test_decoder_handles_every_png_filter(self):
        for filter_type in range(5):
            with self.subTest(filter_type=filter_type):
                build(self.root)
                self.replace_icon(png(120, 64, filter_type=filter_type))
                self.assertEqual(self.errors('depots'), [])

    def test_icon_layout_matches_factorio(self):
        for data, problem in ((png(64, 64), '120x64'), (png(120, 64, color_type=2), '8-bit RGBA'),
                              (b'not a png', '8-bit RGBA'), (png(120, 64, slots=((64, 32), (96, 16), (112, 8))), '64 px level is blank'),
                              (png(120, 64, slots=((0, 64), (64, 32), (96, 16))), '8 px level is blank'),
                              (png(120, 64, extra=(100, 40)), 'outside the mipmap slots')):
            with self.subTest(problem=problem):
                build(self.root)
                self.replace_icon(data)
                self.assertOneError(self.errors('depots'), 'fuel-depot.png', problem, 'make_icons.py')

    def test_layout_is_not_taken_from_the_record(self):
        # A record and icon regenerated for another layout must not pass: the mod declares 64 px.
        records = self.replace_icon(png(56, 32, slots=((0, 32), (32, 16), (48, 8))))
        records['fuel-depot.png'].update(icon_size=32, mipmaps=3)
        record(self.root / 'assets/depots/icons/icons.json', records)
        errors = self.errors('depots')
        self.assertTrue(any('recorded as 32 px with 3 levels' in error for error in errors), errors)
        self.assertTrue(any('must be 120x64' in error for error in errors), errors)

    def test_required_icon_missing_with_its_record(self):
        (self.root / 'assets/depots/icons/fuel-depot.png').unlink()
        record(self.root / 'assets/depots/icons/icons.json', {})
        self.assertOneError(self.errors('depots'), 'fuel-depot.png', 'required by the mod')

    def test_icon_from_an_older_render_or_edited_by_hand(self):
        write(self.root / 'assets/quinityn-freighter/masters/hero-default-palette.png', b're-rendered')
        self.assertOneError(self.errors('freighter'), 'quinityn-freighter.png', 'made from an older')
        build(self.root)
        write(self.root / 'assets/depots/icons/fuel-depot.png', png(120, 64) + b'edited')
        self.assertOneError(self.errors('depots'), 'fuel-depot.png', 'does not match icons.json')

    def test_missing_or_unlisted_icons(self):
        (self.root / 'assets/depots/icons/fuel-depot.png').unlink()
        self.assertOneError(self.errors('depots'), 'fuel-depot.png', 'missing')
        build(self.root)
        write(self.root / 'assets/depots/icons/extra-depot.png', png(120, 64))
        self.assertOneError(self.errors('depots'), 'extra-depot.png', 'not in icons.json')

    def test_loading_zone_marking(self):
        folder = self.root / 'assets/depots/loading-zone'
        write(self.root / 'assets/depots/tools/make_loading_zone.py', 'print("redrawn")\n')
        self.assertOneError(self.errors('depots'), 'loading-zone.png', 'drawn by an older')
        for data, problem in ((png(32, 32, slots=((0, 32),)), 'must be 64x64'), (png(64, 64, slots=()), 'blank'),
                              (b'not a png', '8-bit RGBA')):
            with self.subTest(problem=problem):
                build(self.root)
                digest = write(folder / 'loading-zone.png', data)
                records = json.loads((folder / 'loading-zone.json').read_text())
                records['loading-zone.png']['sha256'] = digest
                record(folder / 'loading-zone.json', records)
                self.assertOneError(self.errors('depots'), 'loading-zone.png', problem)
        build(self.root)
        write(folder / 'loading-zone.png', png(64, 64, slots=((0, 64),)) + b'edited')
        self.assertOneError(self.errors('depots'), 'loading-zone.png', 'does not match')

    def test_areas_are_checked_independently(self):
        write(self.root / 'assets/depots/source/fuel-3.blend', b'not a blend file')
        self.assertEqual(self.errors('freighter'), [])
        self.assertTrue(self.errors('depots'))


if __name__ == '__main__':
    unittest.main()
