#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Tests for tools/portal_page.py: the page's rules, its pinned links and the portal sync, with simulated replies."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import portal_page
from publish_mod import PORTAL

RAW = 'https://raw.githubusercontent.com/jatmn/jatz-distribution/v0.1.2/'
BLOB = 'https://github.com/jatmn/jatz-distribution/blob/v0.1.2/'


class PortalPage(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.write('info.json', json.dumps({'name': 'jatz-distribution', 'version': '0.1.2'}))
        self.write('docs/guide.md', '# Guide\n')
        self.write('docs/images/hero.jpg', b'hero')
        self.write('portal/images/truck.png', b'truck')
        self.write('portal/summary.txt', 'Freight trucks by road.\n')
        self.write('portal/description.md', (
            '[![Truck](images/truck.png)](images/truck.png)\n\n'
            'Read the [guide](../docs/guide.md#fuel), the [docs](../docs) and the [top](#credits).\n'
            '![Hero](../docs/images/hero.jpg "Depots") and [Transport Drones](https://mods.factorio.com/mod/Transport_Drones).\n'))

    def tearDown(self):
        self.directory.cleanup()

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding='utf-8')
        return path

    def gallery(self, *names):
        return [self.write(f'portal/gallery/{name}', name.encode()) for name in names]

    def listing(self, **fields):
        page = portal_page.render('v0.1.2', self.root)
        return {'summary': page['summary'], 'description': page['description'], 'images': [],
                'releases': [{'version': '0.1.2'}], **fields}

    def sync(self, listing, replies=(), token='fixture-key', dry_run=False):
        with patch.object(portal_page, 'full_listing', return_value=listing), patch.object(
                portal_page, 'request_json', side_effect=list(replies)) as request:
            portal_page.sync('v0.1.2', token, dry_run, self.root)
        return request.call_args_list

    def test_relative_links_are_pinned_to_the_tag(self):
        description = portal_page.render('v0.1.2', self.root)['description']
        self.assertIn(f'[![Truck]({RAW}portal/images/truck.png)]({RAW}portal/images/truck.png)', description)
        self.assertIn(f'[guide]({BLOB}docs/guide.md#fuel)', description)
        self.assertIn('[docs](https://github.com/jatmn/jatz-distribution/tree/v0.1.2/docs)', description)
        self.assertIn(f'![Hero]({RAW}docs/images/hero.jpg "Depots")', description)
        self.assertIn('[top](#credits)', description)
        self.assertIn('(https://mods.factorio.com/mod/Transport_Drones)', description)

    def test_page_rules(self):
        cases = [
            ('portal/summary.txt', 'x' * 501, 'allows 500'),
            ('portal/summary.txt', '  \n', 'summary.txt is empty'),
            ('portal/description.md', '[out](../../secret.md)', 'outside the repository'),
            ('portal/description.md', '[gone](../docs/missing.md)', 'does not exist'),
            ('portal/description.md', '[root](/docs/guide.md)', 'relative to portal/'),
            ('portal/description.md', '[ref][guide]\n\n[guide]: ../docs/guide.md', 'reference-style'),
            ('portal/description.md', '[spaced](../docs/my guide.md)', 'would not be rewritten'),
        ]
        for name, content, message in cases:
            with self.subTest(content=content):
                original = (self.root / name).read_text(encoding='utf-8')
                self.write(name, content)
                with self.assertRaisesRegex(ValueError, message):
                    portal_page.render('v0.1.2', self.root)
                self.write(name, original)
        with self.assertRaisesRegex(ValueError, 'not committed'):
            portal_page.render('v0.1.2', self.root, tracked={'docs/guide.md'})
        self.write('portal/gallery/notes.txt', 'notes')
        with self.assertRaisesRegex(ValueError, 'only PNG and JPEG'):
            portal_page.render('v0.1.2', self.root)
        (self.root / 'portal/gallery/notes.txt').unlink()
        self.write('portal/gallery/huge.png', b'0' * (portal_page.IMAGE_LIMIT + 1))
        with self.assertRaisesRegex(ValueError, 'over 5 MiB'):
            portal_page.render('v0.1.2', self.root)

    def test_an_unchanged_page_sends_nothing(self):
        shots = self.gallery('01-depots.png', '02-road.jpg')
        images = [{'id': hashlib.sha1(path.read_bytes()).hexdigest()} for path in shots]
        self.assertEqual(self.sync(self.listing(images=images), token=None), [])
        # The portal's own line endings and trailing spaces don't count as a change.
        listing = self.listing(images=images)
        listing['description'] = listing['description'].replace('\n', ' \r\n')
        self.assertEqual(self.sync(listing, token=None), [])

    def test_only_changed_details_are_sent(self):
        calls = self.sync(self.listing(description='Old text'), [{'success': True, 'url': '/api/mods/jatz-distribution'}])
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0].args[0], PORTAL + '/api/v2/mods/edit_details')
        self.assertEqual(set(calls[0].args[1]), {'mod', 'description'})
        self.assertIn(RAW + 'portal/images/truck.png', calls[0].args[1]['description'])
        self.assertEqual(calls[0].kwargs['token'], 'fixture-key')
        with self.assertRaisesRegex(ValueError, 'refused to change the summary: Forbidden key'):
            self.sync(self.listing(summary='Old'), [{'error': 'Forbidden', 'message': 'Forbidden key'}])

    def test_gallery_uploads_new_images_keeps_old_ones_and_sets_the_order(self):
        kept, new = self.gallery('01-depots.png', '02-road.jpg')
        kept_id = hashlib.sha1(kept.read_bytes()).hexdigest()
        replies = [{'upload_url': 'https://uploads.example.test/image'}, {'id': 'new-id', 'url': 'u', 'thumbnail': 't'},
                   {'success': True, 'images': [{'id': kept_id}, {'id': 'new-id'}]}]
        calls = self.sync(self.listing(images=[{'id': 'stale-id'}, {'id': kept_id}]), replies)
        self.assertEqual([call.args[0] for call in calls], [
            PORTAL + '/api/v2/mods/images/add', 'https://uploads.example.test/image', PORTAL + '/api/v2/mods/images/edit'])
        upload = calls[1]
        self.assertEqual((upload.kwargs['archive'], upload.kwargs['field'], upload.kwargs['content_type']),
                         (new, 'image', 'image/jpeg'))
        self.assertNotIn('token', upload.kwargs)  # the upload URL authorizes itself
        self.assertEqual(calls[2].args[1], {'mod': 'jatz-distribution', 'images': f'{kept_id},new-id'})
        with self.assertRaisesRegex(ValueError, 'does not match portal/gallery'):
            self.sync(self.listing(images=[{'id': kept_id}]), replies[:2] + [{'success': True, 'images': []}])
        with self.assertRaisesRegex(ValueError, 'valid HTTPS'):
            self.sync(self.listing(), [{'upload_url': 'http://uploads.example.test/image'}])

    def test_an_empty_gallery_folder_leaves_the_live_gallery_alone(self):
        self.assertEqual(self.sync(self.listing(images=[{'id': 'added-by-hand'}]), token=None), [])

    def test_dry_run_needs_no_key_and_sync_refuses_unsafe_states(self):
        self.assertEqual(self.sync(self.listing(summary='Old'), token=None, dry_run=True), [])
        self.assertEqual(self.sync(None, token=None, dry_run=True), [])
        with self.assertRaisesRegex(ValueError, 'publish the release'):
            self.sync(None)
        with self.assertRaisesRegex(ValueError, 'Connect FACTORIO_API_KEY'):
            self.sync(self.listing(summary='Old'), token=None)
        with self.assertRaisesRegex(ValueError, 'newer release'):
            self.sync(self.listing(summary='Old', releases=[{'version': '0.1.2'}, {'version': '0.1.3'}]))
        # A tag not uploaded yet never sets the live page (its links point at that tag), but can be previewed.
        unpublished = self.listing(summary='Old', releases=[{'version': '0.1.1'}])
        with self.assertRaisesRegex(ValueError, 'v0.1.2 is not on the portal yet'):
            self.sync(unpublished)
        self.assertEqual(self.sync(unpublished, token=None, dry_run=True), [])
        with self.assertRaisesRegex(ValueError, 'stable tag'):
            portal_page.sync('main', 'fixture-key', root=self.root)


if __name__ == '__main__':
    unittest.main()
