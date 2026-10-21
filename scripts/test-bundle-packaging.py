#!/usr/bin/env python3
"""Exercise packaging metadata/preflight in scratch; never build or launch an app.

ps/codesign are inert test doubles here. Actual delivered signatures are verified
separately by test-bundle-engine.py and the integration/release lane.
"""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BundlePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix='subler-packaging-', dir=Path.home() / '.hermes/cache/scratch')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / 'Subler Automation Local.app'
        (self.app / 'Contents').mkdir(parents=True)
        (self.app / 'Contents/Info.plist').write_bytes(
            (ROOT / 'Sources/SublerAutomation/Resources/Info.plist').read_bytes())
        tools = self.root / 'tools'
        tools.mkdir()
        for name in ('ps', 'codesign'):
            path = tools / name
            path.write_text('#!/bin/sh\nexit 0\n')
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'])
        self.engine = self.root / 'Subler Background.app'
        (self.engine / 'Contents/MacOS').mkdir(parents=True)
        (self.engine / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'local.sublerautomation.Subler',
            'SublerAutomationBackgroundProtocol': '2', 'LSBackgroundOnly': True,
            'CFBundleExecutable': 'FixtureEngine'}))
        self.executable = self.engine / 'Contents/MacOS/FixtureEngine'
        self.executable.write_text('#!/bin/sh\nexit 0\n')
        self.executable.chmod(0o755)

    def configure(self, *options):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/configure-app-bundle.py'),
                               '--app', str(self.app), *options], cwd=ROOT,
                              env=self.env, capture_output=True, text=True)

    def test_normal_package_retains_installed_default_and_services(self):
        result = self.configure()
        self.assertEqual(result.returncode, 0, result.stderr)
        info = plistlib.loads((self.app / 'Contents/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleIdentifier'], 'com.mathiasbunnens.SublerAutomation')
        self.assertNotIn('SublerAutomationEngine', info)
        self.assertNotIn('SublerAutomationBackgroundRelativePath', info)
        self.assertIn('NSServices', info)

    def test_local_package_embeds_selection_and_distinct_identity(self):
        result = self.configure('--local-engine')
        self.assertEqual(result.returncode, 0, result.stderr)
        info = plistlib.loads((self.app / 'Contents/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleIdentifier'], 'com.mathiasbunnens.SublerAutomation.Local')
        self.assertEqual(info['CFBundleDisplayName'], 'Subler Automation Local')
        self.assertEqual(info['SublerAutomationEngine'], 'background')
        self.assertEqual(info['SublerAutomationBackgroundRelativePath'], '../Subler Background.app')
        self.assertNotIn('NSServices', info)

    def test_preflight_rejects_unusable_engine_before_bundle_changes(self):
        before = (self.app / 'Contents/Info.plist').read_bytes()
        for state in ('not-executable', 'missing', 'directory'):
            with self.subTest(state=state):
                if state == 'not-executable':
                    self.executable.chmod(0o644)
                elif state == 'missing':
                    self.executable.unlink()
                else:
                    self.executable.mkdir()
                result = self.configure('--local-engine', '--check-only')
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('usable executable', result.stderr)
                self.assertEqual((self.app / 'Contents/Info.plist').read_bytes(), before)

    def test_embedded_package_is_self_contained_with_clean_name(self):
        result = self.configure('--embedded-engine', '--engine-source', str(self.engine))
        self.assertEqual(result.returncode, 0, result.stderr)
        info = plistlib.loads((self.app / 'Contents/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleDisplayName'], 'Subler Automation')
        self.assertEqual(info['CFBundleIdentifier'], 'com.mathiasbunnens.SublerAutomation.Local')
        self.assertEqual(info['SublerAutomationBackgroundRelativePath'], 'Contents/Helpers/Subler Background.app')
        nested = self.app / info['SublerAutomationBackgroundRelativePath']
        self.assertEqual((nested / 'Contents/MacOS/FixtureEngine').read_bytes(), self.executable.read_bytes())
        self.assertNotIn('NSServices', info)

    def test_preflight_refuses_running_nested_engine_without_mutation(self):
        tools = Path(self.env['PATH'].split(os.pathsep)[0])
        nested = self.app / 'Contents/Helpers/Subler Background.app/Contents/MacOS/Subler'
        (tools / 'ps').write_text('#!/bin/sh\nprintf "%s\\n" "' + str(nested) + '"\n')
        before = (self.app / 'Contents/Info.plist').read_bytes()
        result = self.configure('--embedded-engine', '--engine-source', str(self.engine), '--check-only')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('running', result.stderr)
        self.assertEqual((self.app / 'Contents/Info.plist').read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
