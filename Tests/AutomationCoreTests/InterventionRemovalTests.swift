import XCTest
@testable import AutomationCore

final class InterventionRemovalTests: XCTestCase {
    func testPendingMetadataInterventionWithMissingSourceCanBeRemoved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(root: root)
        var job = MovieJob(sourcePath: root.appendingPathComponent("Spider-Man.mkv").path, fingerprint: "original")
        job.needsSelection = true
        let completed = { () -> MovieJob in
            var value = MovieJob(sourcePath: "/completed.mkv", fingerprint: "completed")
            value.status = .completed
            return value
        }()
        try store.save([job, completed])
        XCTAssertEqual(try store.removeIntervention(job.id, jobs: [job, completed], activeID: nil).map(\.id), [completed.id])
        XCTAssertEqual(try QueueStore(root: root).load().map(\.id), [completed.id])
        XCTAssertTrue(try store.isDismissed(fingerprint: job.fingerprint))
    }

    func testRecoveryKeepsMetadataInterventionOutOfAutomaticPendingQueue() {
        var job = MovieJob(sourcePath: "/missing.mkv", fingerprint: "original")
        job.needsSelection = true
        job.recover()
        XCTAssertEqual(job.status, .paused)
        XCTAssertTrue(job.needsSelection)
    }

    func testReadbackFailureDoesNotReportRemovalSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(root: root)
        var job = MovieJob(sourcePath: root.appendingPathComponent("missing.mkv").path, fingerprint: "missing")
        job.status = .failed
        try store.save([job])
        let noWrite = try QueueStore(root: root, stateWriter: { _, _ in })
        XCTAssertThrowsError(try noWrite.removeIntervention(job.id, jobs: [job], activeID: nil))
        XCTAssertEqual(try store.load().map(\.id), [job.id])
        XCTAssertFalse(try store.isDismissed(fingerprint: job.fingerprint))
        let failedWrite = try QueueStore(root: root, stateWriter: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertThrowsError(try failedWrite.removeIntervention(job.id, jobs: [job], activeID: nil))
        XCTAssertEqual(try store.load().map(\.id), [job.id])
    }
    func testOnlyInactiveInterventionStatusesCanBeRemoved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(root: root)
        for status in JobStatus.allCases {
            var job = MovieJob(sourcePath: root.appendingPathComponent("missing.mkv").path, fingerprint: status.rawValue)
            job.status = status
            try store.save([job])
            XCTAssertThrowsError(try store.removeIntervention(job.id, jobs: [job], activeID: job.id))
            XCTAssertEqual(try store.load().map(\.id), [job.id])
            if [.paused, .failed, .waitingForServer].contains(status) {
                XCTAssertTrue(try store.removeIntervention(job.id, jobs: [job], activeID: nil).isEmpty)
                XCTAssertTrue(try store.load().isEmpty)
            } else {
                XCTAssertThrowsError(try store.removeIntervention(job.id, jobs: [job], activeID: nil))
                XCTAssertEqual(try store.load().map(\.id), [job.id])
            }
        }
        XCTAssertThrowsError(try store.removeIntervention(UUID(), jobs: [], activeID: nil))
    }
    func testLegacyMigrationAndCorruptStateAreSafe() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(root: root)
        let file = root.appendingPathComponent("jobs.json")
        var job = MovieJob(sourcePath: root.appendingPathComponent("missing.mkv").path, fingerprint: "legacy")
        job.status = .paused
        try JSONEncoder().encode([job]).write(to: file)
        XCTAssertEqual(try store.load().map(\.id), [job.id])
        _ = try store.removeIntervention(job.id, jobs: [job], activeID: nil)
        XCTAssertTrue(try QueueStore(root: root).isDismissed(fingerprint: "legacy"))
        for contents in ["corrupt", "{\"version\":2,\"jobs\":[],\"dismissedFingerprints\":[]}"] {
            let data = Data(contents.utf8)
            try data.write(to: file)
            XCTAssertThrowsError(try store.removeIntervention(job.id, jobs: [job], activeID: nil))
            XCTAssertThrowsError(try store.save([job]))
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
    }
    func testCurrentSourceFingerprintIsSuppressedNotStaleJobIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(root: root)
        let source = root.appendingPathComponent("film.mkv")
        try Data("before".utf8).write(to: source)
        var job = MovieJob(sourcePath: source.path, fingerprint: try FileIdentity.fingerprint(source))
        job.status = .waitingForServer
        try store.save([job])
        try Data("changed since import".utf8).write(to: source)
        let current = try FileIdentity.fingerprint(source)
        _ = try store.removeIntervention(job.id, jobs: [job], activeID: nil)
        XCTAssertTrue(try store.isDismissed(fingerprint: current))
        XCTAssertFalse(try store.isDismissed(fingerprint: job.fingerprint))
    }
    func testChangedSourceIsNotSuppressedAndExplicitAddClearsDismissal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(root: root)
        let source = root.appendingPathComponent("film.mkv")
        try Data("one".utf8).write(to: source)
        var job = MovieJob(sourcePath: source.path, fingerprint: try FileIdentity.fingerprint(source))
        job.status = .failed
        try store.save([job])
        _ = try store.removeIntervention(job.id, jobs: [job], activeID: nil)
        try Data("changed contents".utf8).write(to: source)
        XCTAssertFalse(try store.isDismissed(fingerprint: FileIdentity.fingerprint(source)))
        let explicit = MovieJob(sourcePath: source.path, fingerprint: job.fingerprint)
        try store.save([explicit], explicitlyAddedFingerprints: [job.fingerprint])
        let reopened = try QueueStore(root: root)
        XCTAssertFalse(try reopened.isDismissed(fingerprint: job.fingerprint))
        XCTAssertEqual(try reopened.load().map(\.id), [explicit.id])
    }
    func testRemovalSurvivesReopenAndPreservesMedia() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(root: root)
        let source = root.appendingPathComponent("film.mkv")
        let output = root.appendingPathComponent("film.mp4")
        try Data("source".utf8).write(to: source)
        try Data("output".utf8).write(to: output)
        var job = MovieJob(sourcePath: source.path, fingerprint: try FileIdentity.fingerprint(source))
        job.status = .paused; job.localPath = output.path
        let retained = MovieJob(sourcePath: "/other.mkv", fingerprint: "other")
        try store.save([job, retained])
        let remaining = try store.removeIntervention(job.id, jobs: [job, retained], activeID: nil)
        XCTAssertEqual(remaining.map(\.id), [retained.id])
        let reopened = try QueueStore(root: root)
        XCTAssertEqual(try reopened.load().map(\.id), [retained.id])
        XCTAssertTrue(try reopened.isDismissed(fingerprint: FileIdentity.fingerprint(source)))
        try reopened.save(remaining)
        XCTAssertTrue(try QueueStore(root: root).isDismissed(fingerprint: FileIdentity.fingerprint(source)))
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
        XCTAssertEqual(try Data(contentsOf: output), Data("output".utf8))
    }
}
