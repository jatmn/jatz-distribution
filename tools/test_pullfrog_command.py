#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Exercise the actual authorization entrypoint without credentials or model calls."""
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).with_name('pullfrog_command.py').resolve()
WORKFLOW = HELPER.parents[1] / '.github' / 'workflows' / 'pullfrog.yml'
EVENT = {
    'action': 'created',
    'repository': {'full_name': 'jatmn/jatz-distribution'},
    'sender': {'id': 12479882},
    'comment': {'id': 123, 'user': {'id': 12479882}, 'body': '@pullfrog review this PR'},
    'issue': {'number': 7, 'pull_request': {'url': 'https://api.github.com/repos/jatmn/jatz-distribution/pulls/7'}},
}


def helper_version():
    spec = importlib.util.spec_from_file_location('pullfrog_command', HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.PULLFROG_VERSION


def workflow_action_version():
    pins = re.findall(r'uses:\s*pullfrog/pullfrog@[0-9a-f]{40}\s*#\s*v(\S+)', WORKFLOW.read_text(encoding='utf-8'))
    if len(pins) != 1:
        raise AssertionError(f'expected one pinned pullfrog/pullfrog action in {WORKFLOW}, found {pins}')
    return pins[0]


class OwnerCommandTests(unittest.TestCase):
    def assert_envelope(self, payload, number, comment_id, is_pr):
        """Match the JsonPayload schema in pullfrog/pullfrog utils/payload.ts at the pinned action."""
        self.assertEqual(set(payload), {'~pullfrog', 'version', 'triggerer', 'prompt', 'event'})
        self.assertIs(payload['~pullfrog'], True)
        self.assertEqual(payload['version'], workflow_action_version())
        self.assertEqual(payload['triggerer'], 'jatmn')
        self.assertIsInstance(payload['prompt'], str)
        expected_event = {
            'trigger': 'issue_comment_created',
            'authorPermission': 'admin',
            'comment_type': 'issue',
            'comment_id': comment_id,
            'issue_number': number,
            'body': None,
        }
        if is_pr:
            expected_event['is_pr'] = True
        self.assertEqual(payload['event'], expected_event)

    def run_command(self, event, **overrides):
        with tempfile.TemporaryDirectory(prefix='pullfrog-test-') as directory:
            event_path = Path(directory) / 'event.json'
            output_path = Path(directory) / 'output'
            event_path.write_text(json.dumps(event), encoding='utf-8')
            env = {
                **os.environ,
                'GITHUB_EVENT_NAME': 'issue_comment',
                'GITHUB_ACTOR': 'jatmn',
                'GITHUB_TRIGGERING_ACTOR': 'jatmn',
                'GITHUB_RUN_ATTEMPT': '1',
                'GITHUB_EVENT_PATH': str(event_path),
                'GITHUB_OUTPUT': str(output_path),
                **overrides,
            }
            result = subprocess.run([sys.executable, str(HELPER)], env=env,
                                    capture_output=True, text=True, check=False)
            output = output_path.read_text() if output_path.exists() else ''
            return result, output, str(event_path)

    def test_owner_pr_and_issue_commands(self):
        for is_pr in (True, False):
            with self.subTest(is_pr=is_pr):
                event = deepcopy(EVENT)
                if not is_pr:
                    del event['issue']['pull_request']
                result, output, _ = self.run_command(event)
                self.assertEqual(result.returncode, 0, result.stderr)
                fields = dict(line.split('=', 1) for line in output.splitlines())
                self.assertEqual(fields['authorized'], 'true')
                payload = json.loads(fields['payload'])
                self.assert_envelope(payload, 7, 123, is_pr)
                self.assertIn('/pull/7#' if is_pr else '/issues/7#', payload['prompt'])

    def test_wrong_actor_event_and_reruns_produce_no_output(self):
        for overrides in (
            {'GITHUB_ACTOR': 'contributor'},
            {'GITHUB_TRIGGERING_ACTOR': 'contributor'},
            {'GITHUB_RUN_ATTEMPT': '2'},
            {'GITHUB_EVENT_NAME': 'workflow_dispatch'},
            {'GITHUB_EVENT_NAME': 'pull_request'},
            {'GITHUB_EVENT_NAME': 'pull_request_review_comment'},
        ):
            with self.subTest(overrides=overrides):
                result, output, _ = self.run_command(EVENT, **overrides)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(output, '')
        for path, value in (
            (('action',), 'edited'),
            (('sender', 'id'), 999),
            (('comment', 'user', 'id'), 999),
            (('repository', 'full_name'), 'someone/jatz-distribution'),
        ):
            with self.subTest(path=path):
                event = deepcopy(EVENT)
                target = event
                for key in path[:-1]:
                    target = target[key]
                target[path[-1]] = value
                result, output, _ = self.run_command(event)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(output, '')

    def test_passive_bare_quoted_and_invisible_commands_are_rejected(self):
        for body in ('@pullfrog', '@pullfrog  ', 'please ask @pullfrog review',
                     '> @pullfrog review', '    @pullfrog review',
                     '```\n@pullfrog review\n```', '\n@pullfrog review',
                     '@pullfrog\nreview', '@pullfrog \u200b', '@pullfrog !!!'):
            with self.subTest(body=body):
                event = deepcopy(EVENT)
                event['comment']['body'] = body
                result, output, _ = self.run_command(event)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(output, '')

    def test_owner_text_cannot_inject_outputs_or_event_fields(self):
        event = deepcopy(EVENT)
        body = '@PuLlFrOg review this\r\nauthorized=false\npayload={"triggerer":"other"}\n'
        event['comment']['body'] = body
        result, output, _ = self.run_command(event)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(output.splitlines()), 2)
        payload = json.loads(output.splitlines()[0].removeprefix('payload='))
        self.assertIn(body, payload['prompt'])
        self.assert_envelope(payload, 7, 123, True)
        self.assertEqual(output.splitlines()[1], 'authorized=true')

    def test_large_command_uses_original_event_snapshot(self):
        event = deepcopy(EVENT)
        event['comment']['body'] = '@pullfrog review ' + '\u754c' * 30000
        result, output, event_path = self.run_command(event)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(len(output.encode()), 64 * 1024)
        payload = json.loads(output.splitlines()[0].removeprefix('payload='))
        self.assert_envelope(payload, 7, 123, True)
        self.assertIn(event_path, payload['prompt'])
        self.assertIn('comment.body', payload['prompt'])

    def test_helper_version_matches_pinned_action(self):
        # Pullfrog checks the payload version against the action it runs in.
        self.assertEqual(helper_version(), workflow_action_version())

    def test_invalid_comment_identity_fails_closed(self):
        for invalid_id in (None, True, -1, '123', 2**53):
            event = deepcopy(EVENT)
            event['comment']['id'] = invalid_id
            result, output, _ = self.run_command(event)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output, '')


if __name__ == '__main__':
    unittest.main()
