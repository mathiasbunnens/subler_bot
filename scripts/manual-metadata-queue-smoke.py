#!/usr/bin/env python3
"""Run only the manual-metadata queue smoke in a signed, owned scratch application.
Invoke under the shared native-lock.py. No production launch or native Subler calls.
"""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

project = Path(__file__).resolve().parent.parent
scratch = Path.home() / '.hermes/cache/scratch'
scratch.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='manual-metadata-queue-', dir=scratch))
print('Evidence:', root, flush=True)
env = dict(os.environ, TMPDIR=str(scratch))
def run(args):
    result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout
run(['swiftc', '-emit-library', '-emit-module', '-module-name', 'AutomationCore',
     *map(str, (project / 'Sources/AutomationCore').glob('*.swift')),
     '-emit-module-path', str(root / 'AutomationCore.swiftmodule'), '-o', str(root / 'libAutomationCore.dylib')])
files = [project / 'scripts/manual-metadata-queue-smoke.swift', project / 'scripts/harness-check.swift']
for folder in ['Views', 'Models', 'Services']:
    files.extend((project / 'Sources/SublerAutomation' / folder).glob('*.swift'))
run(['swiftc', '-parse-as-library', '-I', str(root), '-L', str(root), '-lAutomationCore',
     '-Xlinker', '-rpath', '-Xlinker', str(root), *map(str, files), '-o', str(root / 'ManualMetadataSmoke')])
app = root / 'ManualMetadataSmoke.app'
macos = app / 'Contents/MacOS'
macos.mkdir(parents=True)
shutil.copy2(root / 'ManualMetadataSmoke', macos / 'ManualMetadataSmoke')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.sublerautomation.' + root.name,
    'CFBundleExecutable': 'ManualMetadataSmoke', 'CFBundleName': 'Manual Metadata Smoke',
    'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'NSPrincipalClass': 'NSApplication'}))
run(['codesign', '--force', '--sign', '-', str(app)])
output, error = root / 'output.log', root / 'error.log'
run(['open', '-g', '-n', '-W', '--stdout', str(output), '--stderr', str(error),
     '--env', 'SUBLER_AUTOMATION_TEST_ROOT=' + str(root / 'state'), str(app)])
stdout = output.read_text() if output.exists() else ''
stderr = error.read_text() if error.exists() else ''
print(stdout, flush=True)
if 'MANUAL_METADATA_QUEUE_PASS:' not in stdout or 'Precondition failed' in stderr:
    raise RuntimeError(f'Queue smoke failed; evidence: {root}\n{stderr}')
