import Foundation
import Darwin
import NetFS

public struct SMBConfiguration: Codable, Equatable, Sendable {
    public var serverURL: String
    public var username: String
    public var expectedMountPath: String
    /// Empty by default: no personal server or account is baked into the app.
    /// A first installation uses `firstLaunchDefault()` instead.
    public init(serverURL: String = "", username: String = "", expectedMountPath: String = "") {
        self.serverURL = serverURL; self.username = username; self.expectedMountPath = expectedMountPath
    }

    /// A server address has been entered (it may still be unreachable).
    public var isConfigured: Bool { !serverURL.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The job's snapshot wins once a server exists; a film converted before any
    /// server was configured uses the server entered since.
    public static func effective(job: SMBConfiguration?, current: SMBConfiguration) -> SMBConfiguration {
        if let job, job.isConfigured { return job }
        return current
    }

    /// Builds a configuration from an existing smbfs mount, e.g.
    /// `//alice@nas.local/Films` mounted on `/Volumes/Films`. Never contains a password.
    public static func fromMount(origin: String, mountPoint: String, fallbackUser: String) -> SMBConfiguration? {
        guard let parts = URLComponents(string: origin.hasPrefix("//") ? "smb:" + origin : origin),
              parts.scheme?.lowercased() == "smb", let host = parts.host, !host.isEmpty else { return nil }
        let shares = parts.path.split(separator: "/", omittingEmptySubsequences: true)
        guard shares.count == 1 else { return nil }
        var url = URLComponents()
        url.scheme = "smb"; url.host = host; url.port = parts.port
        url.path = "/" + String(shares[0])
        guard let server = url.string else { return nil }
        // Mount strings may carry "DOMAIN;user": keep only the account name.
        let user = parts.user.flatMap { $0.split(separator: ";").last.map(String.init) }
        return SMBConfiguration(serverURL: server, username: (user?.isEmpty == false ? user! : fallbackUser), expectedMountPath: mountPoint)
    }

    /// First installation: reuse an SMB share already mounted in the Finder, otherwise
    /// leave the server empty (to configure in Réglages) with the macOS account name as user.
    public static func firstLaunchDefault(userName: String = NSUserName()) -> SMBConfiguration {
        for (origin, mountPoint) in mountedSMBShares() {
            if let detected = fromMount(origin: origin, mountPoint: mountPoint, fallbackUser: userName) { return detected }
        }
        return SMBConfiguration(username: userName)
    }

    /// Metadata only (getmntinfo MNT_NOWAIT): never mounts or prompts.
    public static func mountedSMBShares() -> [(origin: String, mountPoint: String)] {
        var entries: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&entries, MNT_NOWAIT)
        guard count > 0, let entries else { return [] }
        return (0..<Int(count)).compactMap { index in
            let info = entries[index]
            guard mountString(info.f_fstypename) == "smbfs" else { return nil }
            return (mountString(info.f_mntfromname), mountString(info.f_mntonname))
        }
    }
}
public enum SMBError: LocalizedError {
    case unavailable, invalidConfiguration, mountFailed(Int32)
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "The configured SMB share is not mounted."
        case .invalidConfiguration: return "Invalid SMB configuration (use a password-free SMB share URL)."
        case .mountFailed(let code): return "Connexion SMB impossible (\(code)). Vérifiez le serveur et les identifiants, puis utilisez Connecter… pour réessayer."
        }
    }
}

func mountString<T>(_ value: T) -> String {
    var value = value
    return withUnsafePointer(to: &value) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
    }
}

public struct VerifiedMount: Sendable {
    public let root: URL
    public let origin: String
    // No public initializer or production fallback to a local directory.
    private let isFixture: Bool
    fileprivate init(root: URL, origin: String, isFixture: Bool = false) {
        self.root = root; self.origin = origin; self.isFixture = isFixture
    }
    // Explicit internal-only test seam; normal clients cannot construct this.
    static func fixture(root: URL) -> VerifiedMount { .init(root: root, origin: "test-fixture", isFixture: true) }

    func revalidate(descriptor: Int32) throws {
        var descriptorInfo = stat(), pathInfo = stat()
        guard fstat(descriptor, &descriptorInfo) == 0, lstat(root.path, &pathInfo) == 0,
              descriptorInfo.st_dev == pathInfo.st_dev, descriptorInfo.st_ino == pathInfo.st_ino,
              pathInfo.st_mode & S_IFMT == S_IFDIR else { throw SMBError.unavailable }
        if isFixture { return }
        var info = statfs()
        guard fstatfs(descriptor, &info) == 0,
              mountString(info.f_fstypename) == "smbfs",
              SMBService.sameShare(mountString(info.f_mntfromname), origin),
              URL(fileURLWithPath: mountString(info.f_mntonname)).standardizedFileURL == root.standardizedFileURL else { throw SMBError.unavailable }
    }
}

public actor SMBService {
    public init() {}

    private nonisolated static func identity(_ string: String) -> (String, String, Int)? {
        let normalized = string.hasPrefix("//") ? "smb:" + string : string
        guard let parts = URLComponents(string: normalized), parts.scheme?.lowercased() == "smb",
              let host = parts.host, !host.isEmpty, parts.query == nil, parts.fragment == nil else { return nil }
        let shares = parts.path.split(separator: "/", omittingEmptySubsequences: true)
        guard shares.count == 1, shares[0] != ".", shares[0] != "..", !shares[0].contains("\\"), !shares[0].contains("\0") else { return nil }
        return (host.lowercased(), String(shares[0]).precomposedStringWithCanonicalMapping.lowercased(), parts.port ?? 445)
    }
    nonisolated static func sameShare(_ a: String, _ b: String) -> Bool {
        guard let a = identity(a), let b = identity(b) else { return false }
        return a == b
    }
    private nonisolated static func validate(_ configuration: SMBConfiguration) throws -> URL {
        guard identity(configuration.serverURL) != nil,
              let parts = URLComponents(string: configuration.serverURL), parts.password == nil,
              let url = parts.url, configuration.serverURL.lowercased().hasPrefix("smb://"),
              !configuration.username.isEmpty, !configuration.username.contains("\0"),
              configuration.expectedMountPath.hasPrefix("/"), !configuration.expectedMountPath.contains("\0") else { throw SMBError.invalidConfiguration }
        return url
    }
    public func mountedShare(configuration: SMBConfiguration) throws -> VerifiedMount {
        _ = try Self.validate(configuration)
        var entries: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&entries, MNT_NOWAIT)
        guard count > 0, let entries else { throw SMBError.unavailable }
        var candidates: [VerifiedMount] = []
        for index in 0..<Int(count) {
            let info = entries[index]
            let origin = mountString(info.f_mntfromname)
            guard mountString(info.f_fstypename) == "smbfs", Self.sameShare(origin, configuration.serverURL) else { continue }
            candidates.append(.init(root: URL(fileURLWithPath: mountString(info.f_mntonname)), origin: origin))
        }
        candidates.sort { ($0.root.path == configuration.expectedMountPath ? 0 : 1) < ($1.root.path == configuration.expectedMountPath ? 0 : 1) }
        for candidate in candidates {
            let descriptor = open(candidate.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { continue }
            defer { close(descriptor) }
            if (try? candidate.revalidate(descriptor: descriptor)) != nil { return candidate }
        }
        throw SMBError.unavailable
    }
    nonisolated static func openOptions(allowAuthenticationUI: Bool) -> NSMutableDictionary {
        NSMutableDictionary(dictionary: ["UIOption": allowAuthenticationUI ? "AllowUI" : "NoUI"])
    }

    public func reconnect(configuration: SMBConfiguration, allowAuthenticationUI: Bool = false) async throws -> VerifiedMount {
        let url = try Self.validate(configuration)
        if let mounted = try? mountedShare(configuration: configuration) { return mounted }
        try Task.checkCancellation()
        // NetAuth owns credentials and the optional native authentication dialog.
        // Never receive a password, force a session, unmount or create /Volumes paths.
        let status = await Task.detached(priority: .utility) {
            let options = Self.openOptions(allowAuthenticationUI: allowAuthenticationUI)
            let mountOptions = NSMutableDictionary(dictionary: ["SoftMount": true, "AllowSubMounts": false])
            var points: Unmanaged<CFArray>?
            let result = NetFSMountURLSync(url as CFURL, nil, configuration.username as CFString, nil, options, mountOptions, &points)
            _ = points?.takeRetainedValue()
            return result
        }.value
        try Task.checkCancellation()
        guard status == 0 else { throw SMBError.mountFailed(status) }
        return try mountedShare(configuration: configuration)
    }
}
