#!/usr/bin/env python3
"""Real MenuBarExtra autosizing regression; never resizes its native window."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import sys

sticky_height = '--sticky-height-negative-control' in sys.argv
project = Path(__file__).resolve().parent.parent
scratch = Path.home() / '.hermes/cache/scratch'
scratch.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='subler-menu-popup-', dir=scratch))
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
source = (project / 'Sources/SublerAutomation/App/SublerAutomationApp.swift').read_text()
assert source.count('        InstanceLock.acquire()') == 1
assert source.count('        AppPresentationController.shared.bind(queue)') == 1
source = source.replace('        InstanceLock.acquire()', '        MenuPopupLayout.prepare()\n        InstanceLock.acquire()')
source = source.replace('        AppPresentationController.shared.bind(queue)', '        AppPresentationController.shared.bind(queue)\n        Task { @MainActor in await MenuPopupLayout.run(queue) }')
entrypoint = root / 'SublerAutomationApp.swift'
entrypoint.write_text(source)
files = [entrypoint, project / 'scripts/menu-popup-layout.swift']
for folder in ['Views', 'Models', 'Services']:
    files.extend((project / 'Sources/SublerAutomation' / folder).glob('*.swift'))
if sticky_height:
    # Artificial negative control ONLY, not a claim that current production is broken.
    view = project / 'Sources/SublerAutomation/Views/MenuBarView.swift'
    mutated = root / 'MenuBarView.swift'
    text = view.read_text()
    assert text.count('contentHeight = height') == 1
    mutated.write_text(text.replace('contentHeight = height', 'contentHeight = max(contentHeight, height)'))
    files = [mutated if file == view else file for file in files]
run(['swiftc', '-parse-as-library', '-I', str(root), '-L', str(root), '-lAutomationCore',
     '-Xlinker', '-rpath', '-Xlinker', str(root), *map(str, files), '-o', str(root / 'MenuPopupLayout')])
app = root / 'MenuPopupLayout.app'
macos = app / 'Contents/MacOS'
macos.mkdir(parents=True)
shutil.copy2(root / 'MenuPopupLayout', macos / 'MenuPopupLayout')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.sublerautomation.' + root.name,
    'CFBundleExecutable': 'MenuPopupLayout', 'CFBundleName': 'Menu Popup Layout',
    'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'NSPrincipalClass': 'NSApplication'}))
run(['codesign', '--force', '--sign', '-', str(app)])
failures = []
for attempt in range(3):
    output, error = root / f'output-{attempt}.log', root / f'error-{attempt}.log'
    run(['open', '-n', '-W', '--stdout', str(output), '--stderr', str(error),
         '--env', 'SUBLER_AUTOMATION_TEST_ROOT=' + str(root / f'state-{attempt}'), str(app)])
    stdout = output.read_text() if output.exists() else ''
    stderr = error.read_text() if error.exists() else ''
    print(stdout, flush=True)
    if 'MENU_POPUP_LAYOUT_PASS:' in stdout and 'Precondition failed' not in stderr:
        break
    failures.append(stderr)
    if 'EXTERNAL_ACTIVATION:' not in stdout:
        raise RuntimeError(f'Native popup regression failed; evidence: {root}\n{stderr}')
    print(f'Discarding externally interrupted attempt {attempt + 1}', flush=True)
else:
    raise RuntimeError(f'Native focus blocked after 3 attempts; evidence: {root}\n' + '\n'.join(failures))
