#!/usr/bin/env python3
"""Compile the actual pure Settings presenter; no windows, jobs or Apple Events.

Extract only the presenter so the executable never constructs SettingsView,
JobQueueService, or its window-focus accessor. Typechecking the whole view is
covered separately by swift build.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'Sources/SublerAutomation/Views/SettingsView.swift').read_text()
presenter = source.split('struct EngineAboutPresentation {', 1)[1].split('// Remember only', 1)[0]
engine = source.split('private var engine: some View {', 1)[1].split('private var folders:', 1)[0]
for token in ['EngineDiagnostic()', 'EngineAboutPresentation(diagnostic: diagnostic)',
              'diagnostic.label', 'diagnostic.status', 'diagnostic.targetBundleIdentifier',
              'presentation.validation', 'presentation.path', 'presentation.variant',
              'diagnostic.build', 'diagnostic.commit', 'presentation.sourceState',
              'diagnostic.bundleIdentifier', 'diagnostic.executablePath', 'AppVersion.current.details',
              'presentation.validationScope', 'presentation.fallbackNotice']:
    assert token in engine, token
for forbidden in ['SublerTarget(', 'ProcessInfo', 'UserDefaults', 'applySettings',
                  'preparePermissions', 'activate(', 'Timer', 'onReceive', 'object(forInfoDictionaryKey:']:
    assert forbidden not in engine + presenter, forbidden

fixture = r'''
@main struct EngineAboutContract {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let fm = FileManager.default
        func bundle(_ name: String, id: String, dirty: Bool, commit: String? = "0123456789abcdef") throws -> Bundle {
            let app = root.appendingPathComponent(name + ".app")
            try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.1.0", "CFBundleVersion": "6",
                "SublerAutomationSourceDirty": dirty]
            if let commit { info["SublerAutomationCommit"] = commit }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            return Bundle(url: app)!
        }
        let normal = try bundle("Normal", id: "com.mathiasbunnens.SublerAutomation", dirty: false)
        let local = try bundle("Local", id: "com.mathiasbunnens.SublerAutomation.Local", dirty: true)
        let unknown = try bundle("Unknown", id: "test.unknown", dirty: false, commit: nil)
        let installed = SublerTarget(backgroundApplication: nil)
        // Inject a synthetic installed lookup, never inspect or launch installed Subler.
        let valid = EngineDiagnostic(bundle: normal, target: installed, installedApplicationURL: root.appendingPathComponent("Installed.app"))
        let validUI = EngineAboutPresentation(diagnostic: valid)
        precondition(validUI.variant == "Normale" && validUI.validation == "Cible valide")
        precondition(validUI.fallbackNotice == nil && validUI.sourceState == "Sans modifications locales")
        precondition(valid.build == "6" && valid.commit == "0123456789abcdef")
        precondition(AppVersion(infoDictionary: normal.infoDictionary).details.contains("build 6"))
        let missing = root.appendingPathComponent("Missing Background.app").path
        let invalid = EngineDiagnostic(bundle: local, target: SublerTarget(backgroundApplication: missing), installedApplicationURL: nil)
        let invalidUI = EngineAboutPresentation(diagnostic: invalid)
        precondition(invalidUI.variant == "Locale" && invalidUI.validation == "Cible invalide — traitement bloqué")
        precondition(invalid.background && !invalid.valid && invalid.error != nil)
        precondition(invalidUI.path == missing && invalid.targetBundleIdentifier == "local.sublerautomation.Subler")
        precondition(invalidUI.fallbackNotice != nil && invalidUI.sourceState == "Avec modifications locales")
        precondition(invalid.status == invalid.error && !invalid.status.contains("Cible vérifiée"))
        let absentInstalled = EngineAboutPresentation(diagnostic: EngineDiagnostic(bundle: normal, target: installed, installedApplicationURL: nil))
        precondition(absentInstalled.validation == "Cible invalide — traitement bloqué")
        // Development override must not relabel a normal caller as the Local variant.
        let override = EngineAboutPresentation(diagnostic: EngineDiagnostic(bundle: normal, target: SublerTarget(backgroundApplication: missing), installedApplicationURL: nil))
        precondition(override.variant == "Normale" && override.fallbackNotice != nil)
        let malformed = EngineAboutPresentation(diagnostic: EngineDiagnostic(bundle: local, target: SublerTarget(backgroundApplication: ""), installedApplicationURL: nil))
        precondition(malformed.path == "Chemin non résolu" && !malformed.diagnostic.valid)
        let unknownUI = EngineAboutPresentation(diagnostic: EngineDiagnostic(bundle: unknown, target: installed, installedApplicationURL: nil))
        precondition(unknownUI.variant == "Développement / identité non reconnue")
        precondition(unknownUI.sourceState == "Provenance indisponible")
        precondition(validUI.validationScope.contains("ni l’autorisation macOS Automation"))
        precondition(validUI.validationScope.contains("ni une conversion réussie"))
        print("PASS: normal valid, local missing fail-closed, installed missing, normal/local override distinction, malformed path, dirty/full commit/build, unknown provenance, validation scope")
    }
}
'''
scratch = Path(os.environ['TMPDIR'])
with tempfile.TemporaryDirectory(prefix='engine-about-', dir=scratch) as directory:
    work = Path(directory)
    def run(*args):
        subprocess.run(args, cwd=ROOT, check=True)
    run('swiftc', '-enable-testing', '-emit-library', '-emit-module', '-module-name', 'AutomationCore',
        *map(str, sorted((ROOT / 'Sources/AutomationCore').glob('*.swift'))),
        '-o', str(work / 'libAutomationCore.dylib'), '-emit-module-path', str(work / 'AutomationCore.swiftmodule'))
    (work / 'presentation.swift').write_text('import Foundation\n@testable import AutomationCore\nstruct EngineAboutPresentation {' + presenter + fixture)
    run('swiftc', '-parse-as-library', '-I', str(work), '-L', str(work), '-lAutomationCore',
        '-Xlinker', '-rpath', '-Xlinker', str(work), str(work / 'presentation.swift'), '-o', str(work / 'contract'))
    run(str(work / 'contract'), str(work))
print('PASS: Settings view consumes shared diagnostic/presentation only; no settings mutation or second resolver')
