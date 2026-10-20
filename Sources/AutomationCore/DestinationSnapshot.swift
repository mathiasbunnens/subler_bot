import Foundation
import Darwin

/// Consent describes one exact published version, not a path-only overwrite flag.
public struct DestinationSnapshot: Codable, Equatable, Sendable {
    public let path: String
    public let size: Int64
    public let modified: Date
    private let origin: String
    private let identities: [String]

    private static func identity(_ value: stat) -> String {
        "\(value.st_dev)|\(value.st_ino)|\(value.st_size)|\(value.st_mtimespec.tv_sec)|\(value.st_mtimespec.tv_nsec)|\(value.st_ctimespec.tv_sec)|\(value.st_ctimespec.tv_nsec)"
    }
    private static func rootIdentity(_ descriptor: Int32) throws -> String {
        var file = stat(), filesystem = statfs()
        guard fstat(descriptor, &file) == 0, fstatfs(descriptor, &filesystem) == 0 else { throw TransferError.io(errno) }
        return "\(file.st_dev)|\(file.st_ino)|\(filesystem.f_fsid.val.0)|\(filesystem.f_fsid.val.1)|\(mountString(filesystem.f_mntonname))"
    }
    public static func capture(mount: VerifiedMount, movieName: String) throws -> Self? {
        let name = movieName.decomposedStringWithCanonicalMapping
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains(":"),
              name.utf8.count <= 180, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw TransferError.unsafePath }
        let root = open(mount.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw TransferError.unsafePath }
        defer { close(root) }
        try mount.revalidate(descriptor: root)
        var directoryInfo = stat()
        if fstatat(root, name, &directoryInfo, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw TransferError.io(errno) }
            return nil
        }
        guard directoryInfo.st_mode & S_IFMT == S_IFDIR else { throw TransferError.unsafePath }
        let directory = openat(root, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw TransferError.unsafePath }
        defer { close(directory) }
        var heldDirectory = stat(), entry = stat()
        guard fstat(directory, &heldDirectory) == 0, identity(directoryInfo) == identity(heldDirectory),
              heldDirectory.st_dev == directoryInfo.st_dev else { throw TransferError.unsafePath }
        let filename = name + ".mp4"
        if fstatat(directory, filename, &entry, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw TransferError.io(errno) }
            return nil
        }
        guard entry.st_mode & S_IFMT == S_IFREG, entry.st_nlink == 1, entry.st_dev == heldDirectory.st_dev else { throw TransferError.unsafePath }
        let file = openat(directory, filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw TransferError.unsafePath }
        defer { close(file) }
        var held = stat(), rootInfo = stat(), currentDirectory = stat(), currentFile = stat()
        guard fstat(file, &held) == 0, identity(held) == identity(entry), fstat(root, &rootInfo) == 0,
              rootInfo.st_dev == held.st_dev,
              fstatat(root, name, &currentDirectory, AT_SYMLINK_NOFOLLOW) == 0, identity(currentDirectory) == identity(heldDirectory),
              fstatat(directory, filename, &currentFile, AT_SYMLINK_NOFOLLOW) == 0, identity(currentFile) == identity(held) else { throw TransferError.unsafePath }
        try mount.revalidate(descriptor: root)
        // Root directory timestamps change during staging; bind only its device/inode.
        return Self(path: mount.root.appendingPathComponent(name).appendingPathComponent(filename).path,
                    size: held.st_size, modified: Date(timeIntervalSince1970: Double(held.st_mtimespec.tv_sec) + Double(held.st_mtimespec.tv_nsec) / 1e9),
                    origin: mount.origin, identities: [try rootIdentity(root), "\(heldDirectory.st_dev)|\(heldDirectory.st_ino)", identity(held)])
    }
    public func requireUnchanged(mount: VerifiedMount, movieName: String) throws {
        guard try Self.capture(mount: mount, movieName: movieName) == self else { throw TransferError.destinationChanged }
    }
    func matchesContainer(mount: VerifiedMount, movieName: String, root: Int32, directory: stat) throws -> Bool {
        let mountedRoot = try Self.rootIdentity(root)
        return path == mount.root.appendingPathComponent(movieName).appendingPathComponent(movieName + ".mp4").path &&
        origin == mount.origin && Array(identities.prefix(2)) == [mountedRoot, "\(directory.st_dev)|\(directory.st_ino)"]
    }
    public var summary: String {
        "Existe déjà sur serveur : \(path)\n\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) · modifié le \(modified.formatted(date: .numeric, time: .standard))"
    }
}
