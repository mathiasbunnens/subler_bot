#!/usr/bin/env python3
"""Direct swiftc + LaunchServices native fixture; no project .build or live data."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import sys

focus_only = '--focus-only' in sys.argv
project = Path(__file__).resolve().parent.parent
scratch = Path.home() / '.hermes/cache/scratch'
scratch.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='subler-presentation-ui-', dir=scratch))
env = dict(os.environ, TMPDIR=str(scratch))

def run(args):
    result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout

run(['swiftc', '-emit-library', '-emit-module', '-module-name', 'AutomationCore',
     *map(str, (project / 'Sources/AutomationCore').glob('*.swift')),
     '-emit-module-path', str(root / 'AutomationCore.swiftmodule'), '-o', str(root / 'libAutomationCore.dylib')])
files = [project / 'scripts/presentation-ui-smoke.swift']
for folder in ['Views', 'Models', 'Services']:
    files.extend((project / 'Sources/SublerAutomation' / folder).glob('*.swift'))
if focus_only:
    files = [file for file in files if file.name not in ['MenuBarView.swift', 'AppPresentationController.swift', 'MenuBarStatusLabel.swift']]
run(['swiftc', '-parse-as-library', *(['-D', 'FOCUS_ONLY'] if focus_only else []), '-I', str(root), '-L', str(root), '-lAutomationCore',
     '-Xlinker', '-rpath', '-Xlinker', str(root), *map(str, files), '-o', str(root / 'UISmoke')])
# Typecheck the actual App entry point as well, without linking or launching it.
app_sources = list((project / 'Sources/SublerAutomation/App').glob('*.swift'))
if not focus_only:
    run(['swiftc', '-typecheck', '-I', str(root), *map(str, files[1:] + app_sources)])
app = root / 'PresentationSmoke.app'
macos = app / 'Contents/MacOS'
macos.mkdir(parents=True)
shutil.copy2(root / 'UISmoke', macos / 'UISmoke')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.sublerautomation.presentation-smoke',
    'CFBundleExecutable': 'UISmoke', 'CFBundleName': 'Presentation Smoke',
    'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'NSPrincipalClass': 'NSApplication',
}))
run(['codesign', '--force', '--sign', '-', str(app)])
output, error = root / 'output.log', root / 'error.log'
run(['open', '-n', '-W', '--stdout', str(output), '--stderr', str(error),
     '--env', 'SUBLER_AUTOMATION_TEST_ROOT=' + str(root / 'state'), str(app)])
stdout = output.read_text() if output.exists() else ''
stderr = error.read_text() if error.exists() else ''
print(stdout)
print('Evidence:', root)
if 'PRESENTATION_UI_PASS:' not in stdout or 'Precondition failed' in stderr:
    raise RuntimeError(stderr or 'Missing success marker')
