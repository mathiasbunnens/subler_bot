#!/usr/bin/env python3
"""Read-only release and isolated-test readback; emit deterministic evidence JSON."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--appkit-evidence', type=Path, required=True)
parser.add_argument('--swift-log', type=Path, required=True)
args = parser.parse_args()
project = Path(__file__).resolve().parents[1]
info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=project, text=True).strip()
assert info['CFBundleVersion'] == '11'
assert info['SublerAutomationCommit'] == commit and info['SublerAutomationSourceDirty'] is False
engine = args.app / 'Contents/Helpers/Subler Background.app'
engine_info = plistlib.loads((engine / 'Contents/Info.plist').read_bytes())
assert engine_info['SublerAutomationGracefulQuitProtocol'] == '1'
assert 'SublBgQt' in (engine / 'Contents/Resources/Subler.sdef').read_text()
subprocess.run(['codesign', '--verify', '--deep', '--strict', args.app], check=True)
cases = json.loads((args.appkit_evidence / 'results.json').read_text())
assert sorted(case['mode'] for case in cases) == sorted(['absent', 'empty', 'native', 'signal', 'repeated', 'foreignqueue', 'foreigndoc', 'preexisting'])
for case in cases:
    assert case['queuePreserved'] and case['drainedWithoutCancellation']
    state = args.appkit_evidence / case['mode'] / 'state'
    assert (state / 'worker-finished').exists() and (state / 'manual-finished').exists()
    if case['pid']:
        case['inactiveSamples'] = int((state / 'inactive-samples').read_text())
        assert case['inactiveSamples'] >= 3
text = args.swift_log.read_text()
match = re.findall(r'Executed (\d+) tests, with (\d+) tests skipped and (\d+) failures', text)[-1]
executed, skipped, failures = map(int, match)
assert failures == 0

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

print(json.dumps({
    'app': str(args.app.resolve()), 'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'], 'commit': commit, 'sourceDirty': False,
    'appExecutableSHA256': sha(args.app / 'Contents/MacOS' / info['CFBundleExecutable']),
    'engineExecutableSHA256': sha(engine / 'Contents/MacOS' / engine_info['CFBundleExecutable']),
    'nativePatchSHA256': {path.name: sha(path) for path in sorted((project / 'patches/local-subler').glob('*.patch'))},
    'swiftTests': {'executed': executed, 'passed': executed - skipped, 'skipped': skipped, 'failures': failures},
    'appkitCases': cases, 'appkitCount': len(cases),
    'limitations': ['AppKit/Apple Event integration uses the exact native quit handler with in-memory generated queue records and injected delayed workers; no user engine or queue is used.',
                    'No real movie conversion or NAS transfer was repeated for shutdown testing.',
                    'Pre-existing engines, previous-session/foreign queue records, unknown documents or failed native acknowledgement are preserved.',
                    'SIGKILL, force-quit and power loss cannot be drained; ad-hoc signatures do not imply notarization or permanent TCC consent.']
}, ensure_ascii=False, indent=2))
