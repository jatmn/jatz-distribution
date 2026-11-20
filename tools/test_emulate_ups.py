#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Checks that the engine-free UPS emulator (tests/lua/ups-emulator.lua) counts the mod's own Lua
and nothing else: inert work added to the fake runtime, in a method or a computed property, must
leave every number unchanged, and work added to a mod handler must show up exactly. Needs Lua 5.2;
CI's UPS benchmark check runs it before comparing a pull request with its base. It also checks that
the comparison (tools/emulate_ups.py --base) stops the base's emulation as soon as the working tree's
fails, rather than waiting for it."""
import contextlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
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

    def test_a_fake_prototype_method_outside_native_is_refused(self):
        # Prototypes are plain tables (not wrapped as a whole, as inventories and entities are), and
        # a method read once per item can run only before the measured ticks, where no count shows
        # it: the emulator checks every function in them before it runs.
        anchor = 'local NORMAL = prototypes.quality.normal\n'
        inject(self.emulator, anchor, 'prototypes.item["iron-plate"].get_spoil_ticks = function()\n  return 0\nend\n')
        result = subprocess.run([LUA, str(self.emulator), str(self.mod), PRESET, TICKS], capture_output=True,
                                text=True, timeout=600)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('prototypes.item.iron-plate.get_spoil_ticks is a fake runtime function outside native',
                      result.stderr)

    def test_work_inside_a_fake_property_is_not_counted(self):
        before = self.emulate()
        inject(self.emulator, '        __index = function(_, field)\n          if field == "position" then\n',
               LOOP.replace('  ', '          ', 1))
        self.assertEqual(self.emulate(), before)

    def test_the_fake_inventory_lists_an_item_once_however_many_stacks_hold_it(self):
        # As LuaInventory.get_contents does (one entry an item and quality: 48 stacks of iron plate
        # give one entry on 2.1.24). One a stack made a provider whose circuit condition reads its
        # contents count as 48 times the mod's work for it.
        inject(self.emulator, '-- The world: surfaces with road tiles, entities, scheduled engine events.\n', """do
  local name = next(STACK_SIZE)
  local chest = new_inventory(48)
  local held = chest.insert({ name = name, count = 3 * STACK_SIZE[name] })
  local contents = chest.get_contents()
  assert(held == 3 * STACK_SIZE[name], "setup: three stacks")
  assert(#contents == 1, "get_contents: " .. #contents .. " entries for one item in three stacks")
  assert(contents[1].name == name and contents[1].count == held and contents[1].quality == "normal")
end
""")
        self.emulate()

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


# Stands in for Lua 5.2 (argv: emulator, mod root, preset): the base's emulation records its process
# and runs for minutes; the working tree's fails once the base's is running.
FAKE_LUA = '''#!{python}
import os, sys, time
from pathlib import Path
running = Path({running!r})
if sys.argv[2] == {root!r}:
    for _ in range(1000):
        if running.exists():
            break
        time.sleep(0.01)
    sys.exit('the working tree broke')
running.with_suffix('.tmp').write_text(str(os.getpid()))
running.with_suffix('.tmp').rename(running)
time.sleep(300)
'''


class ComparisonTests(unittest.TestCase):
    def test_a_failing_working_tree_stops_the_base_emulation(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        running = Path(directory.name) / 'base.pid'
        lua = Path(directory.name) / 'lua'
        lua.write_text(FAKE_LUA.format(python=sys.executable, running=str(running), root=str(ROOT)))
        lua.chmod(0o755)
        self.addCleanup(self.kill_survivor, running)
        started = time.monotonic()
        result = subprocess.run([sys.executable, str(ROOT / 'tools/emulate_ups.py'), '--base', 'HEAD',
                                 '--lua', str(lua)], capture_output=True, text=True, timeout=60)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('the working tree broke', result.stderr)
        self.assertLess(time.monotonic() - started, 30)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(running.read_text()), 0)

    @staticmethod
    def kill_survivor(running):
        # Only a failed run leaves the base's process behind: it may also never have started, or be gone.
        with contextlib.suppress(FileNotFoundError, ProcessLookupError, ValueError):
            os.kill(int(running.read_text()), signal.SIGKILL)


if __name__ == '__main__':
    unittest.main()
