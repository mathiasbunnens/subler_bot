import Foundation
import Darwin
import CryptoKit

public struct TransferProgress: Sendable {
    public let bytesCopied: Int64
    public let totalBytes: Int64
    public let bytesPerSecond: Double
    public var verificationBytes: Int64? = nil
    public var fraction: Double { totalBytes == 0 ? 1 : min(1, Double(bytesCopied) / Double(totalBytes)) }
    public var secondsRemaining: Double? { bytesPerSecond > 0 ? Double(max(0, totalBytes - (verificationBytes ?? bytesCopied))) / bytesPerSecond : nil }
}
public enum TransferError: LocalizedError {
    case conflict(URL), unsafePath, integrity, io(Int32), busy
    public var errorDescription: String? {
        switch self {
        case .conflict(let url): return "Destination already exists: \(url.path)"
        case .unsafePath: return "Unsafe transfer path or changed directory/file identity."
        case .integrity: return "Source/remote size or SHA-256 verification failed."
        case .io(let code): return "Transfer I/O failed (\(code)): \(String(cString: strerror(code)))"
        case .busy: return "A transfer to this destination is already running."
        }
    }
}

public actor TransferService {
    private var active = Set<String>()
    private let forceDirectoryPublication: Bool
    public init() { forceDirectoryPublication = false }
    // Internal fixture seam exercises SMB publication on a local filesystem.
    init(directoryPublication: Bool) { forceDirectoryPublication = directoryPublication }
    private var backups: [UUID: URL] = [:]
    public func preservedBackup(jobID: UUID) -> URL? { backups[jobID] }

    private func stable(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private func digest(_ file: FileHandle, mount: VerifiedMount, rootFD: Int32, directoryFD: Int32, movieName directoryName: String, verify: @escaping @Sendable () async throws -> Void, progress: (@Sendable (TransferProgress) async -> Void)? = nil) async throws -> SHA256.Digest {
        let before = try attributes(file.fileDescriptor)
        try file.seek(toOffset: 0)
        var hash = SHA256(), count: Int64 = 0
        let started = ContinuousClock.now
        await progress?(.init(bytesCopied: before.st_size, totalBytes: before.st_size, bytesPerSecond: 0, verificationBytes: 0))
        while let bytes = try file.read(upToCount: 8_388_608), !bytes.isEmpty {
            try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
            try checkEntry(parent: rootFD, name: directoryName, descriptor: directoryFD)
            hash.update(data: bytes); count += Int64(bytes.count)
            let elapsed = started.duration(to: .now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            await progress?(.init(bytesCopied: before.st_size, totalBytes: before.st_size, bytesPerSecond: Double(count) / max(seconds, 0.001), verificationBytes: count))
        }
        guard count == before.st_size, stable(before, try attributes(file.fileDescriptor)) else { throw TransferError.integrity }
        return hash.finalize()
    }

    private func attributes(_ descriptor: Int32) throws -> stat {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw TransferError.io(errno) }
        return info
    }
    private func checkEntry(parent: Int32, name: String, descriptor: Int32) throws {
        var entry = stat()
        let descriptorInfo = try attributes(descriptor)
        guard fstatat(parent, name, &entry, AT_SYMLINK_NOFOLLOW) == 0,
              entry.st_dev == descriptorInfo.st_dev, entry.st_ino == descriptorInfo.st_ino,
              entry.st_dev == (try attributes(parent)).st_dev,
              entry.st_mode & S_IFMT == descriptorInfo.st_mode & S_IFMT else { throw TransferError.unsafePath }
    }
    private func exists(parent: Int32, name: String) throws -> Bool {
        var info = stat()
        if fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw TransferError.unsafePath }
            return true
        }
        guard errno == ENOENT else { throw TransferError.io(errno) }
        return false
    }

    public func copy(source: URL, mount: VerifiedMount, movieName: String, jobID: UUID, replaceExisting: Bool = false, expectedDigest: String? = nil, verify: @escaping @Sendable () async throws -> Void, progress: @escaping @Sendable (TransferProgress) async -> Void) async throws -> URL {
        // Darwin smbfs normalizes names to NFD. Use that exact byte spelling for
        // every POSIX operation so synthesized path-based inodes stay consistent.
        let movieName = movieName.decomposedStringWithCanonicalMapping
        var info = statfs()
        let isSMB = statfs(mount.root.path, &info) == 0 && mountString(info.f_fstypename) == "smbfs"
        if forceDirectoryPublication || isSMB {
            return try await copyDirectory(source: source, mount: mount, movieName: movieName, jobID: jobID, replaceExisting: replaceExisting, expectedDigest: expectedDigest, verify: verify, progress: progress)
        }
        return try await copyFile(source: source, mount: mount, movieName: movieName, jobID: jobID, replaceExisting: replaceExisting, expectedDigest: expectedDigest, verify: verify, progress: progress).url
    }

    /// SMB commonly rejects RENAME_EXCL for files (ENOTSUP). Publish a whole
    /// freshly owned directory instead: POSIX rename cannot replace a nonempty
    /// destination directory. A concurrent empty directory may be replaced, but
    /// no existing film can be overwritten. Explicit replacement preserves the
    /// ENTIRE old directory in a UUID backup, including sidecars and subfolders.
    private func copyDirectory(source: URL, mount: VerifiedMount, movieName: String, jobID: UUID, replaceExisting: Bool, expectedDigest: String?, verify: @escaping @Sendable () async throws -> Void, progress: @escaping @Sendable (TransferProgress) async -> Void) async throws -> URL {
        guard source.isFileURL, mount.root.isFileURL, !movieName.isEmpty, movieName != ".", movieName != "..",
              !movieName.contains("/"), !movieName.contains("\\"), !movieName.contains(":"),
              !movieName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              movieName.utf8.count <= 180 else { throw TransferError.unsafePath }
        let key = mount.root.path + "/" + movieName
        guard active.insert(key).inserted else { throw TransferError.busy }
        defer { active.remove(key) }
        let rootFD = open(mount.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw TransferError.unsafePath }
        defer { close(rootFD) }
        try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
        let finalName = movieName + ".mp4"
        let final = mount.root.appendingPathComponent(movieName).appendingPathComponent(finalName)
        let inputFD = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard inputFD >= 0 else { throw TransferError.unsafePath }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
        defer { try? input.close() }
        let sourceInfo = try attributes(inputFD)
        guard sourceInfo.st_mode & S_IFMT == S_IFREG else { throw TransferError.unsafePath }
        var oldDirectoryFD: Int32 = -1
        var oldDirectoryInfo: stat?
        var oldFile: FileHandle?
        var oldFileInfo: stat?
        defer { if oldDirectoryFD >= 0 { close(oldDirectoryFD) }; try? oldFile?.close() }
        var entry = stat()
        if fstatat(rootFD, movieName, &entry, AT_SYMLINK_NOFOLLOW) == 0 {
            guard entry.st_mode & S_IFMT == S_IFDIR else { throw TransferError.unsafePath }
            oldDirectoryFD = openat(rootFD, movieName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard oldDirectoryFD >= 0 else { throw TransferError.unsafePath }
            try checkEntry(parent: rootFD, name: movieName, descriptor: oldDirectoryFD)
            oldDirectoryInfo = try attributes(oldDirectoryFD)
            if try exists(parent: oldDirectoryFD, name: finalName) {
                let fd = openat(oldDirectoryFD, finalName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw TransferError.unsafePath }
                let old = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                oldFile = old; oldFileInfo = try attributes(fd)
                try checkEntry(parent: oldDirectoryFD, name: finalName, descriptor: fd)
                let sourceHash = try await digest(input, mount: mount, rootFD: rootFD, directoryFD: oldDirectoryFD, movieName: movieName, verify: verify)
                guard expectedDigest == nil || sourceHash.map({ String(format: "%02x", $0) }).joined() == expectedDigest else { throw TransferError.integrity }
                let oldHash = try await digest(old, mount: mount, rootFD: rootFD, directoryFD: oldDirectoryFD, movieName: movieName, verify: verify)
                try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
                try checkEntry(parent: rootFD, name: movieName, descriptor: oldDirectoryFD)
                try checkEntry(parent: oldDirectoryFD, name: finalName, descriptor: fd)
                guard stable(sourceInfo, try attributes(inputFD)), stable(oldFileInfo!, try attributes(fd)) else { throw TransferError.integrity }
                if sourceHash == oldHash {
                    await progress(.init(bytesCopied: sourceInfo.st_size, totalBytes: sourceInfo.st_size, bytesPerSecond: 0))
                    return final
                }
            }
            guard replaceExisting else { throw TransferError.conflict(final) }
        } else if errno != ENOENT { throw TransferError.io(errno) }

        // mkdir EXCLUSIVE ownership: never reuse or truncate a pre-existing stage.
        // Failed/cancelled stages remain UUID-labelled for recovery, not recursively
        // removed (a foreign child could have appeared). No public folder is made.
        let stageName = ".subler-" + jobID.uuidString + "-" + UUID().uuidString + ".staging"
        guard mkdirat(rootFD, stageName, 0o700) == 0 else { throw TransferError.io(errno) }
        let stageFD = openat(rootFD, stageName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stageFD >= 0 else { throw TransferError.unsafePath }
        defer { close(stageFD) }
        try checkEntry(parent: rootFD, name: stageName, descriptor: stageFD)
        let copied = try await copyFile(source: source, mount: mount, movieName: movieName, storageName: stageName, privatePublication: true, jobID: jobID, expectedDigest: expectedDigest, verify: verify, progress: progress)
        try checkEntry(parent: rootFD, name: stageName, descriptor: stageFD)
        // Keep the same verified descriptor open through directory publication.
        // smbfs can update server timestamps on close/reopen; do not discard
        // the identity binding or trigger extra rereads just to reopen it.
        guard let stagedFile = copied.file else { throw TransferError.unsafePath }
        let stagedFD = stagedFile.fileDescriptor
        defer { try? stagedFile.close() }
        let stagedInfo = try attributes(stagedFD)
        // Reuse copyFile's complete SHA256 proof, bound to an unchanged file.
        guard stable(copied.info, stagedInfo), stable(sourceInfo, try attributes(inputFD)) else { throw TransferError.integrity }
        guard stagedInfo.st_mode & S_IFMT == S_IFREG, stagedInfo.st_nlink == 1 else { throw TransferError.unsafePath }
        var backupName: String?
        do {
            try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
            try checkEntry(parent: rootFD, name: stageName, descriptor: stageFD)
            try checkEntry(parent: stageFD, name: finalName, descriptor: stagedFD)
            guard stable(stagedInfo, try attributes(stagedFD)), stable(sourceInfo, try attributes(inputFD)) else { throw TransferError.integrity }
            if let captured = oldDirectoryInfo {
                try checkEntry(parent: rootFD, name: movieName, descriptor: oldDirectoryFD)
                guard stable(captured, try attributes(oldDirectoryFD)) else { throw TransferError.unsafePath }
                if let old = oldFile, let info = oldFileInfo {
                    try checkEntry(parent: oldDirectoryFD, name: finalName, descriptor: old.fileDescriptor)
                    guard stable(info, try attributes(old.fileDescriptor)) else { throw TransferError.integrity }
                }
                let name = ".subler-" + UUID().uuidString + ".backup"
                // Reserve a UUID empty directory, then rename only over our own
                // empty reservation. POSIX refuses any nonempty competing target.
                guard mkdirat(rootFD, name, 0o700) == 0 else { throw TransferError.io(errno) }
                let reservationFD = openat(rootFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard reservationFD >= 0 else { throw TransferError.unsafePath }
                defer { close(reservationFD) }
                try checkEntry(parent: rootFD, name: name, descriptor: reservationFD)
                try checkEntry(parent: rootFD, name: movieName, descriptor: oldDirectoryFD)
                guard renameat(rootFD, movieName, rootFD, name) == 0 else { throw TransferError.io(errno) }
                backupName = name
                backups[jobID] = mount.root.appendingPathComponent(name)
                try checkEntry(parent: rootFD, name: name, descriptor: oldDirectoryFD)
            } else {
                // Refuse even an empty pre-existing directory at the final check.
                // The unavoidable rename race can only replace an empty directory.
                var target = stat()
                if fstatat(rootFD, movieName, &target, AT_SYMLINK_NOFOLLOW) == 0 { throw TransferError.conflict(final) }
                guard errno == ENOENT else { throw TransferError.io(errno) }
            }
            try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
            try checkEntry(parent: rootFD, name: stageName, descriptor: stageFD)
            try checkEntry(parent: stageFD, name: finalName, descriptor: stagedFD)
            if let name = backupName { try checkEntry(parent: rootFD, name: name, descriptor: oldDirectoryFD) }
            guard stable(stagedInfo, try attributes(stagedFD)), stable(sourceInfo, try attributes(inputFD)) else { throw TransferError.integrity }
            guard renameat(rootFD, stageName, rootFD, movieName) == 0 else {
                if errno == EEXIST || errno == ENOTEMPTY || errno == ENOTDIR { throw TransferError.conflict(final) }
                throw TransferError.io(errno)
            }
        } catch {
            if let name = backupName,
               (try? mount.revalidate(descriptor: rootFD)) != nil,
               (try? checkEntry(parent: rootFD, name: name, descriptor: oldDirectoryFD)) != nil,
               renameat(rootFD, name, rootFD, movieName) == 0 {
                backups.removeValue(forKey: jobID)
            }
            // Failed rollback leaves the entire original directory discoverable.
            // Never remove a competitor: a nonempty target makes rollback fail.
            throw error
        }
        _ = fsync(rootFD)
        try mount.revalidate(descriptor: rootFD)
        try checkEntry(parent: rootFD, name: movieName, descriptor: stageFD)
        try checkEntry(parent: stageFD, name: finalName, descriptor: stagedFD)
        let publishedInfo = try attributes(stagedFD)
        // Directory rename can change synthetic inode IDs, not file contents.
        // Keep the verified descriptor open and require unchanged content stats.
        guard publishedInfo.st_size == stagedInfo.st_size,
              publishedInfo.st_mtimespec.tv_sec == stagedInfo.st_mtimespec.tv_sec,
              publishedInfo.st_mtimespec.tv_nsec == stagedInfo.st_mtimespec.tv_nsec,
              publishedInfo.st_ctimespec.tv_sec == stagedInfo.st_ctimespec.tv_sec,
              publishedInfo.st_ctimespec.tv_nsec == stagedInfo.st_ctimespec.tv_nsec,
              stable(sourceInfo, try attributes(inputFD)) else { throw TransferError.integrity }
        try checkEntry(parent: rootFD, name: movieName, descriptor: stageFD)
        try checkEntry(parent: stageFD, name: finalName, descriptor: stagedFD)
        return final
    }

    private func copyFile(source: URL, mount: VerifiedMount, movieName: String, storageName: String? = nil, privatePublication: Bool = false, jobID: UUID, replaceExisting: Bool = false, expectedDigest: String? = nil, verify: @escaping @Sendable () async throws -> Void, progress: @escaping @Sendable (TransferProgress) async -> Void) async throws -> (url: URL, info: stat, file: FileHandle?) {
        let directoryName = storageName ?? movieName
        guard source.isFileURL, mount.root.isFileURL, !movieName.isEmpty, movieName != ".", movieName != "..",
              !movieName.contains("/"), !movieName.contains("\\"), !movieName.contains(":"),
              !movieName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              movieName.utf8.count <= 180 else { throw TransferError.unsafePath }
        let key = mount.root.path + "/" + directoryName
        guard active.insert(key).inserted else { throw TransferError.busy }
        defer { active.remove(key) }
        let rootFD = open(mount.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw TransferError.unsafePath }
        defer { close(rootFD) }
        try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
        if mkdirat(rootFD, directoryName, 0o755) != 0, errno != EEXIST { throw TransferError.io(errno) }
        let directoryFD = openat(rootFD, directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw TransferError.unsafePath }
        defer { close(directoryFD) }
        try checkEntry(parent: rootFD, name: directoryName, descriptor: directoryFD)
        let finalName = movieName + ".mp4"
        let final = mount.root.appendingPathComponent(directoryName).appendingPathComponent(finalName)
        let existing = try exists(parent: directoryFD, name: finalName)
        let inputFD = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard inputFD >= 0 else { throw TransferError.io(errno) }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
        defer { try? input.close() }
        let original = try attributes(inputFD)
        guard original.st_mode & S_IFMT == S_IFREG else { throw TransferError.unsafePath }
        let total = original.st_size
        var oldFile: FileHandle?
        var oldInfo: stat?
        defer { try? oldFile?.close() }
        if existing {
            let descriptor = openat(directoryFD, finalName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw TransferError.unsafePath }
            let old = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            oldFile = old; oldInfo = try attributes(descriptor)
            guard oldInfo!.st_mode & S_IFMT == S_IFREG, oldInfo!.st_nlink == 1 else { throw TransferError.unsafePath }
            try checkEntry(parent: directoryFD, name: finalName, descriptor: descriptor)
            if oldInfo!.st_size == total {
                let sourceHash = try await digest(input, mount: mount, rootFD: rootFD, directoryFD: directoryFD, movieName: directoryName, verify: verify)
                guard expectedDigest == nil || sourceHash.map({ String(format: "%02x", $0) }).joined() == expectedDigest else { throw TransferError.integrity }
                let finalHash = try await digest(old, mount: mount, rootFD: rootFD, directoryFD: directoryFD, movieName: directoryName, verify: verify)
                try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
                try checkEntry(parent: rootFD, name: directoryName, descriptor: directoryFD)
                try checkEntry(parent: directoryFD, name: finalName, descriptor: descriptor)
                guard stable(original, try attributes(inputFD)), stable(oldInfo!, try attributes(descriptor)) else { throw TransferError.integrity }
                if sourceHash == finalHash {
                    await progress(.init(bytesCopied: total, totalBytes: total, bytesPerSecond: 0))
                    return (final, try attributes(descriptor), nil)
                }
                try input.seek(toOffset: 0)
            }
            guard replaceExisting else { throw TransferError.conflict(final) }
        }
        let partName = finalName + "." + jobID.uuidString + ".part"
        // Restart only this job's own partial; lock and validate before truncation.
        var partFD = openat(directoryFD, partName, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if partFD < 0, errno == EEXIST { partFD = openat(directoryFD, partName, O_RDWR | O_NOFOLLOW | O_CLOEXEC) }
        guard partFD >= 0 else { throw TransferError.unsafePath }
        let output = FileHandle(fileDescriptor: partFD, closeOnDealloc: true)
        var transferredHandle = false
        defer { if !transferredHandle { try? output.close() } }
        let partInfo = try attributes(partFD)
        guard partInfo.st_mode & S_IFMT == S_IFREG, partInfo.st_nlink == 1,
              !(partInfo.st_dev == original.st_dev && partInfo.st_ino == original.st_ino) else { throw TransferError.unsafePath }
        guard flock(partFD, LOCK_EX | LOCK_NB) == 0 else { throw TransferError.busy }
        try checkEntry(parent: directoryFD, name: partName, descriptor: partFD)
        try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
        try checkEntry(parent: rootFD, name: directoryName, descriptor: directoryFD)
        guard ftruncate(partFD, 0) == 0 else { throw TransferError.io(errno) }
        var copied: Int64 = 0
        var hash = SHA256()
        let start = ContinuousClock.now
        await progress(.init(bytesCopied: 0, totalBytes: total, bytesPerSecond: 0))
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
            try checkEntry(parent: rootFD, name: directoryName, descriptor: directoryFD)
            try checkEntry(parent: directoryFD, name: partName, descriptor: partFD)
            try output.write(contentsOf: data); hash.update(data: data); copied += Int64(data.count)
            let duration = start.duration(to: .now).components
            let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            await progress(.init(bytesCopied: copied, totalBytes: total, bytesPerSecond: Double(copied) / max(elapsed, 0.001)))
        }
        try output.synchronize()
        let after = try attributes(inputFD)
        guard copied == total, after.st_size == original.st_size,
              after.st_mtimespec.tv_sec == original.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == original.st_mtimespec.tv_nsec else { throw TransferError.integrity }
        let verifiedPart = try attributes(partFD)
        let sourceDigest = hash.finalize()
        guard expectedDigest == nil || sourceDigest.map({ String(format: "%02x", $0) }).joined() == expectedDigest else { throw TransferError.integrity }
        if !privatePublication {
            let actual = try await digest(output, mount: mount, rootFD: rootFD, directoryFD: directoryFD, movieName: directoryName, verify: verify, progress: progress)
            guard actual == sourceDigest, stable(verifiedPart, try attributes(partFD)) else { throw TransferError.integrity }
        }
        try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
        try checkEntry(parent: rootFD, name: directoryName, descriptor: directoryFD)
        try checkEntry(parent: directoryFD, name: partName, descriptor: partFD)
        if !privatePublication { try output.close() }
        var backupName: String?
        if let old = oldFile, let oldInfo {
            try checkEntry(parent: directoryFD, name: finalName, descriptor: old.fileDescriptor)
            guard stable(oldInfo, try attributes(old.fileDescriptor)) else { throw TransferError.conflict(final) }
            let name = finalName + "." + UUID().uuidString + ".backup"
            guard renameatx_np(directoryFD, finalName, directoryFD, name, UInt32(RENAME_EXCL)) == 0 else { throw TransferError.io(errno) }
            backupName = name
            backups[jobID] = final.deletingLastPathComponent().appendingPathComponent(name)
        }
        do {
            // Verify after the backup move too; on failure rollback only via NOREPLACE.
            try Task.checkCancellation(); try await verify(); try mount.revalidate(descriptor: rootFD)
            try checkEntry(parent: rootFD, name: directoryName, descriptor: directoryFD)
            if let name = backupName, let old = oldFile { try checkEntry(parent: directoryFD, name: name, descriptor: old.fileDescriptor) }
            // Part was closed for durable publication, so bind its identity explicitly.
            var currentPart = stat()
            guard fstatat(directoryFD, partName, &currentPart, AT_SYMLINK_NOFOLLOW) == 0,
                  currentPart.st_ino == partInfo.st_ino, currentPart.st_dev == partInfo.st_dev,
                  currentPart.st_mode & S_IFMT == S_IFREG, currentPart.st_nlink == 1, currentPart.st_size == total else { throw TransferError.unsafePath }
            guard stable(verifiedPart, currentPart), stable(original, try attributes(inputFD)) else { throw TransferError.integrity }
            // Ordinary file rename is restricted to a freshly mkdir'd UUID staging
            // directory, never the public movie directory on SMB.
            if privatePublication, try exists(parent: directoryFD, name: finalName) { throw TransferError.conflict(final) }
            let result = privatePublication
                ? renameat(directoryFD, partName, directoryFD, finalName)
                : renameatx_np(directoryFD, partName, directoryFD, finalName, UInt32(RENAME_EXCL))
            guard result == 0 else {
                if errno == EEXIST { throw TransferError.conflict(final) }
                throw TransferError.io(errno)
            }
        } catch {
            if let name = backupName {
                // Never delete a competing final or write into an unverified mount.
                if let old = oldFile, (try? mount.revalidate(descriptor: rootFD)) != nil,
                   (try? checkEntry(parent: directoryFD, name: name, descriptor: old.fileDescriptor)) != nil,
                   (try? checkEntry(parent: rootFD, name: directoryName, descriptor: directoryFD)) != nil,
                   renameatx_np(directoryFD, name, directoryFD, finalName, UInt32(RENAME_EXCL)) == 0 { backups.removeValue(forKey: jobID) }
                // If rollback cannot succeed, the backup remains discoverable via
                // preservedBackup(jobID:) and its UUID filename. No original is lost.
            }
            throw error
        }
        // Directory fsync is not supported by every SMB server; file synchronization
        // and atomic exclusive publication above are mandatory and fail closed.
        _ = fsync(directoryFD)
        try mount.revalidate(descriptor: rootFD)
        try checkEntry(parent: rootFD, name: directoryName, descriptor: directoryFD)
        var published = stat()
        if privatePublication {
            // smbfs may synthesize path-based inode numbers: our own rename
            // updates fstat on the STILL OPEN descriptor as well as the entry.
            // Rebind to that descriptor and hash once; never accept a different
            // path identity during copying or between unrelated operations.
            try checkEntry(parent: directoryFD, name: finalName, descriptor: partFD)
            let verified = try attributes(partFD)
            let readback = try await digest(output, mount: mount, rootFD: rootFD, directoryFD: directoryFD, movieName: directoryName, verify: verify, progress: progress)
            guard readback == sourceDigest, stable(verified, try attributes(partFD)), stable(original, try attributes(inputFD)) else { throw TransferError.integrity }
            try checkEntry(parent: directoryFD, name: finalName, descriptor: partFD)
            published = verified
        } else {
            guard fstatat(directoryFD, finalName, &published, AT_SYMLINK_NOFOLLOW) == 0,
                  published.st_ino == verifiedPart.st_ino, published.st_dev == verifiedPart.st_dev,
                  published.st_mode & S_IFMT == S_IFREG, published.st_nlink == 1, published.st_size == total else { throw TransferError.integrity }
        }
        transferredHandle = privatePublication
        return (final, published, privatePublication ? output : nil)
    }
}
