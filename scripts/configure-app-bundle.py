#!/usr/bin/env python3
"""Preflight output ownership, then stamp build selection before signing."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
selection = parser.add_mutually_exclusive_group()
selection.add_argument('--local-engine', action='store_true')
selection.add_argument('--embedded-engine', action='store_true')
parser.add_argument('--engine-source', type=Path)
parser.add_argument('--check-only', action='store_true')
args = parser.parse_args()
app = args.app.resolve()
running = subprocess.check_output(['ps', '-axo', 'comm='], text=True).splitlines()
assert not any(s.strip().startswith(str(app) + '/') for s in running), 'Refusing to replace a running application or nested engine'
if args.engine_source and not args.embedded_engine:
    parser.error('--engine-source requires --embedded-engine')
engine = None
if args.local_engine or args.embedded_engine:
    engine = (args.engine_source or Path('dist-local/Subler Background.app')).resolve() if args.embedded_engine else app.parent / 'Subler Background.app'
    if args.embedded_engine:
        assert not engine.is_relative_to(app), 'Engine source must be outside the output bundle'
    info = plistlib.loads((engine / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'local.sublerautomation.Subler'
    assert info['SublerAutomationBackgroundProtocol'] == '2'
    assert info['LSBackgroundOnly'] is True
    executable_name = info.get('CFBundleExecutable')
    assert isinstance(executable_name, str) and executable_name and Path(executable_name).name == executable_name, 'Local engine has no usable executable'
    executable = engine / 'Contents/MacOS' / executable_name
    assert executable.is_file() and os.access(executable, os.X_OK), 'Local engine has no usable executable'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', engine], check=True)
if args.check_only:
    raise SystemExit(0)
path = app / 'Contents/Info.plist'
info = plistlib.loads(path.read_bytes())
info['SublerAutomationCommit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
info['SublerAutomationSourceDirty'] = bool(subprocess.check_output(['git', 'diff', 'HEAD', '--', 'Sources', 'build.sh', 'scripts/configure-app-bundle.py'], text=True).strip())
if args.local_engine or args.embedded_engine:
    name = 'Subler Automation' if args.embedded_engine else 'Subler Automation Local'
    relative = 'Contents/Helpers/Subler Background.app' if args.embedded_engine else '../Subler Background.app'
    info.update(CFBundleName=name, CFBundleDisplayName=name,
                CFBundleIdentifier='com.mathiasbunnens.SublerAutomation.Local',
                SublerAutomationEngine='background',
                SublerAutomationBackgroundRelativePath=relative)
    # Do not compete with the installed build's Finder Services registration.
    info.pop('NSServices', None)
    if args.embedded_engine:
        assert engine is not None
        destination = app / relative
        if destination.exists():
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        # Preserve framework symlinks, licences, notices and existing inside-out signatures.
        shutil.copytree(engine, destination, symlinks=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', destination], check=True)
path.write_bytes(plistlib.dumps(info))
