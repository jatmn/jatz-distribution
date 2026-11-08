#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Regressions for CI area routing and file selection; no game, Blender or dependency mods are loaded."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

from ci_changes import classify
from release_metadata import PENDING, SEPARATOR, finalize, package_metadata

ROUTER = Path(__file__).with_name('ci_changes.py').resolve()
REPO = ROUTER.parents[1]
WORKFLOWS = REPO / '.github/workflows'
KEYS = ('freighter', 'freighter_art', 'depots', 'depots_art', 'mod', 'repository')
NO_COMMIT = '0' * 40


def workflow_block(workflow, name):
    """The shell script of a named step; the step must appear exactly once."""
    text = (WORKFLOWS / workflow).read_text()
    steps = [re.split(r'\n(?=      - |  \S)', step, maxsplit=1)[0]
             for step in text.split(f'      - name: {name}\n')[1:]]
    if len(steps) != 1:
        raise AssertionError(f'{workflow}: expected one {name!r} step, found {len(steps)}')
    lines = []
    for line in steps[0].split('        run: |\n', 1)[1].splitlines():
        if line.strip() and not line.startswith('          '):
            break
        lines.append(line)
    return textwrap.dedent('\n'.join(lines))


class Repo:
    """A throwaway Git repository for exercising routing and selection."""

    def __init__(self, test):
        self.root = Path(tempfile.mkdtemp(prefix='jatz-ci-'))
        test.addCleanup(shutil.rmtree, self.root)
        self.git('init', '-q')

    def git(self, *args):
        return subprocess.check_output([
            'git', '-c', 'user.name=CI test', '-c', 'user.email=ci@example.invalid', *args
        ], cwd=self.root, text=True).strip()

    def write(self, name, text='return true\n'):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def commit(self, message='change'):
        self.git('add', '-A')
        self.git('commit', '--allow-empty', '-qm', message)
        return self.git('rev-parse', 'HEAD')

    def route(self, base):
        result = subprocess.check_output([sys.executable, str(ROUTER), '--base', base], cwd=self.root, text=True)
        return {line.split('=')[0] for line in result.splitlines() if line.endswith('=true')}

    def select(self, area, base, event):
        subprocess.run([sys.executable, str(ROUTER), '--select', area, '--base', base, '--event', event,
                        '--output', '.cache'], cwd=self.root, check=True)
        return {kind: set(filter(None, (self.root / f'.cache/ci-{kind}-files').read_bytes().split(b'\0')))
                for kind in ('lua', 'py')}

    def run_step(self, command, **env):
        scratch = self.root / '.scratch'
        scratch.mkdir(exist_ok=True)
        output = scratch / 'outputs'
        output.unlink(missing_ok=True)
        result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', command], cwd=self.root,
                                capture_output=True, text=True,
                                env={**os.environ, 'GITHUB_OUTPUT': str(output), 'RUNNER_TEMP': str(scratch), **env})
        return result, (set(output.read_text().splitlines()) if output.exists() else set())


class RoutingTests(unittest.TestCase):
    route_step = workflow_block('ci.yml', 'Route the complete Git diff')

    def test_dispatcher_does_not_execute_changed_router(self):
        for has_base_router in (True, False):
            with self.subTest(has_base_router=has_base_router):
                repo = Repo(self)
                if has_base_router:
                    (repo.root / 'tools').mkdir()
                    shutil.copy(ROUTER, repo.root / 'tools/ci_changes.py')
                base = repo.commit('base')
                repo.write('tools/ci_changes.py', 'print("\\n".join(k + "=false" for k in %r))\n' % (KEYS,))
                repo.write('control.lua', 'return (\n')
                repo.commit('broken Lua with disabled router')
                result, outputs = repo.run_step(self.route_step, BASE=base)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(outputs, {f'{key}=true' for key in KEYS})

    def test_base_router_without_newer_checks_runs_them(self):
        repo = Repo(self)
        repo.write('tools/ci_changes.py', 'print("freighter=false\\nmod=false")\n')
        base = repo.commit('older router')
        repo.write('docs/notes.md', 'notes\n')
        repo.commit('docs')
        result, outputs = repo.run_step(self.route_step, BASE=base)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs, {'freighter=false', 'mod=false'} | {
            f'{key}=true' for key in KEYS if key not in ('freighter', 'mod')})

    def test_push_creating_the_branch_checks_everything(self):
        repo = Repo(self)
        repo.write('control.lua')
        repo.commit('first commit')
        result, outputs = repo.run_step(self.route_step, BASE=NO_COMMIT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs, {f'{key}=true' for key in KEYS})
        # The whole tree is checked for whitespace errors.
        repo.write('notes.txt', 'trailing space \n')
        repo.commit('whitespace error')
        result, _ = repo.run_step(self.route_step, BASE=NO_COMMIT)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('trailing whitespace', result.stdout + result.stderr)

    def test_text_size_guard_matches_the_clone_filter(self):
        # Git's blob:limit omits blobs of *at least* the limit, so the guard must reject that size too.
        self.assertEqual(re.findall(r'filter: (blob:limit=\S+)', (WORKFLOWS / 'ci.yml').read_text()),
                         ['blob:limit=256k'])
        self.assertIn('st_size >= 256 * 1024', self.route_step)
        for size, accepted in ((256 * 1024 - 1, True), (256 * 1024, False)):
            with self.subTest(size=size):
                repo = Repo(self)
                base = repo.commit('base')
                repo.write('assets/depots/previews/viewer.html', 'x' * size)
                repo.commit('text at the boundary')
                result, _ = repo.run_step(self.route_step, BASE=base)
                self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)
                if not accepted:
                    self.assertIn('viewer.html is text of 256 KiB or more', result.stdout)

    def test_large_text_must_be_marked_binary(self):
        repo = Repo(self)
        base = repo.commit('base')
        repo.write('assets/depots/previews/viewer.html', 'x' * (256 * 1024 + 1))
        repo.commit('large text')
        result, _ = repo.run_step(self.route_step, BASE=base)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('viewer.html is text of 256 KiB or more', result.stdout)
        repo.write('.gitattributes', 'assets/*/previews/*.html binary\n')
        repo.commit('mark it binary')
        result, _ = repo.run_step(self.route_step, BASE=base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_binary_files_are_not_whitespace_checked(self):
        repo = Repo(self)
        repo.write('.gitattributes', '*.png binary\n')
        base = repo.commit('base')
        repo.write('image.png', 'not really an image \n')
        repo.commit('binary with trailing whitespace')
        result, _ = repo.run_step(self.route_step, BASE=base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_verbatim_third_party_files_can_opt_out_of_whitespace_checks(self):
        # Third-party files kept exactly as published (assets/roads/yuoki-railways/) may end in a
        # blank line; marking them -whitespace skips the check, and only for them.
        repo = Repo(self)
        repo.write('.gitattributes', 'vendor/** -whitespace\n')
        base = repo.commit('base')
        repo.write('vendor/Licence.txt', 'upstream text\n\n')
        repo.commit('verbatim upstream file')
        result, _ = repo.run_step(self.route_step, BASE=base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        repo.write('ours.txt', 'our text\n\n')
        repo.commit('our file with the same problem')
        result, _ = repo.run_step(self.route_step, BASE=base)
        self.assertNotEqual(result.returncode, 0, 'whitespace errors outside the exempt folder must still fail')

    def test_area_selection(self):
        cases = [
            (['assets/quinityn-freighter/factorio/freighter-animation.lua'], {'freighter', 'mod'}),
            (['tools/test_factorio.py', 'tools/prepare_test_mod.py',
              'tests/factorio/freighter-art-check_0.1.0/control.lua'], {'freighter'}),
            # The art jobs exercise the sprite extractor, so changing it runs the freighter art checks.
            (['assets/quinityn-freighter/tools/package_sprites.py'], {'freighter', 'freighter_art'}),
            (['assets/quinityn-freighter/source/quinityn-freighter.blend'], {'freighter', 'freighter_art'}),
            (['assets/quinityn-freighter/sheets/freighter-base.png',
              'assets/quinityn-freighter/checksums.json'], {'freighter', 'freighter_art'}),
            (['assets/quinityn-freighter/README.md'], {'freighter'}),
            (['assets/depots/factorio/depot-pictures.lua'], {'depots', 'mod'}),
            (['assets/depots/tools/depot_lua.py', 'tools/test_depot_art.py', 'tools/test_depot_lua.py'], {'depots'}),
            # The marking's drawing script is its source, so changing it runs the depot art checks.
            (['assets/depots/tools/make_loading_zone.py'], {'depots', 'depots_art'}),
            (['assets/depots/loading-zone/loading-zone.png', 'assets/depots/loading-zone/loading-zone.json'],
             {'depots', 'depots_art'}),
            (['prototypes/orientation.lua'], {'mod'}),
            (['assets/depots/source/fuel-3.blend'], {'depots', 'depots_art'}),
            (['assets/depots/fuel/3/asset.json', 'assets/depots/geometry-validation.json'], {'depots', 'depots_art'}),
            (['assets/depots/tools/render_connector.py'], {'depots', 'depots_art'}),
            # Every wreck records the builder and renderer that made it: changing either runs both art checks.
            (['assets/depots/tools/build_remnants.py'], {'depots', 'depots_art', 'freighter', 'freighter_art'}),
            (['assets/quinityn-freighter/tools/render_directions.py'],
             {'depots', 'depots_art', 'freighter', 'freighter_art'}),
            (['assets/depots/remnants/fuel/sheets/base.png'], {'depots', 'depots_art'}),
            (['assets/quinityn-freighter/remnants/freighter/asset.json'], {'freighter', 'freighter_art'}),
            (['assets/depots/archive/1x1/README.md'], {'depots', 'depots_art'}),
            (['info.json', 'data.lua', 'control.lua', 'prototypes/freighter.lua',
              'scripts/dispatch.lua', 'locale/en/jatz.cfg'], {'mod'}),
            (['tools/package_mod.py', 'tools/test_mod.py', 'tools/test_mod_setup.py',
              'tests/factorio/jatz-distribution-check_0.1.0/control.lua'], {'mod'}),
            # The UPS benchmark, its map and the engine-free emulator the UPS benchmark check runs.
            (['tools/benchmark_ups.py', 'tools/emulate_ups.py', 'tools/test_emulate_ups.py',
              'tests/factorio/ups-benchmark_0.1.0/layout.lua', 'tests/lua/ups-emulator.lua'], {'mod'}),
            (['.github/workflows/pullfrog.yml', 'tools/pullfrog_command.py',
              'tools/test_pullfrog_command.py', '.github/CODEOWNERS', '.github/main-ruleset.json'], {'repository'}),
            (['tools/check_blender_sources.py'], {'repository', 'freighter', 'freighter_art', 'depots', 'depots_art',
                                                  'mod'}),
            (['tools/make_icons.py'], {'repository', 'freighter', 'freighter_art', 'depots', 'depots_art'}),
            (['assets/depots/icons/fuel-depot.png', 'assets/depots/icons/icons.json'], {'depots', 'depots_art'}),
            (['assets/quinityn-freighter/icons/quinityn-freighter.png'], {'freighter', 'freighter_art'}),
            # The art job redraws the thumbnail from the freighter's sprites; the package job then runs too.
            (['thumbnail.png'], {'freighter', 'freighter_art'}),
            (['tools/test_check_blender_sources.py', 'tools/test_ci_changes.py'], {'repository'}),
            # The Mod Portal page: the release syncs it, and the package job checks it.
            (['portal/description.md', 'portal/summary.txt', 'portal/gallery/01-depots.png'], {'repository'}),
            (['README.md', 'AGENTS.md', 'CONTRIBUTING.md', 'SECURITY.md', 'NOTICE', 'COPYING', 'COPYING.LESSER',
              '.gitignore', 'docs/testing.md', 'docs/images/x.jpg', 'concepts/depots/images/fuel.png'], set()),
            (['.luacheckrc'], {'freighter', 'depots', 'mod', 'repository'}),
            (['.stylua.toml', '.ruff.toml', '.gitattributes'], {'freighter', 'depots', 'mod', 'repository'}),
            (['requirements.txt'], {'freighter', 'freighter_art', 'depots', 'depots_art', 'repository'}),
            (['tools/test_art_dependencies.py'], {'freighter', 'freighter_art', 'depots', 'depots_art', 'repository'}),
            (['.github/workflows/ci.yml'], set(KEYS)),
            (['.github/workflows/area.yml'], set(KEYS)),
            (['tools/ci_changes.py'], set(KEYS)),
            (['control.lua', 'assets/depots/source/fuel-3.blend'], {'mod', 'depots', 'depots_art'}),
            ([], set()),
        ]
        for paths, expected in cases:
            with self.subTest(paths=paths):
                self.assertEqual({name for name, enabled in classify(paths).items() if enabled}, expected)

    def test_complete_git_diff_and_path_changes(self):
        repo = Repo(self)
        base = repo.commit('base')
        for index in range(3500):
            repo.write(f'docs/{index:04}.md', 'documentation\n')
        repo.commit('large docs-only change')
        self.assertEqual(repo.route(base), set())
        lua = repo.write('assets/depots/late file\nwith whitespace.lua')
        repo.commit('Lua beyond the filtered file-list cap')
        self.assertEqual(repo.route(base), {'depots'})
        previous = repo.git('rev-parse', 'HEAD')
        (repo.root / 'tools').mkdir()
        repo.git('mv', str(lua.relative_to(repo.root)), 'tools/renamed.py')
        repo.commit('cross-area rename')
        self.assertEqual(repo.route(previous), {'depots', 'repository'})
        previous = repo.git('rev-parse', 'HEAD')
        repo.git('rm', '-q', 'tools/renamed.py')
        repo.commit('delete')
        self.assertEqual(repo.route(previous), {'repository'})
        failed = subprocess.run([sys.executable, str(ROUTER), '--base', 'missing-revision'],
                                cwd=repo.root, capture_output=True, text=True)
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(failed.stdout, '')


class ReleaseNotesHoldTests(unittest.TestCase):
    hold_step = workflow_block('ci.yml', 'Hold the package check for the release notes')

    def test_only_release_pleases_unfinalized_commit_skips_the_package_check(self):
        history = SEPARATOR + 'Version: 0.1.0\nDate: 2026-11-04\n  Info:\n    - First release.\n'
        release = {'info.json': '{"name": "jatz-distribution", "version": "0.1.1"}\n', '.github/version.txt': '0.1.1\n',
                   '.github/release-please-manifest.json': '{".": "0.1.1"}\n', 'docs/CHANGELOG.md': '# Changelog\n'}
        # With pending player notes, and without any: the finalizer then adds "No player-facing changes."
        for notes in (PENDING + '  Bugfixes:\n    - Keep delivered cargo.\n', ''):
            for scenario, changes, finalized, expected in (
                ('Release Please bumped the version', release, False, True),
                ('notes finalized', release, True, False),
                ('code changed too', {**release, 'control.lua': 'return false\n'}, False, False),
                ('version not raised', {'docs/CHANGELOG.md': '# Changelog\n'}, False, False),
                ('info.json changed, same version', {'info.json': '{"name": "jatz-distribution", "version": "0.1.0",'
                                                     ' "title": "Changed"}\n'}, False, False),
                ('no change', {}, False, False),
            ):
                with self.subTest(notes=bool(notes), scenario=scenario):
                    repo = Repo(self)
                    repo.write('info.json', '{"name": "jatz-distribution", "version": "0.1.0"}\n')
                    repo.write('.github/version.txt', '0.1.0\n')
                    repo.write('.github/release-please-manifest.json', '{".": "0.1.0"}\n')
                    repo.write('changelog.txt', notes + history)
                    repo.write('control.lua')
                    base = repo.commit('base')
                    for name, text in changes.items():
                        repo.write(name, text)
                    if finalized:
                        # What the Release workflow's finalizing commit writes.
                        finalize(repo.root, '2026-11-06')
                        self.assertTrue((repo.root / 'changelog.txt').read_text().startswith(
                            SEPARATOR + 'Version: 0.1.1\n'))
                    repo.commit('release')
                    result, outputs = repo.run_step(self.hold_step, BASE=base)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(outputs, {f'release_pending={str(expected).lower()}'})
                    self.assertEqual('Skipping the installable package check' in result.stdout, expected)
                    if not finalized and expected:
                        # The package check really can't pass on the held commit.
                        with self.assertRaisesRegex(ValueError, 'top version'):
                            package_metadata(repo.root)

    def test_package_job_waits_only_on_the_hold(self):
        workflow = (WORKFLOWS / 'ci.yml').read_text()
        hold = workflow.split('      - name: Hold the package check for the release notes\n')[1].split('        run: |')[0]
        self.assertIn("github.head_ref == 'release-please--branches--main'", hold)
        self.assertIn('github.event.pull_request.head.repo.full_name == github.repository', hold)
        package = workflow.split('\n  package:\n')[1].split('\n    runs-on:')[0]
        self.assertIn("needs.changes.outputs.release_pending != 'true' && (", package)


class SelectionTests(unittest.TestCase):
    def test_pull_requests_lint_changed_lua_and_pushes_lint_all(self):
        repo = Repo(self)
        for name in ('untouched.lua', 'deleted.lua', 'old.lua', 'assets/depots/other-area.lua', 'tool.py'):
            repo.write(name)
        base = repo.commit('base')
        unusual = 'new file\nwith $shell; characters.lua'
        repo.git('mv', 'old.lua', unusual)
        repo.git('rm', '-q', 'deleted.lua')
        repo.write('-added.lua', 'return false\n')
        repo.write('assets/depots/changed.lua')
        repo.write('untracked.lua')
        repo.git('add', '--', '-added.lua', 'assets/depots/changed.lua')
        repo.git('commit', '-qm', 'rename, delete and add')
        self.assertEqual(repo.select('mod', base, 'pull_request'),
                         {'lua': {os.fsencode(unusual), b'-added.lua'}, 'py': {b'tool.py'}})
        self.assertEqual(repo.select('mod', base, 'push')['lua'],
                         {os.fsencode(unusual), b'-added.lua', b'untouched.lua'})
        # Another area's files are never selected for this one.
        self.assertEqual(repo.select('depots', base, 'pull_request')['lua'], {b'assets/depots/changed.lua'})
        for event in ('pull_request', 'push'):
            failed = subprocess.run([sys.executable, str(ROUTER), '--select', 'mod', '--base', 'missing-revision',
                                     '--event', event, '--output', '.cache'], cwd=repo.root, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)

    def test_lint_configuration_changes_lint_everything(self):
        for config in ('.luacheckrc', '.stylua.toml', '.ruff.toml', '.gitattributes',
                       '.github/workflows/area.yml', 'tools/ci_changes.py'):
            with self.subTest(config=config):
                repo = Repo(self)
                repo.write('untouched.lua')
                base = repo.commit('base')
                repo.write(config, '# configuration\n')
                repo.commit('configuration')
                self.assertEqual(repo.select('mod', base, 'pull_request')['lua'], {b'untouched.lua'})

    def test_push_creating_the_branch_lints_everything(self):
        repo = Repo(self)
        repo.write('control.lua')
        repo.commit('first commit')
        self.assertEqual(repo.select('mod', NO_COMMIT, 'push')['lua'], {b'control.lua'})

    def test_lua_type_changes_are_selected(self):
        for starts_as_symlink in (False, True):
            with self.subTest(starts_as_symlink=starts_as_symlink):
                repo = Repo(self)
                repo.write('docs/source')
                repo.write('untouched.lua')
                lua = repo.root / 'control.lua'
                if starts_as_symlink:
                    lua.symlink_to('docs/source')
                else:
                    lua.write_text('return true\n')
                base = repo.commit('base')
                lua.unlink()
                if starts_as_symlink:
                    lua.write_text('invalid Lua source\n')
                else:
                    lua.symlink_to('docs/source')
                    repo.write('docs/source', 'invalid Lua source\n')
                repo.commit('change Lua file type')
                self.assertIn('T\tcontrol.lua', repo.git('diff', '--name-status', base, 'HEAD').splitlines())
                self.assertIn('mod', repo.route(base))
                self.assertEqual(repo.select('mod', base, 'pull_request')['lua'], {b'control.lua'})
                self.assertEqual(repo.select('mod', base, 'push')['lua'], {b'control.lua', b'untouched.lua'})

    def test_area_workflow_reports_what_to_check(self):
        command = workflow_block('area.yml', "Select this area's files")
        repo = Repo(self)
        tools = repo.root / 'tools'
        tools.mkdir()
        shutil.copy(ROUTER, tools / 'ci_changes.py')
        repo.write('control.lua')
        base = repo.commit('base')
        repo.write('control.lua', 'return false\n')
        repo.commit('mod change')
        for area, expected in (('mod', {'lua=true', 'py=false'}), ('repository', {'lua=false', 'py=true'}),
                               ('depots', {'lua=false', 'py=false'})):
            with self.subTest(area=area):
                result, outputs = repo.run_step(command, AREA=area, BASE=base, EVENT_NAME='pull_request')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(outputs, expected)

    @unittest.skipUnless(shutil.which('luac5.2'), 'the area workflow installs the Lua 5.2 compiler')
    def test_lua_syntax_check_handles_option_like_names(self):
        repo = Repo(self)
        shutil.copy(REPO / '.luacheckrc', repo.root / '.luacheckrc')
        base = repo.commit('base')
        repo.write('-generated.lua')
        repo.commit('option-like Lua name')
        repo.select('mod', base, 'pull_request')
        result, _ = repo.run_step(workflow_block('area.yml', 'Check Lua syntax'))
        self.assertEqual(result.returncode, 0, result.stderr)


class CheckoutTests(unittest.TestCase):
    def test_text_only_checkouts_exclude_exactly_the_binary_files(self):
        binary = {line.split()[0] for line in (REPO / '.gitattributes').read_text().splitlines()
                  if line.strip() and not line.startswith('#') and 'binary' in line.split()[1:]}
        self.assertTrue(binary)
        expected = {'/*'} | {f'!{pattern}' for pattern in binary}
        blocks = []
        for workflow in ('ci.yml', 'area.yml'):
            text = (WORKFLOWS / workflow).read_text()
            for match in re.finditer(r'sparse-checkout-cone-mode: false\n\s+sparse-checkout: \|\n((?:\s{12}\S.*\n)+)',
                                     text):
                blocks.append((workflow, {line.strip() for line in match.group(1).splitlines()}))
        self.assertEqual([name for name, _ in blocks], ['ci.yml', 'area.yml'])
        for workflow, patterns in blocks:
            with self.subTest(workflow=workflow):
                self.assertEqual(patterns, expected)


if __name__ == '__main__':
    unittest.main()
