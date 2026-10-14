import XCTest
@testable import AutomationCore

final class FirstInstallDefaultsTests: XCTestCase {
    func testNoPersonalServerOrAccountIsBakedIn() {
        let config = SMBConfiguration()
        XCTAssertEqual(config.serverURL, "")
        XCTAssertEqual(config.username, "")
        XCTAssertFalse(config.isConfigured)
    }

    func testMountedShareBecomesDefaultWithItsUser() {
        let config = SMBConfiguration.fromMount(origin: "//alice@nas.local/Films", mountPoint: "/Volumes/Films", fallbackUser: "bob")
        XCTAssertEqual(config, SMBConfiguration(serverURL: "smb://nas.local/Films", username: "alice", expectedMountPath: "/Volumes/Films"))
    }

    func testDomainUserAndMissingUser() {
        XCTAssertEqual(SMBConfiguration.fromMount(origin: "//WORKGROUP;carol@192.168.0.5/Movies", mountPoint: "/Volumes/Movies", fallbackUser: "bob")?.username, "carol")
        let anonymous = SMBConfiguration.fromMount(origin: "//nas/Videos", mountPoint: "/Volumes/Videos", fallbackUser: "bob")
        XCTAssertEqual(anonymous?.username, "bob")
        XCTAssertEqual(anonymous?.serverURL, "smb://nas/Videos")
    }

    func testUnusableMountsAreIgnored() {
        XCTAssertNil(SMBConfiguration.fromMount(origin: "/dev/disk3s1", mountPoint: "/", fallbackUser: "bob"))
        XCTAssertNil(SMBConfiguration.fromMount(origin: "//nas/a/b", mountPoint: "/Volumes/a", fallbackUser: "bob"))
    }

    func testFirstLaunchFallsBackToMacAccountWithoutServer() {
        let config = SMBConfiguration.firstLaunchDefault(userName: "dora")
        if SMBConfiguration.mountedSMBShares().isEmpty {
            XCTAssertFalse(config.isConfigured)
            XCTAssertEqual(config.username, "dora")
        } else {
            XCTAssertTrue(config.serverURL.hasPrefix("smb://"))
            XCTAssertFalse(config.username.isEmpty)
        }
    }

    func testJobConvertedBeforeServerConfigurationUsesCurrentServer() {
        let current = SMBConfiguration(serverURL: "smb://nas/Films", username: "alice", expectedMountPath: "/Volumes/Films")
        XCTAssertEqual(SMBConfiguration.effective(job: SMBConfiguration(), current: current), current)
        XCTAssertEqual(SMBConfiguration.effective(job: nil, current: current), current)
        let snapshot = SMBConfiguration(serverURL: "smb://old/Movies", username: "x", expectedMountPath: "/Volumes/Movies")
        XCTAssertEqual(SMBConfiguration.effective(job: snapshot, current: current), snapshot)
    }

    @MainActor func testUnconfiguredServerDoesNotBlockConversionPermissions() async {
        let engine = PermissionPreparation(operations: .init(automation: { _ in .granted }, sourceRead: { _, _ in nil }, temporaryWrite: { _, _ in nil }, mountedShare: { _ in nil }, networkRead: { _, _ in nil }, notifications: { _ in .granted }, load: { nil }, save: { _ in }))
        await engine.prepare(.init(sourcePath: "/Source", temporaryPath: "/Temp", serverURL: "", expectedMountPath: "", notifications: false))
        XCTAssertTrue(engine.state.isReady)
    }
}
