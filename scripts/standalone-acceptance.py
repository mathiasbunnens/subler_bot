#!/usr/bin/env python3
"""Generate scratch-only HEVC fixture and exercise a relocated signed app."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

project = Path(__file__).resolve().parent.parent
scratch = Path.home() / '.hermes/profiles/codex-dev-2/cache/scratch'
root = Path(tempfile.mkdtemp(prefix='standalone-déplacé-', dir=scratch))
app = root / 'Applications simulées/Subler Automation.app'
shutil.copytree(project / 'dist-standalone/Subler Automation.app', app, symlinks=True)
framework = app / 'Contents/Helpers/Subler Background.app/Contents/Frameworks'
probe = root / 'probe'
env = dict(os.environ, TMPDIR=str(scratch), SUBLER_EXPECTED_ENGINE=str(app / 'Contents/Helpers/Subler Background.app'))
env.pop('SUBLER_AUTOMATION_LOCAL_SUBLER_APP', None)

def run(args):
    subprocess.run(list(map(str, args)), check=True, env=env)

print('RELOCATED_APP ' + str(app), flush=True)
run(['codesign', '--verify', '--deep', '--strict', app])
run(['/opt/homebrew/bin/ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=24',
     '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '2', '-c:v', 'libx265',
     '-pix_fmt', 'yuv420p10le', '-x265-params', 'log-level=error:keyint=24', '-c:a', 'aac', root / 'generated.mkv'])
run(['clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-F', framework,
     '-framework', 'MP42Foundation', '-framework', 'Foundation', '-framework', 'AVFoundation',
     '-framework', 'CoreMedia', '-framework', 'CoreVideo', '-Wl,-headerpad_max_install_names',
     '-Wl,-rpath,' + str(framework), project / 'scripts/hevc-native-probe.m', '-o', probe])
run(['install_name_tool', '-change', '@loader_path/../Frameworks/MP42Foundation.framework/Versions/A/MP42Foundation',
     framework / 'MP42Foundation.framework/Versions/A/MP42Foundation', probe])
run(['codesign', '--force', '--sign', '-', probe])
run(['swift', project / 'scripts/local-subler-observe.swift', 'python3', project / 'scripts/test-bundle-engine-launch.py',
     '--app', app, '--generated', root / 'generated.mkv', '--probe', probe])
