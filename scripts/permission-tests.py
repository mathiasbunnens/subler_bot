#!/usr/bin/env python3
"""Compile real native services and exercise only injected permissions in scratch."""
import os, pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
scratch = pathlib.Path.home() / '.hermes/cache/scratch'
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='subler-permissions-', dir=scratch) as directory:
    work = pathlib.Path(directory)
    env = dict(os.environ, SUBLER_AUTOMATION_TEST_ROOT=str(work))
    def run(*args): subprocess.run(args, check=True, cwd=root, env=env)
    run('swiftc', '-emit-library', '-emit-module', '-module-name', 'AutomationCore', *map(str, sorted((root/'Sources/AutomationCore').glob('*.swift'))), '-o', str(work/'libAutomationCore.dylib'), '-emit-module-path', str(work/'AutomationCore.swiftmodule'))
    run('swiftc', '-parse-as-library', '-I', str(work), '-L', str(work), '-lAutomationCore', '-Xlinker', '-rpath', '-Xlinker', str(work), 'Sources/SublerAutomation/Services/PermissionPreparationService.swift', 'Sources/SublerAutomation/Services/NotificationService.swift', 'scripts/permission-fixture.swift', '-o', str(work/'fixture'))
    run(str(work/'fixture'))
    run('swiftc', '-parse-as-library', '-I', str(work), '-L', str(work), '-lAutomationCore', '-Xlinker', '-rpath', '-Xlinker', str(work), 'Sources/SublerAutomation/Services/PermissionPreparationService.swift', 'Sources/SublerAutomation/Services/PermissionSettingsScope.swift', 'Sources/SublerAutomation/Services/NotificationService.swift', 'Sources/SublerAutomation/Models/AppSettings.swift', 'Sources/SublerAutomation/Views/PermissionSettingsView.swift', 'Sources/SublerAutomation/Views/SettingsView.swift', 'scripts/permission-ui-fixture.swift', '-o', str(work/'ui-fixture'))
    run(str(work/'ui-fixture'))
