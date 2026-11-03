#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""The committed generated depot Lua must equal what its generators produce from committed data.

package_depots.py and package_connector.py write these files. Regenerating them
here catches a generator change that wasn't regenerated (or a hand-edited
output), so the Lua checks always see the generators' real output.
"""
import importlib.util
from pathlib import Path
import unittest

DEPOT_LUA = Path(__file__).resolve().parents[1] / 'assets/depots/tools/depot_lua.py'
spec = importlib.util.spec_from_file_location('depot_lua', DEPOT_LUA)
depot_lua = importlib.util.module_from_spec(spec)
spec.loader.exec_module(depot_lua)

REGENERATE = 'regenerate it by packaging again (assets/depots/README.md), never edit it by hand'


class GeneratedLuaTests(unittest.TestCase):
    def test_definitions_match_asset_metadata(self):
        self.assertEqual(depot_lua.DEFINITIONS.read_text(), depot_lua.definitions_lua(),
                         f'{depot_lua.DEFINITIONS.name} is out of date; {REGENERATE}')

    def test_pipe_pictures_match_connector_record(self):
        shift = depot_lua.recorded_pipe_shift()
        self.assertEqual(depot_lua.PIPE_PICTURES.read_text(), depot_lua.pipe_pictures_lua(shift),
                         f'{depot_lua.PIPE_PICTURES.name} is out of date; {REGENERATE}')

    def test_generators_use_the_shared_renderer(self):
        # A packager that builds its own Lua again would bypass this test.
        tools = DEPOT_LUA.parent
        for name, function in (('package_depots.py', 'definitions_lua('),
                               ('package_connector.py', 'pipe_pictures_lua(')):
            source = (tools / name).read_text()
            self.assertIn('from depot_lua import', source, name)
            self.assertIn(function, source, name)
            self.assertNotIn('return {', source, f'{name} should not template Lua itself')


if __name__ == '__main__':
    unittest.main()
