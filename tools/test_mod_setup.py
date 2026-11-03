#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Unit tests without Factorio: test_mod.py's expansion resolution and locale parsing, the English
names, the icon size the prototypes declare, and the depots' orientation and loading zones."""
from pathlib import Path
import re
import shutil
import subprocess
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


class IconTests(unittest.TestCase):
    def test_prototypes_declare_the_checked_icon_format(self):
        # prototypes/constants.lua sets icon_size for every icon; check_blender_sources.py checks
        # the icon files against ICON_SIZE. The two must agree.
        from check_blender_sources import ICON_SIZE
        constants = (Path(__file__).resolve().parents[1] / 'prototypes/constants.lua').read_text()
        self.assertEqual(re.findall(r'^\s*icon_size = (\d+),', constants, re.MULTILINE), [str(ICON_SIZE)])


ROOT = Path(__file__).resolve().parents[1]
# Runs prototypes/orientation.lua on the real depot definitions, as the data stage does.
ORIENTATION_CHECK = r"""
package.path = "./?.lua;" .. package.path
local orientation = require("prototypes.orientation")
local definitions = require("assets.depots.factorio.depot-definitions")
local VECTOR = { [0] = { 0, -1 }, [4] = { 1, 0 }, [8] = { 0, 1 }, [12] = { -1, 0 } }
local DIRECTIONS = { "north", "east", "south", "west" }
local function turn(x, y, quarter_turns)
  for _ = 1, quarter_turns do
    x, y = -y, x
  end
  return x, y
end
for role, sizes in pairs(definitions) do
  local ports = orientation.ports(role, sizes[3].ports)
  -- Unrotated: the loading zone is to the south.
  local zone = orientation.loading_zone_shift.north
  assert(zone[1] == 0 and zone[2] == 2, role .. ": unrotated loading zone must be south")
  for quarter, direction in ipairs(DIRECTIONS) do
    local turns = quarter - 1
    -- The loading zone follows the entity as it rotates clockwise.
    local zx, zy = turn(0, 2, turns)
    local shift = orientation.loading_zone_shift[direction]
    assert(shift[1] == zx and shift[2] == zy, role .. ": loading zone doesn't follow rotation " .. direction)
    for _, port in ipairs(ports) do
      local vector = VECTOR[port.direction]
      local px, py = turn(port.position[1] + vector[1], port.position[2] + vector[2], turns)
      assert(not (px == zx and py == zy), role .. ": a pipe connects on the loading zone tile")
    end
  end
  if role:find("^liquid") then
    for _, port in ipairs(ports) do
      assert(port.direction == 0, role .. ": liquid depot pipes must face north, opposite the loading zone")
    end
  end
  print(role, orientation.half_turn[role] and "half-turn" or "as-drawn", #ports)
end
local fuel = orientation.ports("fuel", definitions.fuel[3].ports)[1]
assert(fuel.position[1] == 1 and fuel.position[2] == 0 and fuel.direction == 4, "fuel port must be on the east")
local art = { north = "N", east = "E", south = "S", west = "W" }
local shown = orientation.pictures("provider", art)
assert(shown.north == "S" and shown.east == "W" and shown.south == "N" and shown.west == "E", "half turn")
assert(orientation.pictures("liquid-provider", art) == art, "liquid depots keep their artwork")
"""


class OrientationTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('lua5.2'), 'the Mod CI job installs Lua 5.2')
    def test_loading_zone_is_south_by_default_and_never_on_a_pipe(self):
        result = subprocess.run(['lua5.2', '-'], input=ORIENTATION_CHECK, cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        roles = dict(line.split('\t', 1) for line in result.stdout.splitlines())
        self.assertEqual(len(roles), 7, result.stdout)
        for role in ('provider', 'request', 'buffer', 'fuel'):
            self.assertTrue(roles[role].startswith('half-turn'), role)
        for role in ('liquid-provider', 'liquid-request', 'liquid-buffer'):
            self.assertTrue(roles[role].startswith('as-drawn'), role)


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
