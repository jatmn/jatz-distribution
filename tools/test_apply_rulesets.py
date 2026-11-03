#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Exercise apply_rulesets.py against a fake gh that keeps rulesets in a JSON file; GitHub isn't contacted."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

SCRIPT = Path(__file__).with_name('apply_rulesets.py').resolve()
FAKE_GH = textwrap.dedent('''\
    #!/usr/bin/env python3
    import json, os, sys
    state_path = os.environ['FAKE_GH_STATE']
    state = json.load(open(state_path))
    args = sys.argv[2:]  # after "api"
    method = args[args.index('-X') + 1] if '-X' in args else 'GET'
    url = next(arg for arg in args if arg.startswith('repos/'))
    def save():
        json.dump(state, open(state_path, 'w'))
    def create(name):
        state['next'] += 1
        state['rulesets'].append({'id': state['next'], 'name': name, 'body': None})
    if os.environ.get('FAKE_GH_FAIL_LIST') and method == 'GET':
        sys.exit('HTTP 502')
    if method == 'GET':
        for ruleset in state['rulesets']:
            print(json.dumps({'id': ruleset['id'], 'name': ruleset['name']}))
    elif method == 'POST':
        name = json.load(open(args[args.index('--input') + 1]))['name']
        create(name)
        if os.environ.get('FAKE_GH_RACE'):  # another operator creates the same ruleset
            create(name)
        save()
    elif method in ('PUT', 'DELETE'):
        ruleset_id = int(url.rsplit('/', 1)[1])
        match = [ruleset for ruleset in state['rulesets'] if ruleset['id'] == ruleset_id]
        if not match:
            sys.exit('HTTP 404: Not Found')
        if method == 'DELETE':
            state['rulesets'].remove(match[0])
        else:
            match[0]['body'] = json.load(open(args[args.index('--input') + 1]))
        save()
''')


class ApplyRulesetsTests(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix='jatz-rulesets-'))
        self.addCleanup(shutil.rmtree, self.directory)
        fake = self.directory / 'gh'
        fake.write_text(FAKE_GH)
        fake.chmod(0o755)
        self.state = self.directory / 'state.json'

    def run_script(self, rulesets=(), **env):
        self.state.write_text(json.dumps({'next': 100, 'rulesets': [
            {'id': ruleset_id, 'name': name, 'body': None} for ruleset_id, name in rulesets]}))
        result = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True, env={
            **os.environ, 'PATH': f'{self.directory}{os.pathsep}{os.environ["PATH"]}',
            'FAKE_GH_STATE': str(self.state), **env})
        return result, json.loads(self.state.read_text())['rulesets']

    def named(self, rulesets):
        return {ruleset['name']: ruleset for ruleset in rulesets}

    def test_creates_missing_rulesets_with_the_file_contents(self):
        result, rulesets = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        named = self.named(rulesets)
        self.assertEqual(set(named), {'Main branch protection', 'Require CI'})
        self.assertEqual(len(rulesets), 2)
        self.assertEqual(named['Require CI']['body']['rules'][0]['type'], 'required_status_checks')

    def test_updates_existing_rulesets_in_place(self):
        result, rulesets = self.run_script([(7, 'Main branch protection'), (9, 'Require CI'), (3, 'Unrelated')])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(ruleset['id'] for ruleset in rulesets), [3, 7, 9])
        self.assertIsNone(self.named(rulesets)['Unrelated']['body'])
        self.assertEqual(self.named(rulesets)['Main branch protection']['body']['name'], 'Main branch protection')

    def test_concurrent_creation_converges_on_the_oldest(self):
        result, rulesets = self.run_script(FAKE_GH_RACE='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(rulesets), 2)  # one per name, the duplicates removed
        self.assertEqual({ruleset['id'] for ruleset in rulesets}, {101, 103})

    def test_existing_duplicates_keep_the_lowest_id(self):
        result, rulesets = self.run_script([(12, 'Require CI'), (5, 'Require CI'), (8, 'Main branch protection')])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(ruleset['id'] for ruleset in rulesets), [5, 8])

    def test_failed_lookup_changes_nothing(self):
        result, rulesets = self.run_script([(7, 'Main branch protection')], FAKE_GH_FAIL_LIST='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not applied', result.stderr)
        self.assertEqual(rulesets, [{'id': 7, 'name': 'Main branch protection', 'body': None}])


if __name__ == '__main__':
    unittest.main()
