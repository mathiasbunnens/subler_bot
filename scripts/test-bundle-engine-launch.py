#!/usr/bin/env python3
"""Launch actual signed release via LaunchServices, with scratch queue and generated MKV.
No engine environment variable, user media, SMB, production app restart or target activation.
Run under local-subler-observe.swift. Stops only the new scratch Automation PID it owns.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--generated', type=Path, required=True)
parser.add_argument('--probe', type=Path, required=True)
args = parser.parse_args()
project = Path(__file__).resolve().parent.parent
scratch = Path(os.environ['TMPDIR']).resolve()
root = Path(tempfile.mkdtemp(prefix='subler-bundle-launch-', dir=scratch))
app = args.app.resolve()
exe = str(app / 'Contents/MacOS/SublerAutomation')
env = dict(os.environ)
env.pop('SUBLER_AUTOMATION_LOCAL_SUBLER_APP', None)

def run(command, **kwargs):
    return subprocess.check_output(list(map(str, command)), text=True, env=env, stderr=subprocess.STDOUT, timeout=180, **kwargs)

def owned_pids():
    result = []
    for line in run(['ps', '-axo', 'pid=,comm=']).splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and fields[1] == exe:
            result.append(int(fields[0]))
    return result

assert not owned_pids(), 'Refusing to reuse/stop an already running release'
# Observe the actual app Bundle.main through LS, before any queue initialization.
out, err = root / 'diagnostic.json', root / 'diagnostic.stderr'
run(['open', '-g', '-n', '-W', '--stdout', out, '--stderr', err, app, '--args', '--diagnose-target'])
diag = json.loads(out.read_text())
assert diag['valid'] and diag['background'] and diag['applicationPath'] == str(app / 'Contents/Helpers/Subler Background.app'), diag
assert not (root / 'jobs.json').exists()
(root / 'Source').mkdir()
source = root / 'Source/Generated.2026.mkv'
shutil.copyfile(args.generated, source)
digest = hashlib.sha256(source.read_bytes()).hexdigest()
(root / 'settings.json').write_text(json.dumps(dict(
    sourcePath=str(root / 'Source'), temporaryPath=str(root / 'Temp'),
    smb=dict(serverURL='', username='', expectedMountPath=''), watchFolder=False,
    notifications=False, cleanupTemporary=False, paused=False, presentationMode='menuBar')))
# Compile only a fixture seed helper; app under test remains the unmodified release binary.
run(['swiftc', '-emit-library', '-emit-module', '-module-name', 'AutomationCore',
     *list((project / 'Sources/AutomationCore').glob('*.swift')),
     '-emit-module-path', root / 'AutomationCore.swiftmodule', '-o', root / 'libAutomationCore.dylib'])
run(['swiftc', '-I', root, '-L', root, '-lAutomationCore', '-Xlinker', '-rpath', '-Xlinker', root,
     project / 'scripts/bundle-engine-seed.swift', '-o', root / 'seed'])
run([root / 'seed', root])
owned = None
job = {}
try:
    run(['open', '-g', '-n', '--stdout', root / 'app.stdout', '--stderr', root / 'app.stderr',
         '--env', 'SUBLER_AUTOMATION_TEST_ROOT=' + str(root), app])
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        pids = owned_pids()
        assert len(pids) <= 1, 'Unexpected second release instance'
        if pids:
            if owned is None:
                owned = pids[0]
            assert pids == [owned], 'Owned scratch process was replaced'
        state = json.loads((root / 'jobs.json').read_text())
        job = state['jobs'][0]
        assert job['status'] != 'failed', job
        if job['validated'] and job['status'] == 'waitingForServer':
            break
        time.sleep(.2)
    else:
        raise AssertionError('No validated scratch conversion: ' + json.dumps(job))
    output = Path(job['localPath'])
    assert output.is_relative_to(root / 'Temp') and output.is_file()
    assert job['title'] == 'Generated Finder launch' and job['year'] == 2026
    assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
    decode = run([args.probe, 'inspect', output, 'all'])
    seek = run([args.probe, 'inspect', output, 'seek'])
    assert 'decodedImages=48' in decode and 'status=2 error=(null)' in decode, decode
    assert 'decodedImages=3' in seek, seek
    (root / 'decode.log').write_text(decode)
    (root / 'seek.log').write_text(seek)
    report = dict(diagnostic=diag, output=str(output), jobID=job['id'],
                  validated=True, images=48, seekImages=3, sourceUnchanged=True,
                  settingsRoot=str(root), launch='LaunchServices actual release, only TEST_ROOT override',
                  limits=['permission preflight injected by TEST_ROOT', 'no user media, SMB or TV', 'native mappings checked by separate rich fixture'])
    (root / 'report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2), flush=True)
finally:
    if owned is not None and owned_pids() == [owned]:
        os.kill(owned, 15)
        for _ in range(50):
            if not owned_pids():
                break
            time.sleep(.1)
        assert not owned_pids(), 'Owned scratch app did not exit'
