import Foundation
import Combine
import AppKit
import Carbon
import Darwin
import AutomationCore

/// Single owner shared by startup, queue gating and Settings. Native calls are NEVER
/// selected when SUBLER_AUTOMATION_TEST_ROOT exists, including an empty value.
@MainActor final class PermissionPreparationService: ObservableObject {
    static let shared = PermissionPreparationService()
    @Published private(set) var state: PermissionPreparationState = .unprepared
    @Published private(set) var networkMessage = "Partage réseau non vérifié."
    @Published private(set) var notificationStatus: PermissionDecision = .undetermined
    private let engine: PermissionPreparation
    private var checking = false
    private let selectScope: (PermissionScope) -> Void
    init(operations: PermissionOperations? = nil, storageURL: URL? = nil) {
        let environment = ProcessInfo.processInfo.environment
        let fixture = environment["SUBLER_AUTOMATION_TEST_ROOT"]
        let root = fixture.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Subler Automation")
        let file = storageURL ?? root.appendingPathComponent("permission-grant.json")
        var selectedScope: PermissionScope?
        selectScope = { selectedScope = $0 }
        let allGrants: () throws -> [PermissionGrant] = {
            guard FileManager.default.fileExists(atPath: file.path) else { return [] }
            let data = try Data(contentsOf: file)
            if let grants = try? JSONDecoder().decode([PermissionGrant].self, from: data) { return grants }
            return [try JSONDecoder().decode(PermissionGrant.self, from: data)]
        }
        let load: () throws -> PermissionGrant? = { try allGrants().first { $0.scope == selectedScope } }
        let save: (PermissionGrant) throws -> Void = { grant in
            var grants = try allGrants().filter { $0.scope != grant.scope }
            grants.append(grant)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(grants).write(to: file, options: .atomic)
        }
        if let operations { engine = PermissionPreparation(operations: operations) }
        else if fixture != nil {
            engine = PermissionPreparation(operations: .init(automation: { _ in .granted }, sourceRead: { _, _ in nil }, temporaryWrite: { _, _ in nil }, mountedShare: { _ in nil }, networkRead: { _, _ in nil }, notifications: { _ in .granted }, load: load, save: save))
        } else {
            engine = PermissionPreparation(operations: .init(automation: { request in
                await PermissionNativeAccess.automation(request: request)
            }, sourceRead: { path, request in
                await PermissionNativeAccess.directoryRead(path, request: request, local: true)
            }, temporaryWrite: { path, request in
                await PermissionNativeAccess.temporaryWrite(path, request: request)
            }, mountedShare: { scope in
                PermissionNativeAccess.mountedShare(scope)
            }, networkRead: { path, request in
                await PermissionNativeAccess.directoryRead(path, request: request, local: false)
            }, notifications: { request in
                await NotificationService().permissionStatus(requestIfNeeded: request)
            }, load: load, save: save))
        }
    }
    func isReady(for scope: PermissionScope) -> Bool { !checking && state.isReady && engine.checkedScope == scope }
    /// Call once during startup, BEFORE watch scanning or any Subler/queue work.
    /// First check the recorded scope silently; only a new scope requests upfront.
    func startup(_ scope: PermissionScope) async {
        _ = await PermissionNativeAccess.launchSublerIfNeeded()
        await recheck(scope)
        if !isReady(for: scope), !engine.hasRecordedScope { await prepare(scope) }
    }
    /// Explicit user retry / first-run onboarding only. Never call from a queue tick.
    func prepare(_ scope: PermissionScope) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        state = .requesting
        selectScope(scope)
        await engine.prepare(scope)
        publish()
    }
    /// No AppleEvents/notification requests, no filesystem data probes, no mounting.
    func recheck(_ scope: PermissionScope) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        selectScope(scope)
        await engine.recheck(scope)
        publish()
    }
    private func publish() {
        if state != engine.state { state = engine.state }
        if networkMessage != engine.networkMessage { networkMessage = engine.networkMessage }
        if notificationStatus != engine.notificationStatus { notificationStatus = engine.notificationStatus }
    }
}

enum PermissionNativeAccess {
    @MainActor static func launchSublerIfNeeded() async -> Bool {
        guard ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"] == nil else { return true }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "org.galad.Subler").isEmpty { return true }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.galad.Subler") else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return true
        } catch { return false }
    }
    static func automation(request: Bool) async -> PermissionDecision {
        guard ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"] == nil else { return .granted }
        if request, !(await launchSublerIfNeeded()) { return .undetermined }
        // Permission determination sends no conversion Apple Event and imports nothing.
        return await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: "org.galad.Subler")
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), request)
            if status == noErr { return PermissionDecision.granted }
            if status == errAEEventWouldRequireUserConsent || status == procNotFound { return PermissionDecision.undetermined }
            return PermissionDecision.denied
        }.value
    }
    static func localDirectory(_ path: String) throws -> URL {
        try LocalPathPolicy.directoryURL(path)
    }
    static func directoryRead(_ path: String, request: Bool, local: Bool) async -> String? {
        await Task.detached(priority: .utility) {
            do {
                let url = (local && request) ? try localDirectory(path) : URL(fileURLWithPath: path)
                if request {
                    if local { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
                    // Reading the directory upfront lets macOS present its file-access dialog.
                    _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                } else {
                    // No open/enumeration during work. access is only a non-requesting
                    // preflight, not a promise against revocation between this and I/O.
                    guard access(url.path, R_OK | X_OK) == 0 else { throw CocoaError(.fileReadNoPermission) }
                }
                return nil
            } catch { return error.localizedDescription }
        }.value
    }
    static func temporaryWrite(_ path: String, request: Bool) async -> String? {
        await Task.detached(priority: .utility) {
            do {
                if !request {
                    guard access(path, W_OK | X_OK) == 0 else { throw CocoaError(.fileWriteNoPermission) }
                    return nil
                }
                let url = try localDirectory(path)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                // Exclusive creation: never overwrite or remove a pre-existing path.
                let probe = url.appendingPathComponent(".subler-permission-" + UUID().uuidString)
                let descriptor = open(probe.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
                guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
                defer { close(descriptor) }
                var info = stat()
                guard fstat(descriptor, &info) == 0 else { throw CocoaError(.fileWriteUnknown) }
                defer {
                    var current = stat()
                    if lstat(probe.path, &current) == 0, current.st_dev == info.st_dev, current.st_ino == info.st_ino { _ = unlink(probe.path) }
                }
                let bytes: [UInt8] = [0x53, 0x41, 0x0A]
                let count = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
                guard count == bytes.count, fsync(descriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
                // Cleanup is part of readiness, not a best-effort permission success.
                var current = stat()
                guard lstat(probe.path, &current) == 0, current.st_dev == info.st_dev, current.st_ino == info.st_ino, unlink(probe.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
                return nil
            } catch { return error.localizedDescription }
        }.value
    }
    /// Metadata only: getmntinfo(MNT_NOWAIT) never mounts or asks for credentials.
    static func mountedShare(_ scope: PermissionScope) -> String? {
        func identity(_ raw: String) -> String? {
            guard let parts = URLComponents(string: raw.hasPrefix("//") ? "smb:" + raw : raw), parts.scheme?.lowercased() == "smb", let host = parts.host, parts.password == nil else { return nil }
            let share = parts.path.split(separator: "/")
            guard share.count == 1 else { return nil }
            return "\(host.lowercased()):\(parts.port ?? 445)/\(String(share[0]).precomposedStringWithCanonicalMapping.lowercased())"
        }
        func string<T>(_ value: T) -> String {
            var value = value
            return withUnsafePointer(to: &value) { $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) } }
        }
        guard let wanted = identity(scope.serverURL) else { return nil }
        var entries: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&entries, MNT_NOWAIT)
        guard count > 0, let entries else { return nil }
        var matches: [String] = []
        for index in 0..<Int(count) {
            let info = entries[index]
            if string(info.f_fstypename) == "smbfs", identity(string(info.f_mntfromname)) == wanted { matches.append(string(info.f_mntonname)) }
        }
        return matches.first(where: { $0 == scope.expectedMountPath }) ?? matches.sorted().first
    }
}
