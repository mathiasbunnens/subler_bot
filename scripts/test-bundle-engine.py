#!/usr/bin/env python3
"""Read-only release/diagnostic contract; never initializes a user's queue."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
args = parser.parse_args()
info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
assert info.get('SublerAutomationEngine') == 'background', 'Finder launch still selects installed Subler'
assert info['CFBundleIdentifier'] == 'com.mathiasbunnens.SublerAutomation.Local'
assert info['CFBundleDisplayName'] == 'Subler Automation Local'
assert int(info['CFBundleVersion']) >= 5
assert len(info['SublerAutomationCommit']) == 40
subprocess.run(['codesign', '--verify', '--deep', '--strict', args.app], check=True)
result = subprocess.run([args.app / 'Contents/MacOS/SublerAutomation', '--diagnose-target'],
                        check=True, capture_output=True, text=True, timeout=15)
diagnostic = json.loads(result.stdout)
assert diagnostic['bundleIdentifier'] == info['CFBundleIdentifier']
assert diagnostic['background'] is True
assert diagnostic['targetBundleIdentifier'] == 'local.sublerautomation.Subler'
assert diagnostic['applicationPath'] == str(args.app.resolve().parent / 'Subler Background.app')
assert diagnostic['valid'] is True, diagnostic
assert diagnostic['commit'] == info['SublerAutomationCommit']
assert diagnostic['build'] == info['CFBundleVersion']
with tempfile.TemporaryDirectory(prefix='subler-missing-engine-', dir=os.environ['TMPDIR']) as temporary:
    isolated = Path(temporary) / args.app.name
    shutil.copytree(args.app, isolated)
    missing = subprocess.run([isolated / 'Contents/MacOS/SublerAutomation', '--diagnose-target'],
                             check=True, capture_output=True, text=True, timeout=15)
    rejected = json.loads(missing.stdout)
    assert rejected['background'] is True and rejected['valid'] is False, rejected
    assert rejected['targetBundleIdentifier'] == 'local.sublerautomation.Subler'
    assert 'fallback' in rejected['error'], rejected
print(json.dumps(diagnostic, indent=2, ensure_ascii=False))
print('PASS missing co-local engine fails closed in actual signed executable')
