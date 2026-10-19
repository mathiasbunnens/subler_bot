import XCTest
@testable import AutomationCore

final class SublerBackgroundTests: XCTestCase {
    func testInstalledDefaultIsUnchanged() throws {
        let target = SublerTarget(backgroundApplication: nil)
        XCTAssertFalse(target.isBackground)
        XCTAssertEqual(target.bundleIdentifier, "org.galad.Subler")
        XCTAssertNil(try target.validatedApplicationURL())
        XCTAssertEqual(target.documentArgument(42, role: "into"), "into (document of window id 42)")
    }
    func testInvalidLocalOptInNeverFallsBack() async {
        for path in ["", "relative.app", "/Applications/Subler.app", "/nonexistent/background.app"] {
            let target = SublerTarget(backgroundApplication: path)
            XCTAssertEqual(target.bundleIdentifier, "local.sublerautomation.Subler")
            XCTAssertThrowsError(try target.validatedApplicationURL())
            let service = SublerService(target: target)
            do { _ = try await service.queueState(destination: URL(fileURLWithPath: "/nonexistent/output.mp4")); XCTFail("Must reject before any Apple Event") }
            catch { XCTAssertFalse(error.localizedDescription.contains("osascript")) }
        }
    }
    func testBackgroundTargetsTokenNotWindow() {
        let target = SublerTarget(backgroundApplication: "/nonexistent/background.app")
        XCTAssertEqual(target.documentArgument(42, role: "doc"), "owned token 42")
        XCTAssertEqual(target.documentArgument(42, role: "into"), "owned token 42")
    }
    func testDifferentRunningLocalBuildIsRejected() throws {
        let target = SublerTarget(backgroundApplication: "/reviewed/Subler.app")
        let expected = URL(fileURLWithPath: "/reviewed/Subler.app")
        XCTAssertNoThrow(try target.validateRunningApplicationURLs([], expected: expected))
        XCTAssertNoThrow(try target.validateRunningApplicationURLs([expected], expected: expected))
        XCTAssertThrowsError(try target.validateRunningApplicationURLs([URL(fileURLWithPath: "/older/Subler.app")], expected: expected))
    }
    func testRealBackgroundManualConversion() async throws {
        guard let app = ProcessInfo.processInfo.environment["SUBLER_TEST_BACKGROUND_APP"],
              let input = ProcessInfo.processInfo.environment["SUBLER_TEST_BACKGROUND_FIXTURE"] else { throw XCTSkip("Explicit local build + generated fixture required") }
        let target = SublerTarget(backgroundApplication: app)
        _ = try target.validatedApplicationURL()
        let service = SublerService(target: target)
        let source = URL(fileURLWithPath: input)
        let output = source.deletingLastPathComponent().appendingPathComponent("swift-background-\(UUID().uuidString).mp4")
        let doc = try await service.prepare(source: source)
        do {
            try await service.convert(document: doc, manual: ManualMovieMetadata(title: "Generated preservation fixture", year: 2026), destination: output)
            let state = try await service.queueState(destination: output)
            XCTAssertEqual(state, "completed")
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        } catch { await service.close(document: doc); throw error }
        await service.close(document: doc)
    }

    func testRealBackgroundCloseTargetsOnlyOwnedToken() async throws {
        guard let app = ProcessInfo.processInfo.environment["SUBLER_TEST_BACKGROUND_APP"],
              let input = ProcessInfo.processInfo.environment["SUBLER_TEST_BACKGROUND_FIXTURE"] else { throw XCTSkip("Explicit local build + generated fixture required") }
        let target = SublerTarget(backgroundApplication: app)
        let service = SublerService(target: target)
        let first = try await service.prepare(source: URL(fileURLWithPath: input))
        let second = try await service.prepare(source: URL(fileURLWithPath: input))
        XCTAssertNotEqual(first.id, second.id)
        await service.close(document: first)
        do {
            let state = try await AppleScriptService.run("tell \(try target.applicationClause()) to return {has background document \(first.id), has background document \(second.id)}")
            XCTAssertEqual(state, "false, true")
        } catch { await service.close(document: second); throw error }
        await service.close(document: second)
        let state = try await AppleScriptService.run("tell \(try target.applicationClause()) to return background state")
        XCTAssertEqual(state, "0|false|2|0")
    }

    func testRealBackgroundMetadataSelectionAndConversion() async throws {
        guard ProcessInfo.processInfo.environment["SUBLER_TEST_BACKGROUND_METADATA"] == "1",
              let app = ProcessInfo.processInfo.environment["SUBLER_TEST_BACKGROUND_APP"],
              let input = ProcessInfo.processInfo.environment["SUBLER_TEST_BACKGROUND_FIXTURE"] else { throw XCTSkip("Explicit online metadata test required") }
        let directory = URL(fileURLWithPath: input).deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let source = directory.appendingPathComponent("Amelie.2001.mp4")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: input), to: source)
        let target = SublerTarget(backgroundApplication: app)
        let service = SublerService(target: target)
        let doc = try await service.prepare(source: source)
        do {
            let candidates = try await service.candidates(document: doc)
            let chosen = try XCTUnwrap(MetadataMatching.best(sourceName: source.lastPathComponent, candidates: candidates))
            let output = directory.appendingPathComponent("metadata-output.mp4")
            try await service.convert(document: doc, candidate: chosen, destination: output)
            let validated = try await MediaValidationService.validate(source: source, output: output, expected: chosen)
            XCTAssertEqual(validated.title, chosen.title)
            XCTAssertEqual(validated.year, 2001)
            let state = try await AppleScriptService.run("tell \(try target.applicationClause()) to return background state")
            XCTAssertEqual(state, "0|false|2|0")
            print("BACKGROUND_METADATA_OUTPUT: \(output.path)")
        } catch { await service.close(document: doc); throw error }
        await service.close(document: doc)
    }
}
