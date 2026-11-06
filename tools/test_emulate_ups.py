#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Checks that the engine-free UPS emulator (tests/lua/ups-emulator.lua) counts the mod's own Lua
and nothing else: inert work added to the fake runtime, in a method or a computed property, must
leave every number unchanged, and work added to a mod handler must show up exactly. Needs Lua 5.2;
CI's UPS benchmark check runs it before comparing a pull request with its base."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = shutil.which('lua5.2')
PRESET, TICKS = 'quick', '600'
# A loop Lua 5.2 compiles to exactly 206 instructions: 5 to set it up, 2 per pass, 1 to leave.
LOOP = '  local noop = 0\n  for index = 1, 100 do\n    noop = noop + index\n  end\n'
LOOP_INSTRUCTIONS = 206


def inject(path, anchor, code):
    text = path.read_text()
    if text.count(anchor) != 1:
        raise AssertionError(f'{path.name}: expected the anchor {anchor!r} exactly once')
    path.write_text(text.replace(anchor, anchor + code))


@unittest.skipUnless(LUA, 'needs lua5.2')
class EmulatorCountsOnlyTheModTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.tree = Path(self.directory.name)
        # The emulator finds the benchmark map beside it, as in the repository.
        shutil.copytree(ROOT / 'tests/lua', self.tree / 'tests/lua')
        shutil.copytree(ROOT / 'tests/factorio/ups-benchmark_0.1.0', self.tree / 'tests/factorio/ups-benchmark_0.1.0')
        self.mod = self.tree / 'mod'
        self.mod.mkdir()
        shutil.copy(ROOT / 'control.lua', self.mod)
        shutil.copytree(ROOT / 'scripts', self.mod / 'scripts')
        shutil.copytree(ROOT / 'prototypes', self.mod / 'prototypes')
        self.emulator = self.tree / 'tests/lua/ups-emulator.lua'

    def emulate(self):
        result = subprocess.run([LUA, str(self.emulator), str(self.mod), PRESET, TICKS], capture_output=True,
                                text=True, timeout=600)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout.strip().splitlines()[-1])
        report.pop('cpu_seconds')
        return report

    def test_repeated_runs_agree_exactly(self):
        self.assertEqual(self.emulate(), self.emulate())

    def test_work_inside_a_fake_method_is_not_counted(self):
        before = self.emulate()
        inject(self.emulator, '  function inv.get_item_count(id)\n', LOOP)
        self.assertEqual(self.emulate(), before)

    def test_work_inside_a_fake_property_is_not_counted(self):
        before = self.emulate()
        inject(self.emulator, '        __index = function(_, field)\n          if field == "position" then\n',
               LOOP.replace('  ', '          ', 1))
        self.assertEqual(self.emulate(), before)

    def test_work_inside_a_mod_handler_is_counted_exactly(self):
        before = self.emulate()
        inject(self.mod / 'scripts/logistics.lua', 'function logistics.on_tick_share(tick)\n', LOOP)
        after = self.emulate()
        # logistics.on_tick_share runs every tick (control.lua's on_tick).
        calls = before['ticks']
        self.assertGreater(calls, 0)
        self.assertEqual(round((after['instructions_per_tick'] - before['instructions_per_tick']) * before['ticks']),
                         LOOP_INSTRUCTIONS * calls)
        self.assertEqual(after['instructions_max'] - before['instructions_max'], LOOP_INSTRUCTIONS)
        # The same workload: only the count moved.
        for key in ('api_calls_per_tick', 'path_requests', 'commands', 'freighters_sent', 'vehicles_out',
                    'delivered', 'spilled'):
            self.assertEqual(after[key], before[key], key)


if __name__ == '__main__':
    unittest.main()
