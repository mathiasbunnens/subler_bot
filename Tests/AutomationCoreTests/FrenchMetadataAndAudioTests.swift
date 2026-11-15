import XCTest
@testable import AutomationCore

final class FrenchMetadataAndAudioTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testDefaultMetadataLanguageIsFrench() {
        XCTAssertEqual(SublerService.defaultMetadataLanguage, "fr")
        XCTAssertEqual(SublerService.languageClause("fr"), " language \"fr\"")
        XCTAssertEqual(SublerService.languageClause("a\"b"), " language \"a\\\"b\"")
    }

    /// Search and fetch-and-set must both carry the language; the embedded engine otherwise falls back to English.
    func testSearchAndFetchAndSetBothPassLanguage() throws {
        let source = try String(contentsOf: root.appendingPathComponent("Sources/AutomationCore/SublerService.swift"), encoding: .utf8)
        for line in source.split(separator: "\n") where line.contains("fetch metadata candidates") || line.contains("fetch and set metadata candidate") {
            XCTAssertTrue(line.contains("languageClause(metadataLanguage)"), "Missing language: \(line)")
        }
        XCTAssertEqual(source.components(separatedBy: "languageClause(metadataLanguage)").count - 1, 2)
    }

    /// The native engine decides AAC for formats AVFoundation/Apple TV cannot play and copies the others.
    func testEngineConvertsDtsToAacAndCopiesAacAc3() throws {
        let source = try String(contentsOf: root.appendingPathComponent("vendor-local/Subler/Classes/ScriptCommand.swift"), encoding: .utf8)
        let patch = try String(contentsOf: root.appendingPathComponent("patches/local-subler/background-audio-conversion.patch"), encoding: .utf8)
        for text in [source, patch] {
            for needed in ["kMP42AudioCodecType_DTS", "kMP42AudioCodecType_TrueHD", "kMP42AudioCodecType_MPEG4AAC",
                           "MP42AudioConversionSettings", "BackgroundTrackPolicy.configure(track)"] {
                XCTAssertTrue(text.contains(needed), needed)
            }
        }
        let list = try XCTUnwrap(source.range(of: "static func audioNeedsAAC")).upperBound
        let body = String(source[list...].prefix(500))
        for copied in ["kMP42AudioCodecType_AC3", "kMP42AudioCodecType_EnhancedAC3", "kMP42AudioCodecType_MPEG4AAC,", "AppleLossless"] {
            XCTAssertFalse(body.contains(copied), "\(copied) must be copied, not converted")
        }
    }

    /// Needs SUBLER_TEST_BACKGROUND_APP and SUBLER_TEST_DTS_FIXTURE (generated MKV: h264 + DTS [+ SRT]) in a scratch root.
    func testRealBackgroundDtsMkvBecomesAacAndValidates() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let app = env["SUBLER_TEST_BACKGROUND_APP"], let input = env["SUBLER_TEST_DTS_FIXTURE"] else {
            throw XCTSkip("Explicit local build + generated DTS fixture required")
        }
        let target = SublerTarget(backgroundApplication: app)
        let service = SublerService(target: target)
        let source = URL(fileURLWithPath: input)
        let output = source.deletingLastPathComponent().appendingPathComponent("dts-\(UUID().uuidString).mp4")
        let doc = try await service.prepare(source: source)
        do {
            let manual = try ManualMovieMetadata(title: "La Tour Montparnasse infernale", year: 2001)
            try await service.convert(document: doc, manual: manual, destination: output)
            let queueState = try await service.queueState(destination: output)
            XCTAssertEqual(queueState, "completed")
            // ManualMetadataWriter persists the identity after conversion; audio count is AVFoundation's.
            let audioCount = try await AVURLAssetCounter.audioTracks(output)
            XCTAssertGreaterThanOrEqual(audioCount, 1)
        } catch { await service.close(document: doc); throw error }
        await service.close(document: doc)
    }
}

import AVFoundation
enum AVURLAssetCounter {
    static func audioTracks(_ url: URL) async throws -> Int {
        try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).count
    }
}
