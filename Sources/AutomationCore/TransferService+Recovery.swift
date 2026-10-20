import Foundation
import Darwin
import CryptoKit

extension TransferService {
    /// Recovery is read-only: intent never authorizes another publication.
    /// Incomplete transactions remain available for explicit intervention.
    public func recoverReplacement(source: URL, mount: VerifiedMount, movieName: String, jobID: UUID,
                                   expectedDigest: String, verify: @escaping @Sendable () async throws -> Void,
                                   progress: @escaping @Sendable (TransferProgress) async -> Void) async throws -> URL? {
        let name = movieName.decomposedStringWithCanonicalMapping
        let current = try DestinationSnapshot.capture(mount: mount, movieName: name)
        let key = mount.root.path + "/" + name
        guard active.insert(key).inserted else { throw TransferError.busy }
        defer { active.remove(key) }
        let root = open(mount.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw TransferError.unsafePath }
        defer { close(root) }
        try mount.revalidate(descriptor: root)
        var directoryEntry = stat()
        if fstatat(root, name, &directoryEntry, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw TransferError.io(errno) }
            return nil
        }
        let directory = openat(root, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw TransferError.unsafePath }
        defer { close(directory) }
        try checkEntry(parent: root, name: name, descriptor: directory)
        let folder = mount.root.appendingPathComponent(name)
        let prefix = ".subler-replace-" + jobID.uuidString + "-"
        for journalName in try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            where journalName.hasPrefix(prefix) && journalName.hasSuffix(".json") {
            try Task.checkCancellation(); try await verify()
            let fd = try ReplacementTransaction.openRegular(parent: directory, name: journalName)
            let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? file.close() }
            let info = try attributes(fd)
            guard info.st_size <= 65_536 else { throw TransferError.unsafePath }
            guard let data = try file.read(upToCount: 65_537),
                  let transaction = try? JSONDecoder().decode(ReplacementTransaction.self, from: data) else { continue }
            let token = String(journalName.dropFirst(prefix.count).dropLast(5))
            guard UUID(uuidString: token)?.uuidString == token,
                  transaction.jobID == jobID, transaction.sourcePath == source.path,
                  transaction.digest == expectedDigest, transaction.journalName == journalName,
                  transaction.stageName == prefix + token + ".new",
                  transaction.backupName == prefix + token + ".backup",
                  try transaction.destination.matchesContainer(mount: mount, movieName: name, root: root, directory: attributes(directory)) else { continue }
            // A crash before the backup exists is not a committed transaction.
            var entry = stat()
            if fstatat(directory, transaction.backupName, &entry, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else { throw TransferError.io(errno) }
                continue
            }
            let backupFD = try ReplacementTransaction.openRegular(parent: directory, name: transaction.backupName)
            defer { close(backupFD) }
            let backup = FileHandle(fileDescriptor: backupFD, closeOnDealloc: false)
            let backupHash = try await digest(backup, mount: mount, rootFD: root, directoryFD: directory, movieName: name, verify: verify)
            guard backupHash.map({ String(format: "%02x", $0) }).joined() == transaction.oldDigest else { throw TransferError.integrity }
            try checkEntry(parent: directory, name: transaction.backupName, descriptor: backupFD)
            backups[jobID] = folder.appendingPathComponent(transaction.backupName)
            guard let current else { throw TransferError.recoveryRequired(folder) }
            if fstatat(directory, transaction.backupName + ".native", &entry, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else { throw TransferError.io(errno) }
                continue
            }
            let exchangedFD = try ReplacementTransaction.openRegular(parent: directory, name: transaction.backupName + ".native")
            defer { close(exchangedFD) }
            let exchanged = FileHandle(fileDescriptor: exchangedFD, closeOnDealloc: false)
            let exchangedHash = try await digest(exchanged, mount: mount, rootFD: root, directoryFD: directory, movieName: name, verify: verify)
            guard exchangedHash.map({ String(format: "%02x", $0) }).joined() == transaction.oldDigest else { throw TransferError.recoveryRequired(folder) }
            let backupInfo = try attributes(backupFD), exchangedInfo = try attributes(exchangedFD)
            let finalFD = try ReplacementTransaction.openRegular(parent: directory, name: name + ".mp4")
            defer { close(finalFD) }
            let final = FileHandle(fileDescriptor: finalFD, closeOnDealloc: false)
            let finalHash = try await digest(final, mount: mount, rootFD: root, directoryFD: directory, movieName: name, verify: verify, progress: progress)
            try current.requireUnchanged(mount: mount, movieName: name)
            try checkEntry(parent: directory, name: name + ".mp4", descriptor: finalFD)
            try checkEntry(parent: directory, name: transaction.backupName, descriptor: backupFD)
            try checkEntry(parent: directory, name: transaction.backupName + ".native", descriptor: exchangedFD)
            guard stable(backupInfo, try attributes(backupFD)), stable(exchangedInfo, try attributes(exchangedFD)) else { throw TransferError.integrity }
            if finalHash.map({ String(format: "%02x", $0) }).joined() == expectedDigest {
                return folder.appendingPathComponent(name + ".mp4")
            }
        }
        return nil
    }
}
