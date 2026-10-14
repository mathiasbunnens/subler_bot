#!/usr/bin/env python3
"""Exercise the real SwiftUI @main and Scene in a signed, scratch-only app.
Only inject scratch preparation + an async test driver into a copied initializer.
No .build, production launch, substitute Scene or test-root fallback.
"""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

baseline = '--baseline-always-inserted' in sys.argv
skip_miniaturization = '--skip-miniaturization' in sys.argv

project = Path(__file__).resolve().parent.parent
scratch = Path.home() / '.hermes/cache/scratch'
scratch.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='subler-presentation-entrypoint-', dir=scratch))
env = dict(os.environ, TMPDIR=str(scratch))
print('Evidence:', root, flush=True)

def run(args):
    result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout

run(['swiftc', '-emit-library', '-emit-module', '-module-name', 'AutomationCore',
     *map(str, (project / 'Sources/AutomationCore').glob('*.swift')),
     '-emit-module-path', str(root / 'AutomationCore.swiftmodule'), '-o', str(root / 'libAutomationCore.dylib')])
source = (project / 'Sources/SublerAutomation/App/SublerAutomationApp.swift').read_text()
if baseline:
    assert source.count('get: { queue.settings.presentationMode == .menuBar }') == 1
    source = source.replace('get: { queue.settings.presentationMode == .menuBar }', 'get: { true }')
assert source.count('        InstanceLock.acquire()') == 1
assert source.count('        AppPresentationController.shared.bind(queue)') == 1
source = source.replace('        InstanceLock.acquire()', '        PresentationEntrypointSmoke.prepare()\n        InstanceLock.acquire()')
source = source.replace('        AppPresentationController.shared.bind(queue)', '        AppPresentationController.shared.bind(queue)\n        Task { @MainActor in await PresentationEntrypointSmoke.run(queue) }')
entrypoint = root / 'SublerAutomationApp.swift'
entrypoint.write_text(source)
files = [entrypoint, project / 'scripts/presentation-entrypoint-smoke.swift', project / 'scripts/harness-check.swift']
for folder in ['Views', 'Models', 'Services']:
    files.extend((project / 'Sources/SublerAutomation' / folder).glob('*.swift'))
controller = project / 'Sources/SublerAutomation/Services/AppPresentationController.swift'
instrumented = root / controller.name
instrumented.write_text(controller.read_text().replace('AppPresentationController.shared.showMainWindow()', 'print("DOCK_REOPEN: visible=\\(flag) minimized=\\(AppPresentationController.shared.mainWindow?.isMiniaturized ?? false)"); AppPresentationController.shared.showMainWindow()'))
files = [instrumented if file == controller else file for file in files]
run(['swiftc', '-parse-as-library', '-I', str(root), '-L', str(root), '-lAutomationCore',
     '-Xlinker', '-rpath', '-Xlinker', str(root), *map(str, files), '-o', str(root / 'EntrypointSmoke')])
app = root / 'EntrypointSmoke.app'
macos = app / 'Contents/MacOS'
macos.mkdir(parents=True)
shutil.copy2(root / 'EntrypointSmoke', macos / 'EntrypointSmoke')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.sublerautomation.' + root.name,
    'CFBundleExecutable': 'EntrypointSmoke', 'CFBundleName': 'Entrypoint Smoke',
    'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'NSPrincipalClass': 'NSApplication',
}))
run(['codesign', '--force', '--sign', '-', str(app)])
failures = []
for mode in ['normal', 'menuBar']:
    output, error = root / f'{mode}.output.log', root / f'{mode}.error.log'
    run(['open', '-n', '-W', '--stdout', str(output), '--stderr', str(error),
         '--env', 'SUBLER_AUTOMATION_TEST_ROOT=' + str(root / mode),
         '--env', 'PRESENTATION_SKIP_MINIATURIZATION=' + ('1' if skip_miniaturization else '0'),
         '--env', 'PRESENTATION_INITIAL_MODE=' + mode, str(app)])
    stdout = output.read_text() if output.exists() else ''
    stderr = error.read_text() if error.exists() else ''
    print(stdout, flush=True)
    if 'PRESENTATION_ENTRYPOINT_PASS:' not in stdout or 'Precondition failed' in stderr:
        failures.append(f'{mode}: {stderr or "Missing success marker"}')
if failures:
    raise RuntimeError('\n'.join(failures))
print('PRESENTATION_ENTRYPOINT_ALL_PASS')
