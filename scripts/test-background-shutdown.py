#!/usr/bin/env python3
"""Run the exact native shutdown guard without starting or contacting any app."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'vendor-local/Subler/Classes/ScriptCommand.swift').read_text()
assert 'enum BackgroundShutdownPolicy' in source, 'Missing atomic native shutdown guard'
policy = source[source.index('enum BackgroundShutdownPolicy'):source.index('@objc(SBQuitBackgroundScriptCommand)')]
checks = '''
func safe(_ docs: Int = 0, _ windows: Int = 0, _ active: Bool = false,
          _ working: Bool = false, _ items: [(String, Bool)] = [], _ owned: Set<String> = []) -> Bool {
    BackgroundShutdownPolicy.isSafe(documents: docs, windows: windows, active: active,
        working: working, items: items, owned: owned)
}
precondition(safe())
precondition(safe(0, 0, false, false, [("mine", true)], ["mine"]))
precondition(!safe(1)) // foreign or unknown document, even with no visible window
precondition(!safe(0, 1))
precondition(!safe(0, 0, true))
precondition(!safe(0, 0, false, true))
precondition(!safe(0, 0, false, false, [("foreign", true)], ["mine"]))
precondition(!safe(0, 0, false, false, [("mine", false)], ["mine"])) // ready/working/failed/unknown
precondition(!safe(0, 0, false, false, [("mine", true), ("mine", true)], ["mine"]))
print("PASS native shutdown guard: empty, owned completed, foreign/unknown documents and queue, active, duplicate")
'''
with tempfile.TemporaryDirectory(prefix='subler-shutdown-', dir=os.environ['TMPDIR']) as tmp:
    main = Path(tmp) / 'main.swift'
    main.write_text('import Foundation\n' + policy + checks)
    subprocess.run(['swiftc', str(main), '-o', str(Path(tmp) / 'test')], check=True)
    subprocess.run([str(Path(tmp) / 'test')], check=True)
