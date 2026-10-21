#!/usr/bin/env python3
"""Read-only release/diagnostic contract; never initializes a user's queue."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--engine-source', type=Path, help='Compare every embedded file/symlink with the reviewed engine, including notices')
parser.add_argument('--allow-running-conflict', action='store_true',
                    help='Record a real conflicting old engine as a blocker, never as a valid runtime target')
args = parser.parse_args()
info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
assert info.get('SublerAutomationEngine') == 'background', 'Finder launch still selects installed Subler'
assert info['CFBundleIdentifier'] == 'com.mathiasbunnens.SublerAutomation.Local'
assert info['CFBundleDisplayName'] == 'Subler Automation'
assert info['SublerAutomationBackgroundRelativePath'] == 'Contents/Helpers/Subler Background.app'
assert int(info['CFBundleVersion']) >= 9
assert len(info['SublerAutomationCommit']) == 40
if args.engine_source:
    def inventory(root):
        return {str(p.relative_to(root)): ('symlink', os.readlink(p)) if p.is_symlink()
                else ('file', hashlib.sha256(p.read_bytes()).hexdigest())
                for p in root.rglob('*') if p.is_symlink() or p.is_file()}
    original = inventory(args.engine_source)
    embedded = inventory(args.app / info['SublerAutomationBackgroundRelativePath'])
    assert original == embedded, 'Embedded engine differs from reviewed source (including native frameworks/notices)'
    assert any(p.endswith('en.lproj/Credits.rtf') for p in embedded), 'Native notices are missing'
    print(f'PASS {len(embedded)} native files/symlinks preserved byte-for-byte, including Credits.rtf')
subprocess.run(['codesign', '--verify', '--deep', '--strict', args.app], check=True)
result = subprocess.run([args.app / 'Contents/MacOS/SublerAutomation', '--diagnose-target'],
                        check=True, capture_output=True, text=True, timeout=15)
diagnostic = json.loads(result.stdout)
assert diagnostic['bundleIdentifier'] == info['CFBundleIdentifier']
assert diagnostic['background'] is True
assert diagnostic['targetBundleIdentifier'] == 'local.sublerautomation.Subler'
assert diagnostic['applicationPath'] == str(args.app.resolve() / info['SublerAutomationBackgroundRelativePath'])
def check_runtime(diagnostic):
    if not diagnostic['valid']:
        assert args.allow_running_conflict and 'different local Subler build is already running' in diagnostic['error'], diagnostic
        print('BLOCKED runtime validation: ' + diagnostic['error'])
check_runtime(diagnostic)
assert diagnostic['commit'] == info['SublerAutomationCommit']
assert diagnostic['build'] == info['CFBundleVersion']
with tempfile.TemporaryDirectory(prefix='subler-autonome-déplacé-', dir=os.environ['TMPDIR']) as temporary:
    isolated = Path(temporary) / 'Applications simulées' / args.app.name
    shutil.copytree(args.app, isolated, symlinks=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', isolated], check=True)
    def diagnose():
        result = subprocess.run([isolated / 'Contents/MacOS/SublerAutomation', '--diagnose-target'],
                                check=True, capture_output=True, text=True, timeout=15,
                                env=dict(os.environ, SUBLER_AUTOMATION_LOCAL_SUBLER_APP='/unreviewed/Other.app'))
        return json.loads(result.stdout)
    moved = diagnose()
    engine = isolated / info['SublerAutomationBackgroundRelativePath']
    # Foundation may return macOS's decomposed spelling for accented paths.
    # Compare real file identity, not a normalized string that might hide relocation.
    assert Path(moved['applicationPath']).samefile(engine) and moved['embedded'], moved
    assert Path(moved['executablePath']).samefile(isolated / 'Contents/MacOS/SublerAutomation'), moved
    assert not (isolated.parent / 'Subler Background.app').exists()
    check_runtime(moved)
    print('RELOCATED_DIAGNOSTIC ' + json.dumps(moved, ensure_ascii=False))
    engine_info = plistlib.loads((engine / 'Contents/Info.plist').read_bytes())
    executable = engine / 'Contents/MacOS' / engine_info['CFBundleExecutable']
    mode = executable.stat().st_mode
    executable.chmod(0o644)
    unusable = diagnose()
    assert not unusable['valid'] and 'usable executable' in unusable['error'], unusable
    executable.chmod(mode)
    engine.rename(Path(temporary) / 'Engine removed.app')
    missing = subprocess.run([isolated / 'Contents/MacOS/SublerAutomation', '--diagnose-target'],
                             check=True, capture_output=True, text=True, timeout=15)
    rejected = json.loads(missing.stdout)
    assert rejected['background'] is True and rejected['valid'] is False, rejected
    assert rejected['targetBundleIdentifier'] == 'local.sublerautomation.Subler'
    assert 'fallback' in rejected['error'], rejected
print(json.dumps(diagnostic, indent=2, ensure_ascii=False))
print('PASS standalone signed copy relocates without sibling, ignores environment, missing/non-executable engine fail closed')
