import XCTest
@testable import AutomationCore

final class IgnoredSubtitleNoticeTests: XCTestCase {
    func testPgsIsReportedAndConvertibleSubtitlesAreNot() {
        let json = """
        {"streams":[{"codec_name":"hdmv_pgs_subtitle","tags":{"language":"fre"}},
                    {"codec_name":"subrip","tags":{"language":"eng"}},
                    {"codec_name":"ass"}]}
        """
        XCTAssertEqual(IgnoredSubtitleNotice.messages(fromProbeJSON: json),
                       ["sous-titre PGS fre ignoré (non convertible en arrière-plan)"])
    }

    func testMalformedProbeYieldsNoNotice() {
        XCTAssertEqual(IgnoredSubtitleNotice.messages(fromProbeJSON: "not json"), [])
    }

    /// Ignoring a subtitle must not alter the video/audio gate.
    func testValidationStillCountsOnlyVideoAndAudio() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/AutomationCore/MediaValidationService.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("outputAudio >= counts.audio"))
        XCTAssertTrue(source.contains("outputVideo == counts.video"))
        XCTAssertFalse(source.lowercased().contains("subtitle"))
    }
}
