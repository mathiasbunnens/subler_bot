#!/usr/bin/env python3
"""Preflight output ownership, then stamp build selection before signing."""
import argparse
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--local-engine', action='store_true')
parser.add_argument('--check-only', action='store_true')
args = parser.parse_args()
app = args.app.resolve()
running = subprocess.check_output(['ps', '-axo', 'comm='], text=True).splitlines()
assert str(app / 'Contents/MacOS/SublerAutomation') not in [s.strip() for s in running], 'Refusing to replace a running application'
if args.local_engine:
    engine = app.parent / 'Subler Background.app'
    info = plistlib.loads((engine / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'local.sublerautomation.Subler'
    assert info['SublerAutomationBackgroundProtocol'] == '2'
    assert info['LSBackgroundOnly'] is True
    subprocess.run(['codesign', '--verify', '--deep', '--strict', engine], check=True)
if args.check_only:
    raise SystemExit(0)
path = app / 'Contents/Info.plist'
info = plistlib.loads(path.read_bytes())
info['SublerAutomationCommit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
info['SublerAutomationSourceDirty'] = bool(subprocess.check_output(['git', 'diff', 'HEAD', '--', 'Sources', 'build.sh', 'scripts/configure-app-bundle.py'], text=True).strip())
if args.local_engine:
    info.update(CFBundleName='Subler Automation Local', CFBundleDisplayName='Subler Automation Local',
                CFBundleIdentifier='com.mathiasbunnens.SublerAutomation.Local',
                SublerAutomationEngine='background',
                SublerAutomationBackgroundRelativePath='../Subler Background.app')
    # Do not compete with the installed build's Finder Services registration.
    info.pop('NSServices', None)
path.write_bytes(plistlib.dumps(info))
