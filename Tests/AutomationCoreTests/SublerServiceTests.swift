import XCTest
@testable import AutomationCore

final class SublerServiceTests: XCTestCase {
    func testValidationNeverAcceptsSourceAsOutput() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUBLER_TEST_VALIDATED_MP4"] else { throw XCTSkip("Requires synthetic MP4") }
        let file = URL(fileURLWithPath: path)
        do {
            _ = try await MediaValidationService.validate(source: file, output: file, expected: MetadataCandidate(index: 1, title: "Amélie", year: 2001, raw: ""))
            XCTFail("Original source must not be accepted as generated output")
        } catch { XCTAssertTrue(error.localizedDescription.contains("same file")) }
    }
    func testAppleScriptErrorsRetainDescriptionAndNumber() async {
        do {
            _ = try await AppleScriptService.run("error \"intentional test failure\" number 1234")
            XCTFail("Expected script error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("intentional test failure"))
            XCTAssertTrue(error.localizedDescription.contains("1234"))
        }
    }

    func testAppleScriptTimeoutDoesNotWaitForScriptCompletion() async {
        let start = Date()
        do {
            _ = try await AppleScriptService.run("delay 10", timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func testAppleScriptCancellationStopsOnlyWorker() async {
        let task = Task { try await AppleScriptService.run("delay 10") }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testAppleScriptLiteralPreservesQuotesBackslashesAndLineBreaks() async throws {
        let value = "a\"b\\c\nAmélie"
        let result = try await AppleScriptService.run("return \(AppleScriptService.literal(value))")
        XCTAssertEqual(result, value)
    }

    func testValidationRejectsSelectedMetadataMismatch() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUBLER_TEST_VALIDATED_MP4"], let sourcePath = ProcessInfo.processInfo.environment["SUBLER_TEST_MKV"] else { throw XCTSkip("Requires real synthetic conversion output") }
        do {
            _ = try await MediaValidationService.validate(source: URL(fileURLWithPath: sourcePath), output: URL(fileURLWithPath: path), expected: MetadataCandidate(index: 1, title: "Wrong Movie", year: 2002, raw: ""))
            XCTFail("Applied tags must match selection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("does not match")) }
    }

    func testUnownedDocumentCannotBeConverted() async {
        do {
            try await SublerService().convert(document: SublerDocument(id: -1), candidate: MetadataCandidate(index: 1, title: "Example", year: 2000, raw: ""), destination: URL(fileURLWithPath: "/nonexistent/output.mp4"))
            XCTFail("Unowned document must be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("not owned")) }
    }
    func testValidationRejectsMissingOutput() async {
        do {
            _ = try await MediaValidationService.validate(source: URL(fileURLWithPath: "/nonexistent/source.mkv"), output: URL(fileURLWithPath: "/nonexistent/output.mp4"), expected: MetadataCandidate(index: 1, title: "Amélie", year: 2001, raw: ""))
            XCTFail("Missing output must not validate")
        } catch { XCTAssertTrue(error.localizedDescription.contains("output")) }
    }
    func testRealSublerConversionValidatesSelectedMetadata() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUBLER_TEST_CONVERT_MKV"] else { throw XCTSkip("Opt-in real Subler conversion") }
        let service = SublerService()
        let source = URL(fileURLWithPath: path)
        let output = source.deletingLastPathComponent().appendingPathComponent("converted-\(UUID().uuidString).mp4")
        let document = try await service.prepare(source: source)
        do {
            let candidates = try await service.candidates(document: document)
            let chosen = try XCTUnwrap(candidates.first(where: { $0.year == 2001 }))
            try await service.convert(document: document, candidate: chosen, destination: output)
            let validated = try await MediaValidationService.validate(source: source, output: output, expected: chosen)
            XCTAssertEqual(validated.title, chosen.title)
            XCTAssertEqual(validated.year, chosen.year)
            XCTAssertGreaterThan(validated.size, 0)
            let state = try await service.queueState(destination: output)
            XCTAssertEqual(state, "completed")
            print("SUBLER_VALIDATED: \(output.path) title=\(validated.title) year=\(validated.year) bytes=\(validated.size)")
        } catch { await service.close(document: document); throw error }
        await service.close(document: document)
    }
    func testRealSublerPrepareCandidatesClose() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUBLER_TEST_MKV"] else { throw XCTSkip("Opt-in synthetic MKV integration") }
        let service = SublerService()
        let document = try await service.prepare(source: URL(fileURLWithPath: path))
        let candidates = try await service.candidates(document: document)
        XCTAssertFalse(candidates.isEmpty)
        print("SUBLER_CANDIDATES: \(candidates)")
        await service.close(document: document)
    }
    func testBestRequiresUniqueExactTitleAndYear() {
        let candidate = MetadataCandidate(index: 1, title: "Amélie", year: 2001, raw: "Movie: Amélie (2001)")
        XCTAssertEqual(MetadataMatching.best(sourceName: "Amelie.2001.1080p.mkv", candidates: [candidate]), candidate)
        XCTAssertNil(MetadataMatching.best(sourceName: "Amelie.2002.mkv", candidates: [candidate]))
        XCTAssertNil(MetadataMatching.best(sourceName: "Amelie.mkv", candidates: [candidate]))
        XCTAssertNil(MetadataMatching.best(sourceName: "Amelie.2001.mkv", candidates: [candidate, candidate]))
        XCTAssertNil(MetadataMatching.best(sourceName: "Not.Amelie.2001.mkv", candidates: [candidate]))
    }
    func testCandidateParsingKeepsOriginalOneBasedIndexAndRequiresMovieYear() {
        let result = MetadataMatching.parse("Movie: Amélie (2001)", index: 4)
        XCTAssertEqual(result?.title, "Amélie")
        XCTAssertEqual(result?.year, 2001)
        XCTAssertEqual(result?.index, 4)
        XCTAssertNil(MetadataMatching.parse("TV: Example S1E2", index: 1))
        XCTAssertNil(MetadataMatching.parse("Movie: Example", index: 2))
    }
    func testAppleScriptExecutesRealProcessAndPreservesUnicode() async throws {
        let result = try await AppleScriptService.run("return \"héllo\"")
        XCTAssertEqual(result, "héllo")
    }
    func testValidationRejectsMissingDuration() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["SUBLER_TEST_VALIDATED_MP4"],
              let sourcePath = ProcessInfo.processInfo.environment["SUBLER_TEST_LONG_MKV"] else { throw XCTSkip("Requires synthetic duration fixtures") }
        do {
            _ = try await MediaValidationService.validate(source: URL(fileURLWithPath: sourcePath), output: URL(fileURLWithPath: outputPath), expected: MetadataCandidate(index: 1, title: "Amélie", year: 2001, raw: ""))
            XCTFail("An output missing most of the source duration must not be transferred")
        } catch { XCTAssertTrue(error.localizedDescription.contains("duration")) }
    }
}
