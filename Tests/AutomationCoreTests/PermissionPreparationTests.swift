import XCTest
@testable import AutomationCore

final class PermissionPreparationTests: XCTestCase {
    @MainActor func testCredentialURLsNeverPersist() async {
        var saved = false
        let engine = PermissionPreparation(operations: .init(automation: { _ in .granted }, sourceRead: { _, _ in nil }, temporaryWrite: { _, _ in nil }, mountedShare: { _ in nil }, networkRead: { _, _ in nil }, notifications: { _ in .granted }, load: { nil }, save: { _ in saved = true }))
        await engine.prepare(.init(sourcePath: "/Source", temporaryPath: "/Temp", serverURL: "smb://user:fixture-secret@fixture/Movies", expectedMountPath: "/Volumes/Fixture", notifications: false))
        XCTAssertFalse(engine.state.isReady)
        XCTAssertFalse(saved)
    }

    @MainActor func testInvalidPathsNeverReachNativeOperations() async {
        var calls = 0
        let engine = PermissionPreparation(operations: .init(automation: { _ in calls += 1; return .granted }, sourceRead: { _, _ in nil }, temporaryWrite: { _, _ in nil }, mountedShare: { _ in nil }, networkRead: { _, _ in nil }, notifications: { _ in .granted }, load: { nil }, save: { _ in }))
        await engine.prepare(.init(sourcePath: "relative", temporaryPath: "/Temp", serverURL: "", expectedMountPath: "", notifications: false))
        XCTAssertFalse(engine.state.isReady)
        XCTAssertEqual(calls, 0)
    }

    @MainActor func testDenialRevocationPathChangeAndMountedShareRequirePreparation() async {
        let scope = PermissionScope(sourcePath: "/Source", temporaryPath: "/Temp", serverURL: "smb://fixture/Movies", expectedMountPath: "/Volumes/Fixture", notifications: true)
        var automation: PermissionDecision = .denied
        var mount: String?
        var networkError: String?
        var saved: PermissionGrant?
        var requests: [Bool] = []
        let operations = PermissionOperations(automation: { ask in requests.append(ask); return automation }, sourceRead: { _, _ in nil }, temporaryWrite: { _, _ in nil }, mountedShare: { _ in mount }, networkRead: { _, _ in networkError }, notifications: { _ in .denied }, load: { saved }, save: { saved = $0 })
        let engine = PermissionPreparation(operations: operations)
        await engine.prepare(scope)
        XCTAssertFalse(engine.state.isReady); XCTAssertNil(saved)
        automation = .granted
        await engine.prepare(scope)
        XCTAssertTrue(engine.state.isReady) // Optional notifications denied.
        automation = .denied
        await engine.recheck(scope)
        XCTAssertFalse(engine.state.isReady); XCTAssertEqual(requests.last, false)
        automation = .granted; mount = "/Volumes/Fixture"
        await engine.recheck(scope)
        XCTAssertFalse(engine.state.isReady) // No network prompt from tick.
        networkError = "Refusé"
        await engine.prepare(scope)
        XCTAssertFalse(engine.state.isReady)
        networkError = nil
        await engine.prepare(scope)
        XCTAssertTrue(engine.state.isReady); XCTAssertEqual(saved?.networkPath, mount)
        requests = []
        await engine.recheck(.init(sourcePath: "/Other", temporaryPath: "/Temp", serverURL: scope.serverURL, expectedMountPath: scope.expectedMountPath, notifications: true))
        XCTAssertFalse(engine.state.isReady); XCTAssertTrue(requests.isEmpty)
    }

    @MainActor func testUpfrontGrantPersistsScopeAndRelaunchRechecksWithoutRequests() async throws {
        let scope = PermissionScope(sourcePath: "/Source", temporaryPath: "/Temp", serverURL: "smb://fixture/Movies", expectedMountPath: "/Volumes/Fixture", notifications: true)
        var calls: [String] = []
        var saved: PermissionGrant?
        let operations = PermissionOperations(automation: { ask in calls.append("automation:\(ask)"); return .granted }, sourceRead: { _, ask in calls.append("read:\(ask)"); return nil }, temporaryWrite: { _, ask in calls.append("write:\(ask)"); return nil }, mountedShare: { _ in nil }, networkRead: { _, ask in calls.append("network:\(ask)"); return nil }, notifications: { ask in calls.append("notifications:\(ask)"); return .granted }, load: { saved }, save: { saved = $0 })
        let engine = PermissionPreparation(operations: operations)
        await engine.prepare(scope)
        XCTAssertTrue(engine.state.isReady)
        XCTAssertEqual(saved?.scope, scope)
        XCTAssertEqual(calls, ["automation:true", "read:true", "write:true", "notifications:true"])
        calls = []
        let relaunched = PermissionPreparation(operations: operations)
        await relaunched.recheck(scope)
        XCTAssertTrue(relaunched.state.isReady)
        XCTAssertEqual(calls, ["automation:false", "read:false", "write:false", "notifications:false"])
    }
}
