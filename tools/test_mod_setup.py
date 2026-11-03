#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Unit tests for test_mod.py's setup logic, without Factorio: expansion resolution and locale parsing."""
from pathlib import Path
import shutil
import tempfile
import unittest

from test_mod import enabled_with, locale_keys

# The dependencies Factorio 2.1.24 ships for its bundled mods.
BUNDLED = {
    'base': {'dependencies': []},
    'elevated-rails': {'dependencies': ['base >= 2.1.0']},
    'recycler': {'dependencies': ['base >= 2.1.0']},
    'quality': {'dependencies': ['base >= 2.1.0', 'recycler >= 2.1.0']},
    'space-age': {'dependencies': ['base >= 2.1.0', 'elevated-rails >= 2.1.0', '+ quality >= 2.1.0',
                                   'recycler >= 2.1.0']},
}


class ExpansionTests(unittest.TestCase):
    def test_space_age_brings_its_required_and_recommended_mods(self):
        self.assertEqual(enabled_with('space-age', BUNDLED),
                         {'space-age', 'base', 'elevated-rails', 'recycler', 'quality'})

    def test_missing_space_age_or_a_required_mod_skips_the_run(self):
        self.assertIsNone(enabled_with('space-age', {k: v for k, v in BUNDLED.items() if k != 'space-age'}))
        self.assertIsNone(enabled_with('space-age', {k: v for k, v in BUNDLED.items() if k != 'recycler'}))

    def test_optional_and_incompatible_dependencies_are_not_enabled(self):
        bundled = {'a': {'dependencies': ['? b', '(?) c', '! d', '~ e']}, 'b': {}, 'c': {}, 'd': {}, 'e': {}}
        self.assertEqual(enabled_with('a', bundled), {'a', 'e'})


class LocaleTests(unittest.TestCase):
    def test_keys_are_section_qualified(self):
        root = Path(tempfile.mkdtemp(prefix='jatz-locale-'))
        self.addCleanup(shutil.rmtree, root)
        (root / 'locale/en').mkdir(parents=True)
        (root / 'locale/en/a.cfg').write_text('[entity-name]\nx=X\n; y=comment\n\n[item-name]\nz=Z = still Z\n')
        self.assertEqual(locale_keys(root), {'entity-name.x', 'item-name.z'})

    def test_every_mod_entity_has_a_name(self):
        keys = locale_keys()
        roles = ('provider', 'request', 'buffer', 'fuel', 'liquid-provider', 'liquid-request', 'liquid-buffer')
        for name in ['jatz-quinityn-freighter'] + [f'jatz-{role}-depot' for role in roles]:
            with self.subTest(name=name):
                self.assertIn(f'entity-name.{name}', keys)
                self.assertIn(f'entity-description.{name}', keys)


if __name__ == '__main__':
    unittest.main()
