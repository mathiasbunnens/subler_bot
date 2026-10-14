// Compile fixture only: deliberately no live queue, NSApplication or windows.
import SwiftUI
import AutomationCore

@MainActor final class JobQueueService: ObservableObject {
    @Published var settings = AppSettings()
    @Published var message: String?
    let permissions = PermissionPreparationService.shared
    func preparePermissions() { Task { await permissions.prepare(PermissionScope(settings: settings)) } }
    func applySettings(_ draft: AppSettings) { settings = draft }
}

@main struct PermissionUIFixture {
    @MainActor static func main() async {
        let queue = JobQueueService()
        let settings = SettingsView(queue: queue)
        _ = settings.body // Typechecks actual Settings content without presenting a native window.
        var job = MovieJob(sourcePath: "/FixtureManual/film.mkv", fingerprint: "fixture")
        job.workRoot = "/FixtureRecoveredWork"
        job.smbConfiguration = SMBConfiguration(serverURL: "smb://fixture.invalid/Old", expectedMountPath: "/Volumes/Old")
        let scope = PermissionScope(settings: queue.settings, job: job)
        precondition(scope.sourcePath == "/FixtureManual")
        precondition(scope.temporaryPath == "/FixtureRecoveredWork")
        precondition(scope.serverURL == "smb://fixture.invalid/Old")
        print("PASS: actual Settings/permission views typechecked; manual/recovered scope uses source parent and snapshots")
    }
}
