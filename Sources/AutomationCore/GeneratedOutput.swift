import Foundation
import CryptoKit
import Darwin

public enum GeneratedOutput {
    public static func verify(url: URL, source: URL, root: URL, jobID: UUID, expectedDigest: String? = nil) async throws -> String {
        try await Task.detached {
            guard url.isFileURL, root.isFileURL, url.pathExtension == "mp4",
                  UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                  url.deletingLastPathComponent().lastPathComponent == jobID.uuidString,
                  url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
                  url.standardizedFileURL == url.resolvingSymlinksInPath(),
                  source.resolvingSymlinksInPath() != url.resolvingSymlinksInPath() else {
                throw OutputSafetyError.invalidOwnership
            }
            let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw OutputSafetyError.invalidOwnership }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            var before = stat(), original = stat()
            guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1,
                  before.st_size > 0 else { throw OutputSafetyError.invalidOwnership }
            if stat(source.path, &original) == 0, original.st_dev == before.st_dev, original.st_ino == before.st_ino {
                throw OutputSafetyError.invalidOwnership
            }
            var hash = SHA256()
            while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
                try Task.checkCancellation(); hash.update(data: bytes)
            }
            var after = stat(), pathInfo = stat()
            guard fstat(fd, &after) == 0, lstat(url.path, &pathInfo) == 0,
                  pathInfo.st_ino == before.st_ino, pathInfo.st_dev == before.st_dev,
                  after.st_size == before.st_size, after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
                  after.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec,
                  after.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec else { throw OutputSafetyError.changed }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard expectedDigest == nil || digest == expectedDigest else { throw OutputSafetyError.changed }
            return digest
        }.value
    }
}

public enum OutputSafetyError: LocalizedError {
    case invalidOwnership, changed
    public var errorDescription: String? {
        switch self {
        case .invalidOwnership: return "Le MP4 n’est pas un fichier temporaire appartenant à cette tâche. Transfert et nettoyage refusés."
        case .changed: return "Le MP4 temporaire a changé depuis sa validation. Aucun transfert ni nettoyage autorisé."
        }
    }
}
