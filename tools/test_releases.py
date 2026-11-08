#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Exercise release packaging and portal decisions without publishing anything."""
import hashlib
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from package_mod import REPO, build, mod_files
import publish_mod
from release_metadata import SEPARATOR, finalize, package_metadata, split_notes
from validate_package import validate


class Releases(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / 'dist'
        # Preserve the actual file layout and metadata; tiny sprite placeholders
        # keep these packaging tests independent of rendering and image packages.
        for original in mod_files(REPO):
            target = self.root / original.relative_to(REPO)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b'sprite fixture' if original.suffix == '.png' else original.read_bytes())
        # The wrecks' records too, so packaging finds their sheets (assets/*/remnants/).
        for original in list((REPO / 'assets/depots').glob('*/3/asset.json')) + list(
                (REPO / 'assets').glob('*/remnants/*/asset.json')) + [
            REPO / '.github/version.txt', REPO / '.github/release-please-manifest.json',
        ]:
            target = self.root / original.relative_to(REPO)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(original.read_bytes())
        self.version = json.loads((self.root / 'info.json').read_text())['version']
        self.tag = 'v' + self.version
        # The tests add their own pending notes: start from the numbered history alone, without
        # the repository's own Unreleased notes.
        _, self.history = split_notes((self.root / 'changelog.txt').read_text())
        (self.root / 'changelog.txt').write_text(self.history)

    def bump(self):
        parts = [int(part) for part in self.version.split('.')]
        parts[2] += 1
        version = '.'.join(map(str, parts))
        info = json.loads((self.root / 'info.json').read_text())
        info['version'] = version
        (self.root / 'info.json').write_text(json.dumps(info))
        (self.root / '.github/version.txt').write_text(version + '\n')
        (self.root / '.github/release-please-manifest.json').write_text(json.dumps({'.': version}))
        return version

    def test_repeat_build_preserves_bytes_and_licences(self):
        archive, count = build(self.output, self.root)
        first = archive.read_bytes()
        for path in mod_files(self.root):
            os.utime(path, (1600000000, 1700000000))
        build(self.output, self.root)
        self.assertEqual(first, archive.read_bytes())
        info, _ = validate(self.output, self.tag, self.root)
        with zipfile.ZipFile(archive) as zipped:
            self.assertGreater(count, 80)
            for name in ('COPYING', 'COPYING.LESSER', 'NOTICE', 'assets/roads/yuoki-railways/Licence.txt'):
                self.assertEqual(zipped.read(f'{info["name"]}_{self.version}/{name}'), (self.root / name).read_bytes())
            self.assertFalse(any('/tools/' in name or '/masters/' in name for name in zipped.namelist()))

    def note_source(self, fragment):
        """Main's changelog and note files, as the release workflow copies them."""
        source = self.root / 'main-notes'
        if source.exists():
            for path in source.rglob('*'):
                if path.is_file():
                    path.unlink()
        unreleased = source / 'changelog' / 'unreleased'
        unreleased.mkdir(parents=True)
        (source / 'changelog.txt').write_text(self.history)
        (unreleased / 'cargo.txt').write_text(fragment)
        unreleased = self.root / 'changelog' / 'unreleased'
        unreleased.mkdir(parents=True, exist_ok=True)
        (unreleased / 'cargo.txt').write_text(fragment)
        return source

    def test_separate_note_files_merge_without_editing_changelog(self):
        changelog = (self.root / 'changelog.txt').read_text()
        notes = self.root / 'changelog' / 'unreleased'
        notes.mkdir(parents=True)
        (notes / 'a-bug.txt').write_text('  Bugfixes:\n    - First fix.\n')
        (notes / 'b-feature.txt').write_text('  Features:\n    - New depot.\n  Bugfixes:\n    - Second fix.\n')
        info, text = package_metadata(self.root)
        self.assertEqual((self.root / 'changelog.txt').read_text(), changelog)
        self.assertTrue((notes / 'a-bug.txt').is_file())
        self.assertIn('Version: ' + info['version'], text)
        self.assertLess(text.index('  Features:'), text.index('  Bugfixes:'))
        self.assertLess(text.index('First fix.'), text.index('Second fix.'))
        self.assertIn('Development snapshot.', text)

    def test_shared_changelog_section_is_rejected(self):
        (self.root / 'changelog.txt').write_text(
            SEPARATOR + 'Version: Unreleased\n  Bugfixes:\n    - Old shared section.\n' + self.history)
        with self.assertRaisesRegex(ValueError, 'changelog/unreleased'):
            package_metadata(self.root)

    def test_pending_notes_build_as_numeric_snapshot_then_finalize_and_refresh(self):
        fragment = '  Bugfixes:\n    - Keep delivered cargo.\n'
        source = self.note_source(fragment)
        kept = (self.root / 'changelog.txt').read_text()
        source_info = (self.root / 'info.json').read_bytes()
        build(self.output, self.root)
        info, _ = validate(self.output, root=self.root)
        self.assertNotEqual(info['version'], self.version)
        self.assertEqual((self.root / 'info.json').read_bytes(), source_info)
        self.assertEqual((self.root / 'changelog.txt').read_text(), kept)
        with self.assertRaisesRegex(ValueError, 'Finalize'):
            validate(self.output, 'v' + info['version'], self.root)
        version = self.bump()
        finalize(self.root, '2026-11-04', source)
        first = (self.root / 'changelog.txt').read_text()
        self.assertIn('Version: ' + version, first)
        self.assertNotIn('Unreleased', first)
        self.assertFalse((self.root / 'changelog' / 'unreleased' / 'cargo.txt').exists())
        finalize(self.root, '2026-11-05', source)
        self.assertEqual(first, (self.root / 'changelog.txt').read_text())
        (source / 'changelog' / 'unreleased' / 'cargo.txt').write_text(
            fragment.replace('Keep delivered cargo.', 'Keep all delivered cargo.'))
        finalize(self.root, '2026-11-05', source)
        updated = (self.root / 'changelog.txt').read_text()
        self.assertIn('Date: 2026-11-04', updated)
        self.assertIn('Keep all delivered cargo.', updated)
        build(self.output, self.root)
        validate(self.output, 'v' + version, self.root)

    def test_release_without_player_changes_and_mismatched_records(self):
        version = self.bump()
        with self.assertRaisesRegex(ValueError, 'top version'):
            package_metadata(self.root)
        finalize(self.root, '2026-11-04')
        self.assertIn('No player-facing changes.', (self.root / 'changelog.txt').read_text())
        build(self.output, self.root)
        validate(self.output, 'v' + version, self.root)
        (self.root / '.github/version.txt').write_text(self.version)
        with self.assertRaisesRegex(ValueError, 'version records'):
            build(self.output, self.root)

    def test_wrong_tag_corrupt_checksum_and_extra_zip_content_are_rejected(self):
        archive, _ = build(self.output, self.root)
        with self.assertRaisesRegex(ValueError, 'tag'):
            validate(self.output, 'v99.0.0', self.root)
        (self.output / 'SHA256SUMS').write_text('incorrect\n')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            validate(self.output, self.tag, self.root)
        build(self.output, self.root)
        with zipfile.ZipFile(archive, 'a') as zipped:
            zipped.writestr('../unexpected.txt', b'not a mod file')
        with self.assertRaisesRegex(ValueError, 'entries'):
            validate(self.output, self.tag, self.root)

    def test_invalid_player_notes_are_rejected(self):
        notes = self.root / 'changelog' / 'unreleased'
        notes.mkdir(parents=True)
        for body in ('\tBugfixes:\n', '  Bugfixes:\n    - trailing \n', '    - No category.\n'):
            with self.subTest(body=body):
                (notes / 'bad.txt').write_text(body)
                with self.assertRaises(ValueError):
                    build(self.output, self.root)

    def portal_release(self, archive):
        return {'releases': [{'version': self.version, 'file_name': archive.name,
                              'sha1': hashlib.sha1(archive.read_bytes()).hexdigest()}]}

    def test_first_portal_publication_needs_licence_and_never_forwards_key(self):
        archive, _ = build(self.output, self.root)
        with patch.object(publish_mod, 'listing', return_value=None), patch.object(publish_mod, 'request_json') as request:
            for licence in (None, 'default_mit', 'custom_', 'custom_6aee33da 2a59'):
                with self.subTest(licence=licence), self.assertRaisesRegex(ValueError, 'FACTORIO_LICENSE_ID'):
                    publish_mod.publish(self.output, self.tag, 'fixture-key', licence, self.root)
            request.assert_not_called()
        with patch.object(publish_mod, 'listing', side_effect=[None, self.portal_release(archive)]), patch.object(
            publish_mod, 'request_json', side_effect=[{'upload_url': 'https://uploads.example.test/upload'}, {'success': True}]
        ) as request:
            publish_mod.publish(self.output, self.tag, 'fixture-key', 'custom_6aee33da2a59c98152d81dc1', self.root)
            self.assertEqual(request.call_args_list[0].kwargs['token'], 'fixture-key')
            self.assertEqual(request.call_args_list[0].args[0], publish_mod.PORTAL + '/api/v2/mods/init_publish')
            self.assertNotIn('token', request.call_args_list[1].kwargs)
            self.assertEqual(request.call_args_list[1].args[1]['license'], 'custom_6aee33da2a59c98152d81dc1')

    def test_portal_retry_requires_identical_bytes_and_refuses_downgrades(self):
        archive, _ = build(self.output, self.root)
        listing = self.portal_release(archive)
        with patch.object(publish_mod, 'listing', return_value=listing), patch.object(publish_mod, 'request_json') as request:
            publish_mod.publish(self.output, self.tag, 'fixture-key', root=self.root)
            request.assert_not_called()
            listing['releases'][0]['sha1'] = 'wrong'
            with self.assertRaisesRegex(ValueError, 'different package bytes'):
                publish_mod.publish(self.output, self.tag, 'fixture-key', root=self.root)
            listing['releases'][0]['version'] = '99.0.0'
            with self.assertRaisesRegex(ValueError, 'newer version'):
                publish_mod.publish(self.output, self.tag, 'fixture-key', root=self.root)
            request.assert_not_called()

    def test_portal_listing_reads_past_the_cdn_cache(self):
        # The portal's CDN serves /api/mods/<name> from cache for 15 minutes: each read needs a URL it hasn't cached.
        with patch.object(publish_mod, 'request_json', return_value={'releases': []}) as request:
            publish_mod.listing('jatz-distribution')
            publish_mod.listing('jatz-distribution')
        first, second = (call.args[0] for call in request.call_args_list)
        self.assertTrue(first.startswith(publish_mod.PORTAL + '/api/mods/jatz-distribution?'))
        self.assertNotEqual(first, second)

    def test_existing_portal_upload_and_failed_publication_are_checked(self):
        archive, _ = build(self.output, self.root)
        with patch.object(publish_mod, 'listing', side_effect=[{'releases': []}, self.portal_release(archive)]), patch.object(
            publish_mod, 'request_json', side_effect=[{'upload_url': 'https://uploads.example.test/upload'}, {'success': True}]
        ) as request:
            publish_mod.publish(self.output, self.tag, 'fixture-key', root=self.root)
            self.assertEqual(request.call_args_list[0].args[0], publish_mod.PORTAL + '/api/v2/mods/releases/init_upload')
        with patch.object(publish_mod, 'listing', return_value={'releases': []}), patch.object(
            publish_mod, 'request_json', side_effect=[{'upload_url': 'https://uploads.example.test/upload'}, {'success': False}]
        ):
            with self.assertRaisesRegex(ValueError, 'rejected'):
                publish_mod.publish(self.output, self.tag, 'fixture-key', root=self.root)


class ReleaseBranchGuard(unittest.TestCase):
    def test_only_verified_metadata_branch_reaches_checkout(self):
        workflow = (REPO / '.github/workflows/release.yml').read_text()
        start = workflow.index('          branch=release-please--branches--main')
        end = workflow.index('          python3 tools/release_metadata.py', start)
        guard = '\n'.join(line[10:] for line in workflow[start:end].splitlines())
        for scenario in ('valid', 'code change', 'metadata symlink', 'note symlink', 'stale head'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                repo = root / 'repo'
                repo.mkdir()

                def git(*args):
                    return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.DEVNULL).decode().strip()

                git('init', '-b', 'main')
                git('config', 'user.name', 'Test')
                git('config', 'user.email', 'test@example.invalid')
                (repo / 'info.json').write_text('{"version":"0.1.0"}')
                (repo / 'changelog.txt').write_text('main notes')
                (repo / 'tool.py').write_text('trusted code')
                if scenario == 'note symlink':
                    notes = repo / 'changelog' / 'unreleased'
                    notes.mkdir(parents=True)
                    (notes / 'bad.txt').symlink_to('tool.py')
                git('add', '.')
                git('commit', '-m', 'base')
                base = git('rev-parse', 'HEAD')
                git('checkout', '-b', 'release-please--branches--main')
                (repo / 'info.json').write_text('{"version":"0.1.1"}')
                if scenario == 'code change':
                    (repo / 'tool.py').write_text('untrusted code')
                if scenario == 'metadata symlink':
                    (repo / 'changelog.txt').unlink()
                    (repo / 'changelog.txt').symlink_to('tool.py')
                git('add', '.')
                git('commit', '-m', 'release metadata')
                head = git('rev-parse', 'HEAD')
                git('checkout', 'main')
                git('remote', 'add', 'origin', str(repo))
                commands = root / 'bin'
                commands.mkdir()
                (commands / 'gh').write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_RELEASE_HEAD"\n')
                (commands / 'gh').chmod(0o755)
                env = {**os.environ, 'PATH': str(commands) + os.pathsep + os.environ['PATH'],
                       'TEST_RELEASE_HEAD': base if scenario == 'stale head' else head,
                       'GITHUB_SHA': base, 'RUNNER_TEMP': str(root)}
                result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', guard], cwd=repo,
                                        env=env, capture_output=True, text=True)
                if scenario == 'valid':
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(git('rev-parse', 'HEAD'), head)
                    self.assertEqual((root / 'player-notes' / 'changelog.txt').read_text(), 'main notes')
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(git('rev-parse', 'HEAD'), base)


if __name__ == '__main__':
    unittest.main()
