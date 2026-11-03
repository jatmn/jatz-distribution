#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Exercise check_blender_sources.py on a small synthetic repository; no Blender or real art needed."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from check_blender_sources import BLEND_HEADER, check

ARCHIVE = 'assets/depots/archive/1x1'


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode())
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record(path, data):
    write(path, json.dumps(data))


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
    record(freighter / 'geometry-validation.json', {'model_sha256': model})
    record(freighter / 'asset.json', {'concept_sha256': concept})
    record(freighter / 'checksums.json', {'source/quinityn-freighter.blend': model,
                                          'sheets/freighter-base.png': sheet, 'tools/x.py': 'not checked'})
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
                record(asset / 'geometry-validation.json', {'model_sha256': digest})
                checksums = json.loads((asset / 'checksums.json').read_text())
                checksums['source/quinityn-freighter.blend'] = digest
                record(asset / 'checksums.json', checksums)
                self.assertOneError(self.errors('freighter'), 'quinityn-freighter.blend', 'Blender 4.3.2')

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

    def test_areas_are_checked_independently(self):
        write(self.root / 'assets/depots/source/fuel-3.blend', b'not a blend file')
        self.assertEqual(self.errors('freighter'), [])
        self.assertTrue(self.errors('depots'))


if __name__ == '__main__':
    unittest.main()
