import Foundation
import Combine
import AutomationCore

@main struct PermissionFixture {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!)
        let scope = PermissionScope(sourcePath: root.appendingPathComponent("Source").path, temporaryPath: root.appendingPathComponent("Temp").path, serverURL: "smb://fixture.invalid/Movies", expectedMountPath: "/Volumes/Fixture", notifications: true)
        // The default service must select deterministic operations, never native TCC.
        let service = PermissionPreparationService(storageURL: root.appendingPathComponent("grant.json"))
        await service.prepare(scope)
        precondition(service.isReady(for: scope))
        var states: [PermissionPreparationState] = []
        var networkUpdates: [String] = []
        var notificationUpdates: [PermissionDecision] = []
        let observers = [service.$state.dropFirst().sink { states.append($0) },
                         service.$networkMessage.dropFirst().sink { networkUpdates.append($0) },
                         service.$notificationStatus.dropFirst().sink { notificationUpdates.append($0) }]
        for _ in 0..<4 { await service.recheck(scope) }
        precondition(states.isEmpty && networkUpdates.isEmpty && notificationUpdates.isEmpty,
                     "Silent unchanged rechecks publish transient UI states and make the window flash")
        withExtendedLifetime(observers) {}
        var allowed = true
        weak var checkingService: PermissionPreparationService?
        var readyDuringCheck = false
        let changing = PermissionPreparationService(operations: .init(
            automation: { _ in
                readyDuringCheck = checkingService?.isReady(for: scope) ?? false
                await Task.yield()
                return allowed ? .granted : .denied
            }, sourceRead: { _, _ in nil }, temporaryWrite: { _, _ in nil }, mountedShare: { _ in nil },
            networkRead: { _, _ in nil }, notifications: { _ in .granted },
            load: { PermissionGrant(scope: scope, networkPath: nil) }, save: { _ in }))
        checkingService = changing
        await changing.recheck(scope)
        precondition(changing.isReady(for: scope))
        var changedStates: [PermissionPreparationState] = []
        let changedObserver = changing.$state.dropFirst().sink { changedStates.append($0) }
        allowed = false
        await changing.recheck(scope)
        await changing.recheck(scope)
        precondition(!changing.isReady(for: scope) && changedStates.count == 1)
        precondition(!changedStates.contains(.requesting), "Silent revocation exposed a transient preparation state")
        allowed = true
        await changing.recheck(scope)
        precondition(changing.isReady(for: scope) && changedStates.count == 2 && changedStates.last == .ready)
        precondition(!readyDuringCheck, "A stale ready scope escaped the in-flight authorization gate")
        withExtendedLifetime(changedObserver) {}
        print("PASS: unchanged silent checks publish zero UI updates; revocation/regrant publish only real changes; in-flight checks block work")
        let relaunched = PermissionPreparationService(storageURL: root.appendingPathComponent("grant.json"))
        await relaunched.recheck(scope)
        precondition(relaunched.isReady(for: scope))
        let other = PermissionScope(sourcePath: root.appendingPathComponent("Other").path, temporaryPath: scope.temporaryPath, serverURL: scope.serverURL, expectedMountPath: scope.expectedMountPath, notifications: true)
        await relaunched.recheck(other)
        precondition(!relaunched.isReady(for: other))
        await relaunched.prepare(other)
        precondition(relaunched.isReady(for: other))
        await relaunched.recheck(scope)
        precondition(relaunched.isReady(for: scope), "Preparing a job must preserve the watched configuration grant")
        // Native file probe itself is safe to exercise with owned local scratch files.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Probe"), withIntermediateDirectories: true)
        let probeError = await PermissionNativeAccess.temporaryWrite(root.appendingPathComponent("Probe").path, request: true)
        precondition(probeError == nil)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Probe").path)
        precondition(remaining.isEmpty)
        let absent = root.appendingPathComponent("SilentMustNotCreate").path
        let silentRead = await PermissionNativeAccess.directoryRead(absent, request: false, local: true)
        let silentWrite = await PermissionNativeAccess.temporaryWrite(absent, request: false)
        precondition(silentRead != nil && silentWrite != nil)
        precondition(!FileManager.default.fileExists(atPath: absent))
        let nativeGuard = await PermissionNativeAccess.automation(request: true)
        precondition(nativeGuard == .granted)
        var prompts = 0
        let revoked = PermissionPreparationService(operations: .init(automation: { ask in if ask { prompts += 1 }; return .denied }, sourceRead: { _, _ in nil }, temporaryWrite: { _, _ in nil }, mountedShare: { _ in nil }, networkRead: { _, _ in nil }, notifications: { _ in .denied }, load: { PermissionGrant(scope: scope, networkPath: nil) }, save: { _ in }))
        await revoked.startup(scope)
        precondition(!revoked.isReady(for: scope))
        precondition(prompts == 0, "Relaunch must not request revoked recorded permissions")
        NotificationService().requestPermission() // Environment guard: no native center request.
        print("PASS: fixture grant, relaunch, path change, owned probe cleanup, no native permission requests")
    }
}
