#!/usr/bin/env python3
"""Run the real SwiftUI views in a separately signed, isolated native app."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import sys

layout_only = '--layout-only' in sys.argv

project = Path(__file__).resolve().parent.parent
# This separate real App/Scene test owns native MenuBarExtra autosizing assertions.
# The NSWindow host checks below explicitly resize their host and cannot prove that.
subprocess.run([sys.executable, str(project / 'scripts/menu-popup-layout.py')], check=True)
scratch = Path.home() / '.hermes/cache/scratch'
scratch.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='subler-ui-layout-', dir=scratch))
source = root / 'Sources/UISmoke'
source.mkdir(parents=True)
files = [project / 'scripts/ui-layout-smoke.swift']
for folder in ['Views', 'Models', 'Services']:
    files.extend((project / 'Sources/SublerAutomation' / folder).glob('*.swift'))
for file in files:
    (source / file.name).symlink_to(file)
(root / 'Package.swift').write_text('// swift-tools-version: 5.9\nimport PackageDescription\n'
    'let package = Package(name: "SublerUISmoke", platforms: [.macOS(.v14)], '
    'dependencies: [.package(path: ' + json.dumps(str(project)) + ')], '
    'targets: [.executableTarget(name: "UISmoke", dependencies: '
    '[.product(name: "AutomationCore", package: "sublerautomation")])])\n')
env = dict(os.environ, TMPDIR=str(scratch))

def run(*args):
    result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout.strip()

run('swift', 'build', '--package-path', str(root))
# The bin path differs between Swift build systems; never hardcode .build/debug.
bin_path = Path(run('swift', 'build', '--package-path', str(root), '--show-bin-path'))
app = root / 'UISmoke.app'
macos = app / 'Contents/MacOS'
macos.mkdir(parents=True)
shutil.copy2(bin_path / 'UISmoke', macos / 'UISmoke')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.sublerautomation.ui-smoke',
    'CFBundleExecutable': 'UISmoke', 'CFBundleName': 'Subler UI Smoke',
    'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'NSPrincipalClass': 'NSApplication',
}))
run('codesign', '--force', '--sign', '-', str(app))
output, error = root / 'output.log', root / 'error.log'
# LaunchServices activation is required for a meaningful foreground-window test.
# A CLI process alone can remain inactive despite activateIgnoringOtherApps.
run('open', '-n', '-W', '--stdout', str(output), '--stderr', str(error),
    '--env', 'SUBLER_AUTOMATION_TEST_ROOT=' + str(root / 'state'),
    '--env', 'SUBLER_UI_LAYOUT_ONLY=' + ('1' if layout_only else '0'), str(app))
stdout = output.read_text() if output.exists() else ''
stderr = error.read_text() if error.exists() else ''
marker = 'UI_LAYOUT_ONLY_PASS:' if layout_only else 'UI_LAYOUT_SMOKE_PASS:'
if marker not in stdout or 'Precondition failed' in stderr:
    raise RuntimeError(f'Native UI smoke failed; evidence: {root}\n{stdout}\n{stderr}')
print(stdout.strip())
print(f'Isolated native UI evidence: {root}')
