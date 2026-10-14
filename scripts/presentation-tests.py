#!/usr/bin/env python3
"""Compile real settings against AutomationCore without touching package .build."""
import os
from pathlib import Path
import subprocess
import tempfile

project = Path(__file__).resolve().parent.parent
scratch = Path.home() / '.hermes/cache/scratch'
scratch.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='subler-presentation-', dir=scratch))
env = dict(os.environ, TMPDIR=str(scratch), SUBLER_AUTOMATION_TEST_ROOT=str(root / 'state'))

def run(args):
    result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=180)
    print(result.stdout, end='')
    if result.returncode:
        raise RuntimeError(result.stderr or f'Exit {result.returncode}')

run(['swiftc', '-emit-library', '-emit-module', '-module-name', 'AutomationCore',
     *map(str, (project / 'Sources/AutomationCore').glob('*.swift')),
     '-emit-module-path', str(root / 'AutomationCore.swiftmodule'), '-o', str(root / 'libAutomationCore.dylib')])
run(['swiftc', '-parse-as-library', '-I', str(root), '-L', str(root), '-lAutomationCore',
     '-Xlinker', '-rpath', '-Xlinker', str(root),
     str(project / 'Sources/SublerAutomation/Models/AppSettings.swift'),
     str(project / 'scripts/presentation-settings-test.swift'), str(project / 'scripts/harness-check.swift'), '-o', str(root / 'SettingsTest')])
run([str(root / 'SettingsTest')])
print('Evidence:', root)
