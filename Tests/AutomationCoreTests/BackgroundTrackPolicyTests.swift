import XCTest
@testable import AutomationCore

/// Compiles the engine's pure track policy (extracted verbatim from the vendored ScriptCommand.swift between
/// BEGIN/END-PURE-POLICY markers) against stub FourCCs, with `isTrackMuxable` built from the real list in
/// MP42Utilities.m, and runs the decisions.
final class BackgroundTrackPolicyTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func runPolicy(_ checks: String) throws -> String {
        let script = try read("vendor-local/Subler/Classes/ScriptCommand.swift")
        let begin = try XCTUnwrap(script.range(of: "enum BackgroundTrackKind"))
        let policyStart = try XCTUnwrap(script.range(of: "// BEGIN-PURE-POLICY"))
        let policyEnd = try XCTUnwrap(script.range(of: "// END-PURE-POLICY"))
        let types = String(script[begin.lowerBound..<policyStart.lowerBound])
        let policy = String(script[policyStart.upperBound..<policyEnd.lowerBound])
        let utilities = try read("vendor-local/Subler/MP42Foundation/MP42/MP42Utilities.m")
        let muxStart = try XCTUnwrap(utilities.range(of: "BOOL isTrackMuxable"))
        let listStart = try XCTUnwrap(utilities.range(of: "{", range: muxStart.upperBound..<utilities.endIndex)) // body
        let arrayStart = try XCTUnwrap(utilities.range(of: "supportedFormats[] = {", range: listStart.lowerBound..<utilities.endIndex))
        let arrayEnd = try XCTUnwrap(utilities.range(of: "0};", range: arrayStart.upperBound..<utilities.endIndex))
        let muxable = utilities[arrayStart.upperBound..<arrayEnd.lowerBound]
            .split(whereSeparator: { ",\n ".contains($0) }).map(String.init).filter { $0.hasPrefix("kMP42") }
        var names = Set(muxable)
        let pattern = try NSRegularExpression(pattern: "kMP42[A-Za-z0-9_]+")
        for match in pattern.matches(in: policy + checks, range: NSRange(policy.startIndex..., in: policy + checks)) {
            names.insert(String((policy + checks as NSString).substring(with: match.range)))
        }
        let constants = names.sorted().enumerated().map { "let \($1): FourCharCode = \(1000 + $0)" }.joined(separator: "\n")
        let source = """
        typealias FourCharCode = UInt32
        \(constants)
        func isTrackMuxable(_ format: FourCharCode) -> Bool { [\(muxable.joined(separator: ", "))].contains(format) }
        \(types)
        \(policy)
        \(checks)
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("main.swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        process.arguments = ["-o", dir.appendingPathComponent("policy").path, file.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        let compile = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, compile)
        let run = Process()
        run.executableURL = dir.appendingPathComponent("policy")
        let out = Pipe()
        run.standardOutput = out
        try run.run()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        run.waitUntilExit()
        XCTAssertEqual(run.terminationStatus, 0, text)
        return text
    }

    func testSubtitlePolicyAndFailClosedForVideoAndAudio() throws {
        let output = try runPolicy("""
        func check(_ name: String, _ actual: BackgroundTrackDecision, _ expected: BackgroundTrackDecision) {
            print("\\(name)=\\(actual == expected ? "ok" : "FAIL(\\(actual))")")
        }
        let unknown: FourCharCode = 424242
        check("pgs", BackgroundTrackPolicy.decide(kind: .subtitle, format: kMP42SubtitleCodecType_PGS), .skip)
        check("ssa", BackgroundTrackPolicy.decide(kind: .subtitle, format: kMP42SubtitleCodecType_SSA), .convertToTx3g)
        check("srt", BackgroundTrackPolicy.decide(kind: .subtitle, format: kMP42SubtitleCodecType_Text), .convertToTx3g)
        check("vobsub", BackgroundTrackPolicy.decide(kind: .subtitle, format: kMP42SubtitleCodecType_VobSub), .copy)
        check("tx3g", BackgroundTrackPolicy.decide(kind: .subtitle, format: kMP42SubtitleCodecType_3GText), .copy)
        check("unknownSubtitle", BackgroundTrackPolicy.decide(kind: .subtitle, format: unknown), .skip)
        check("hevc", BackgroundTrackPolicy.decide(kind: .video, format: kMP42VideoCodecType_HEVC), .copy)
        check("unknownVideo", BackgroundTrackPolicy.decide(kind: .video, format: unknown), .refuse)
        check("eac3", BackgroundTrackPolicy.decide(kind: .audio, format: kMP42AudioCodecType_EnhancedAC3), .copy)
        check("dts", BackgroundTrackPolicy.decide(kind: .audio, format: kMP42AudioCodecType_DTS), .convertToAAC)
        check("unknownAudio", BackgroundTrackPolicy.decide(kind: .audio, format: unknown), .refuse)
        check("pgsAsAudio", BackgroundTrackPolicy.decide(kind: .audio, format: kMP42SubtitleCodecType_PGS), .refuse)
        check("unknownOther", BackgroundTrackPolicy.decide(kind: .other, format: unknown), .refuse)
        """)
        let lines = output.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 13, output)
        for line in lines { XCTAssertTrue(line.hasSuffix("=ok"), line) }
    }

    func testEngineLogsSkippedSubtitleAndKeepsAVRefusal() throws {
        let source = try read("vendor-local/Subler/Classes/ScriptCommand.swift")
        let patch = try read("patches/local-subler/background-subtitle-policy.patch")
        let script = try read("scripts/prepare-local-subler.sh")
        XCTAssertTrue(source.contains("ignoré (non convertible en arrière-plan)"))
        XCTAssertTrue(source.contains("plan.refusal"))
        XCTAssertTrue(patch.contains("ignoré (non convertible en arrière-plan)"))
        XCTAssertTrue(script.contains("background-subtitle-policy.patch"))
        let audio = try XCTUnwrap(script.range(of: "background-audio-conversion.patch\"\n"))
        let subtitle = try XCTUnwrap(script.range(of: "apply \"$patch_root/background-subtitle-policy.patch\""))
        XCTAssertLessThan(audio.lowerBound, subtitle.lowerBound, "subtitle patch builds on the audio patch")
    }
}
