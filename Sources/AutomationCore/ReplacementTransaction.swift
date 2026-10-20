import Foundation
import Darwin


/// Immutable intent is synchronized before the native replacement begins. The
/// backup is NEVER deleted automatically, including after a successful readback.
/// On SMB neither Foundation nor fsync is a promise of server crash atomicity.
struct ReplacementTransaction: Codable, Sendable {
    let jobID: UUID
    let destination: DestinationSnapshot
    let sourcePath: String
    let digest: String
    let oldDigest: String
    let stageName: String
    let backupName: String
    let journalName: String

    static func openRegular(parent: Int32, name: String) throws -> Int32 {
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw TransferError.unsafePath }
        var info = stat(), entry = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              fstatat(parent, name, &entry, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_dev == entry.st_dev, info.st_ino == entry.st_ino else {
            close(fd); throw TransferError.unsafePath
        }
        return fd
    }
}
