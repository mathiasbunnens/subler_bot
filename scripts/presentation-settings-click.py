#!/usr/bin/env python3
"""Actual Settings click in the real App/Scene, signed scratch-only bundle.
Run under the shared native-lock.py; no production launch or synthetic settings host.
"""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

project = Path(__file__).resolve().parent.parent
scratch = Path.home() / '.hermes/cache/scratch'
scratch.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='subler-settings-click-', dir=scratch))
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
source = source.replace('        InstanceLock.acquire()', '        PresentationSettingsClick.prepare()\n        InstanceLock.acquire()')
source = source.replace('        AppPresentationController.shared.bind(queue)', '        AppPresentationController.shared.bind(queue)\n        Task { @MainActor in await PresentationSettingsClick.run(queue) }')
entrypoint = root / 'SublerAutomationApp.swift'
entrypoint.write_text(source)
files = [entrypoint, project / 'scripts/presentation-settings-click.swift', project / 'scripts/harness-check.swift']
for folder in ['Views', 'Models', 'Services']:
    files.extend((project / 'Sources/SublerAutomation' / folder).glob('*.swift'))
if '--baseline-settings-link' in sys.argv:
    view = project / 'Sources/SublerAutomation/Views/MenuBarView.swift'
    text = view.read_text()
    start = text.index('                Button {\n                    // Invoke the scene')
    end = text.index('                Spacer(minLength: 0)', start)
    baseline = root / 'MenuBarView.swift'
    baseline.write_text(text[:start] + '''                SettingsLink {
                    Label("Réglages…", systemImage: "gearshape")
                }.help("Ouvrir les réglages")
                    .simultaneousGesture(TapGesture().onEnded { SettingsWindowFocus.request() })
''' + text[end:])
    files = [baseline if file == view else file for file in files]
run(['swiftc', '-parse-as-library', '-I', str(root), '-L', str(root), '-lAutomationCore',
     '-Xlinker', '-rpath', '-Xlinker', str(root), *map(str, files), '-o', str(root / 'SettingsClick')])
app = root / 'SettingsClick.app'
macos = app / 'Contents/MacOS'
macos.mkdir(parents=True)
shutil.copy2(root / 'SettingsClick', macos / 'SettingsClick')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.sublerautomation.' + root.name,
    'CFBundleExecutable': 'SettingsClick', 'CFBundleName': 'Settings Click',
    'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'NSPrincipalClass': 'NSApplication'}))
run(['codesign', '--force', '--sign', '-', str(app)])
failures = []
for mode in ['menuBar', 'normal']:
    for attempt in range(3):
        output, error = root / f'{mode}-{attempt}.output.log', root / f'{mode}-{attempt}.error.log'
        run(['open', '-n', '-W', '--stdout', str(output), '--stderr', str(error),
             '--env', 'SUBLER_AUTOMATION_TEST_ROOT=' + str(root / f'{mode}-{attempt}'),
             '--env', 'PRESENTATION_INITIAL_MODE=' + mode, str(app)])
        stdout = output.read_text() if output.exists() else ''
        stderr = error.read_text() if error.exists() else ''
        print(stdout, flush=True)
        if 'PRESENTATION_SETTINGS_CLICK_PASS:' in stdout and 'Precondition failed' not in stderr:
            break
        if 'EXTERNAL_FOCUS_INTERRUPTED:' in stdout:
            print(f'Discarding inactive external-focus attempt {mode}-{attempt}', flush=True)
            continue
        failures.append(f'{mode}: {stderr or "Missing success marker"}')
        break
    else:
        failures.append(f'{mode}: external focus blocked all three attempts')
if failures:
    raise RuntimeError('\n'.join(failures))
print('PRESENTATION_SETTINGS_CLICK_ALL_PASS')
