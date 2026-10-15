#!/usr/bin/env python3
"""Render the real menu and Settings views to PNG off-screen, light and dark.
Launched in the background (open -g, never activated, no visible window) with a
fresh scratch root: no production state, Subler or SMB is touched.
Usage: python3 scripts/render-ui.py  -> prints the folder containing the PNGs.
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
root = Path(tempfile.mkdtemp(prefix='subler-render-ui-', dir=scratch))
print('Evidence:', root, flush=True)
env = dict(os.environ, TMPDIR=str(scratch))
def run(args):
    result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=300)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout
run(['swiftc', '-emit-library', '-emit-module', '-module-name', 'AutomationCore',
     *map(str, (project / 'Sources/AutomationCore').glob('*.swift')),
     '-emit-module-path', str(root / 'AutomationCore.swiftmodule'), '-o', str(root / 'libAutomationCore.dylib')])
files = [project / 'scripts/render-ui.swift', project / 'scripts/harness-check.swift']
for folder in ['Views', 'Models', 'Services']:
    files.extend((project / 'Sources/SublerAutomation' / folder).glob('*.swift'))
run(['swiftc', '-parse-as-library', '-I', str(root), '-L', str(root), '-lAutomationCore',
     '-Xlinker', '-rpath', '-Xlinker', str(root), *map(str, files), '-o', str(root / 'RenderUI')])
app = root / 'RenderUI.app'
(app / 'Contents/MacOS').mkdir(parents=True)
shutil.copy2(root / 'RenderUI', app / 'Contents/MacOS/RenderUI')
version_info = plistlib.loads((project / 'Sources/SublerAutomation/Resources/Info.plist').read_bytes())
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleShortVersionString': version_info['CFBundleShortVersionString'],
    'CFBundleVersion': version_info['CFBundleVersion'],
    'CFBundleIdentifier': 'local.sublerautomation.' + root.name,
    'CFBundleExecutable': 'RenderUI', 'CFBundleName': 'Render UI',
    'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'LSBackgroundOnly': True,
    'NSPrincipalClass': 'NSApplication'}))
run(['codesign', '--force', '--sign', '-', str(app)])
poster = root / 'fixture-poster.png'
ffmpeg = next((p for p in ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg'] if os.access(p, os.X_OK)), None)
extra = []
if ffmpeg:
    run([ffmpeg, '-v', 'error', '-f', 'lavfi', '-i', 'gradients=s=200x300:c0=0x1d3557:c1=0xe76f51:d=1', '-frames:v', '1', str(poster)])
    extra = ['--env', 'RENDER_POSTER=' + str(poster)]
out = root / 'png'
out.mkdir()
output, error = root / 'output.log', root / 'error.log'
run(['open', '-g', '-n', '-W', '--stdout', str(output), '--stderr', str(error),
     '--env', 'SUBLER_AUTOMATION_TEST_ROOT=' + str(root / 'state'), '--env', 'RENDER_OUTPUT=' + str(out), *extra, str(app)])
stdout = output.read_text() if output.exists() else ''
print(stdout, flush=True)
if 'RENDER_UI_PASS' not in stdout:
    raise RuntimeError(f'Render failed; evidence: {root}\n' + (error.read_text() if error.exists() else ''))
print('PNG:', out)
