#!/usr/bin/env python3
"""Version source/UI contracts and optional real built-bundle consistency check."""
from pathlib import Path
import os
import plistlib
import unittest

ROOT = Path(__file__).resolve().parent.parent
PLIST = ROOT / 'Sources/SublerAutomation/Resources/Info.plist'


class VersionContracts(unittest.TestCase):
    def test_release_metadata(self):
        info = plistlib.loads(PLIST.read_bytes())
        self.assertEqual(info['CFBundleShortVersionString'], '1.0.1')
        self.assertGreater(int(info['CFBundleVersion']), 1)

    def test_shared_bundle_version_in_both_views(self):
        for name in ['MenuBarView', 'SettingsView']:
            source = (ROOT / f'Sources/SublerAutomation/Views/{name}.swift').read_text()
            self.assertIn('Text(AppVersion.current.label)', source)
            self.assertIn('.help(AppVersion.current.details)', source)
            self.assertNotIn('1.0.1', source)
        core = (ROOT / 'Sources/AutomationCore/AppVersion.swift').read_text()
        self.assertIn('Bundle.main.infoDictionary', core)
        build = (ROOT / 'build.sh').read_text()
        self.assertIn('cp Sources/SublerAutomation/Resources/Info.plist "$APP/Contents/Info.plist"', build)

    @unittest.skipUnless(os.environ.get('SUBLER_BUILD_APP'), 'Set SUBLER_BUILD_APP for packaged integration check')
    def test_built_bundle_matches_source_and_release_binary(self):
        import hashlib
        import shutil
        import subprocess
        import tempfile
        app = Path(os.environ['SUBLER_BUILD_APP'])
        self.assertEqual(plistlib.loads((app / 'Contents/Info.plist').read_bytes()), plistlib.loads(PLIST.read_bytes()))
        bin_path = subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=ROOT, text=True).strip()
        # Signing the bundle legitimately changes Mach-O signature bytes.
        # Compare unsigned copies, never modify either original executable.
        scratch = Path.home() / '.hermes/cache/scratch'
        with tempfile.TemporaryDirectory(prefix='subler-version-', dir=scratch) as temp:
            digests = []
            for index, binary in enumerate([Path(bin_path) / 'SublerAutomation', app / 'Contents/MacOS/SublerAutomation']):
                copy = Path(temp) / str(index)
                shutil.copy2(binary, copy)
                subprocess.run(['codesign', '--remove-signature', str(copy)], check=True)
                digests.append(hashlib.sha256(copy.read_bytes()).digest())
            self.assertEqual(*digests)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
