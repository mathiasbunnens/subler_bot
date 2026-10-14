import Foundation
import AutomationCore

extension PermissionScope {
    init(settings: AppSettings) {
        self.init(sourcePath: settings.sourcePath, temporaryPath: settings.temporaryPath, serverURL: settings.smb.serverURL, expectedMountPath: settings.smb.expectedMountPath, notifications: settings.notifications)
    }
    /// Recovered jobs retain their own output/share configuration; manual files
    /// require their source directory, not the watched folder, to be prepared.
    init(settings: AppSettings, job: MovieJob) {
        let share = job.smbConfiguration ?? settings.smb
        self.init(sourcePath: URL(fileURLWithPath: job.sourcePath).deletingLastPathComponent().path, temporaryPath: job.workRoot ?? settings.temporaryPath, serverURL: share.serverURL, expectedMountPath: share.expectedMountPath, notifications: settings.notifications)
    }
}
