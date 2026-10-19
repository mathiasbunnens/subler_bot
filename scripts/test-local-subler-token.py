#!/usr/bin/env python3
"""Execute the native resolver with deterministic process/counter reuse, no app launch."""
from pathlib import Path
import os
import sys
import subprocess
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
native = root / 'vendor-local/Subler'
source = (native / 'Classes/ScriptCommand.swift').read_text()
if '--baseline' in sys.argv:
    source = subprocess.run(['git', '-C', str(native), 'show', '5442a16:Classes/ScriptCommand.swift'], check=True, capture_output=True, text=True).stdout
resolver = source[source.index('protocol ScriptCommandDocumentTargeting'):source.index('    func extractFilePath')]
resolver += '}\n'
# Minimal AppKit stand-ins: run the unchanged production resolver, not a rewrite.
stubs = '''import Foundation
class Document {
    let uniqueID: Int
    let backgroundToken: String
    init(_ id: Int, _ token: String) { uniqueID = id; backgroundToken = token }
}
class NSScriptCommand {
    var scriptErrorNumber = 0
    var scriptErrorString: String?
    var evaluatedArguments: [String: Any]?
    var directParameter: Any?
    var receiversSpecifier: Specifier?
}
class Specifier { var objectsByEvaluatingSpecifier: Any? }
class DocumentWindowController { var document: Any? }
class NSWindow { var windowController: Any? }
class NSDocumentController {
    static let shared = NSDocumentController()
    var documents: [Any] = []
    var currentDocument: Any?
}
class Command: NSScriptCommand, ScriptCommandDocumentTargeting {}
'''
checks = '''
func expect(_ condition: @autoclosure () -> Bool, _ message: String = "native token assertion failed") {
    if !condition() { print("FAIL: " + message); exit(1) }
}
let old = Document(1, "11111111-1111-4111-8111-111111111111")
let replacement = Document(1, "22222222-2222-4222-8222-222222222222")
let oldHandle: Any = old.backgroundToken
let controller = NSDocumentController.shared
controller.documents = [replacement]
controller.currentDocument = replacement
let command = Command()
// New native process, same counter. Also supply fallbacks to ensure none is used.
command.evaluatedArguments = ["ownedToken": oldHandle, "doc": replacement, "into": replacement]
command.directParameter = replacement
expect(command.targetedDocument() == nil, "stale token targeted replacement")
for malformed: Any in [1, "", NSNull()] {
    command.evaluatedArguments = ["ownedToken": malformed, "doc": replacement]
    expect(command.targetedDocument() == nil, "malformed token fell back")
}
command.evaluatedArguments = ["ownedToken": replacement.backgroundToken]
expect(command.targetedDocument() === replacement)
// A stale close is a no-op; candidates/metadata/enqueue receive no document.
for _ in ["candidates", "metadata", "enqueue", "close"] {
    command.evaluatedArguments = ["ownedToken": old.backgroundToken]
    expect(command.targetedDocument() == nil)
    expect(controller.documents.count == 1)
}
command.evaluatedArguments = ["doc": replacement]
expect(command.targetedDocument() === replacement, "legacy explicit targeting changed")
print("PASS native resolver: restart/counter reuse, stale/malformed no fallback, replacement preserved")
'''
if '--baseline' in sys.argv:
    # The old wire protocol sends the reused integer, not the new UUID.
    checks = checks.replace('let oldHandle: Any = old.backgroundToken', 'let oldHandle: Any = old.uniqueID')
with tempfile.TemporaryDirectory(prefix='subler-token-', dir=os.environ['TMPDIR']) as tmp:
    path = Path(tmp) / 'main.swift'
    path.write_text(stubs + resolver + checks)
    subprocess.run(['swiftc', str(path), '-o', str(Path(tmp) / 'test')], check=True)
    subprocess.run([str(Path(tmp) / 'test')], check=True)
    print('PASS executable native resolver regression')
doc = (native / 'Classes/Document.swift').read_text()
assert 'let backgroundToken = UUID().uuidString' in doc
assert 'return doc.backgroundToken' in source
assert 'directParameter as? String' in source[source.index('class SBHasBackgroundDocumentScriptCommand'):source.index('@objc(SBBackgroundStateScriptCommand)')]
sdef = ET.parse(native / 'Subler.sdef')
for parameter in sdef.findall('.//parameter[@name="owned token"]'):
    assert parameter.get('type') == 'text'
presence = sdef.find('.//command[@name="has background document"]/direct-parameter')
assert presence is not None and presence.get('type') == 'text'
print('PASS native UUID generation, presence lookup and all SDEF token types')
