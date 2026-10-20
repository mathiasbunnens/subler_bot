import Foundation
import AppKit

/// Selection-only diagnostic: no Apple Events, permission requests, settings or queue reads.
public struct EngineDiagnostic: Encodable {
    public let bundleIdentifier: String
    public let build: String
    public let commit: String
    public let sourceDirty: Bool
    public let executablePath: String
    public let background: Bool
    public let targetBundleIdentifier: String
    public let applicationPath: String
    public let valid: Bool
    public let error: String?

    public init(bundle: Bundle = .main, target: SublerTarget = SublerTarget()) {
        self.init(bundle: bundle, target: target,
                  installedApplicationURL: target.isBackground ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier))
    }

    internal init(bundle: Bundle, target: SublerTarget, installedApplicationURL: URL?) {
        bundleIdentifier = bundle.bundleIdentifier ?? "hors bundle"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "indisponible"
        commit = bundle.object(forInfoDictionaryKey: "SublerAutomationCommit") as? String ?? "indisponible"
        sourceDirty = bundle.object(forInfoDictionaryKey: "SublerAutomationSourceDirty") as? Bool ?? false
        executablePath = bundle.executableURL?.path ?? "indisponible"
        background = target.isBackground
        targetBundleIdentifier = target.bundleIdentifier
        applicationPath = target.backgroundApplication
            ?? installedApplicationURL?.path
            ?? "Subler installé introuvable"
        do {
            _ = try target.validatedApplicationURL()
            if !target.isBackground && installedApplicationURL == nil {
                throw AutomationServiceError.message("Subler installé introuvable · \(target.bundleIdentifier)")
            }
            valid = true
            error = nil
        } catch {
            valid = false
            self.error = error.localizedDescription
        }
    }

    public var label: String { background ? "Moteur : Subler Background (local)" : "Moteur : Subler installé" }
    public var status: String { error ?? "Cible vérifiée · \(targetBundleIdentifier)" }
}
