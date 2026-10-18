import XCTest
@testable import AutomationCore

final class AppleTVPreparationTests: XCTestCase {
    func testDiagnosticExposesContainerTagAndDolbyVisionProfile() throws {
        let source = try media("\"codec_name\":\"hevc\",\"codec_tag_string\":\"hev1\",\"profile\":\"Main 10\",\"pix_fmt\":\"yuv420p10le\",\"side_data_list\":[{\"dv_profile\":7}]")
        XCTAssertTrue(source.diagnostic.contains("hev1"))
        XCTAssertTrue(source.diagnostic.contains("Dolby Vision profil 7"))
        XCTAssertTrue(source.diagnostic.contains("24/1"))
    }

    func testBaselineAboveAppleDocumentedLevelIsNotAdvertisedAsCompatible() throws {
        let source = try media("\"codec_name\":\"h264\",\"profile\":\"Constrained Baseline\",\"pix_fmt\":\"yuv420p\",\"level\":42")
        XCTAssertThrowsError(try AppleTVPlan.make(media: source, mode: .preserve))
    }

    private func media(_ video: String, extra: String = "") throws -> AppleTVMedia {
        try AppleTVMedia.decode(Data("{\"streams\":[{\"index\":0,\"codec_type\":\"video\",\"width\":1280,\"height\":720,\"avg_frame_rate\":\"24/1\",\(video)}\(extra)],\"format\":{\"duration\":\"2\"}}".utf8))
    }

    func testUnknownTenBitTransferCannotBeSilentlyConvertedToSDR() throws {
        let source = try media("\"codec_name\":\"hevc\",\"profile\":\"Main 10\",\"pix_fmt\":\"yuv420p10le\",\"level\":120")
        XCTAssertThrowsError(try AppleTVPlan.make(media: source, mode: .convert))
    }

    func testAnamorphicVideoCannotBeDistortedBySDRConversion() throws {
        let source = try media("\"codec_name\":\"mpeg4\",\"pix_fmt\":\"yuv420p\",\"sample_aspect_ratio\":\"16:15\"")
        XCTAssertThrowsError(try AppleTVPlan.make(media: source, mode: .convert))
    }

    func testHDRAndDolbyVisionAreNeverReencoded() throws {
        for metadata in ["\"color_transfer\":\"smpte2084\"", "\"color_transfer\":\"arib-std-b67\"", "\"side_data_list\":[{\"side_data_type\":\"DOVI configuration record\",\"dv_profile\":7}]"] {
            let source = try media("\"codec_name\":\"hevc\",\"profile\":\"Main 10\",\"pix_fmt\":\"yuv420p10le\",\(metadata)")
            XCTAssertThrowsError(try AppleTVPlan.make(media: source, mode: .convert))
        }
    }

    func testHEVCMain10RemuxAndHDR10MetadataRequirements() throws {
        let basic = "\"codec_name\":\"hevc\",\"profile\":\"Main 10\",\"pix_fmt\":\"yuv420p10le\",\"level\":120"
        XCTAssertTrue(try AppleTVPlan.make(media: media(basic), mode: .preserve).videoArguments.contains("hvc1"))
        XCTAssertThrowsError(try AppleTVPlan.make(media: media(basic + ",\"color_transfer\":\"smpte2084\""), mode: .preserve))
        let hdr = basic + ",\"color_transfer\":\"smpte2084\",\"color_primaries\":\"bt2020\",\"color_space\":\"bt2020nc\",\"side_data_list\":[{\"side_data_type\":\"Mastering display metadata\"}]"
        XCTAssertTrue(try AppleTVPlan.make(media: media(hdr), mode: .preserve).videoArguments.contains("copy"))
    }

    func testUnsupportedVideoNeedsExplicitConversionAndTrackLossNeedsConsent() throws {
        let source = try media("\"codec_name\":\"mpeg4\",\"pix_fmt\":\"yuv420p\"")
        XCTAssertThrowsError(try AppleTVPlan.make(media: source, mode: .preserve))
        XCTAssertTrue(try AppleTVPlan.make(media: source, mode: .convert).videoArguments.contains("h264_videotoolbox"))
        let subtitles = try media("\"codec_name\":\"mpeg4\",\"pix_fmt\":\"yuv420p\"", extra: ",{\"index\":1,\"codec_type\":\"subtitle\",\"codec_name\":\"subrip\"}")
        XCTAssertThrowsError(try AppleTVPlan.make(media: subtitles, mode: .convert))
        XCTAssertNoThrow(try AppleTVPlan.make(media: subtitles, mode: .convert, allowTrackLoss: true))
    }

    func testH264PreservationUsesCopyAndAACFallback() throws {
        let media = try AppleTVMedia.decode(Data("""
        {"streams":[{"index":0,"codec_type":"video","codec_name":"h264","profile":"High","pix_fmt":"yuv420p","level":40,"width":1920,"height":1080,"avg_frame_rate":"24/1"},{"index":1,"codec_type":"audio","codec_name":"dts","channels":6,"sample_rate":"48000"}],"format":{"duration":"2.0"}}
        """.utf8))
        let plan = try AppleTVPlan.make(media: media, mode: .preserve)
        XCTAssertTrue(plan.videoArguments.contains("copy"))
        XCTAssertTrue(plan.audioArguments.contains("aac"))
        XCTAssertEqual(plan.videoIndex, 0)
        XCTAssertEqual(plan.audioIndices, [1])
        XCTAssertFalse(plan.videoArguments.contains("h264_videotoolbox"))
    }

    func testPreparationNeverOverwritesAnExistingDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mkv")
        let output = root.appendingPathComponent("result.mp4")
        try Data("source".utf8).write(to: source)
        try Data("keep".utf8).write(to: output)
        do {
            _ = try await AppleTVPreparationService.prepare(source: source, destination: output, mode: .convert)
            XCTFail("Existing destination accepted")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: output), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["result.mp4", "source.mkv"])
    }

    func testRealUnsupportedVideoIsEncodedThenDecodedByAVFoundation() async throws {
        let tools = try AppleTVTools.discover()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("synthetic.mkv"), output = root.appendingPathComponent("encoded.mp4")
        _ = try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "2", "-c:v", "mpeg4", "-c:a", "pcm_s16le", source.path], timeout: 30)
        let original = try Data(contentsOf: source)
        let analyzed = try await AppleTVPreparationService.inspect(source: source)
        XCTAssertEqual(analyzed.videos.first?.codec_name, "mpeg4")
        XCTAssertThrowsError(try AppleTVPlan.make(media: analyzed, mode: .preserve))
        _ = try await AppleTVPreparationService.prepare(source: source, destination: output, mode: .convert)
        let result = try await AppleTVPreparationService.inspect(source: output)
        XCTAssertEqual(result.videos.first?.codec_name, "h264")
        XCTAssertEqual(result.videos.first?.codec_tag_string, "avc1")
        XCTAssertEqual(result.audios.first?.codec_name, "aac")
        try await AppleTVPreparationService.verifyDecodableImage(output)
        _ = try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-xerror", "-i", output.path, "-map", "0:v:0", "-f", "null", "-"], timeout: 30)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".appletv-") })
    }

    func testRealRemuxPreservesDecodedFrames() async throws {
        let tools = try AppleTVTools.discover()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("copy.mkv"), output = root.appendingPathComponent("copy.mp4")
        _ = try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24", "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-g", "1", "-bf", "0", source.path], timeout: 30)
        _ = try await AppleTVPreparationService.prepare(source: source, destination: output, mode: .preserve)
        var hashes: [Data] = []
        for url in [source, output] {
            hashes.append(try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-i", url.path, "-map", "0:v:0", "-f", "hash", "-hash", "sha256", "-"], timeout: 30, capture: true))
        }
        XCTAssertEqual(hashes[0], hashes[1], "Remux must preserve decoded image bytes")
    }

    func testRealHEVCMain10RemuxIsNativeDecodableAndLossless() async throws {
        let tools = try AppleTVTools.discover()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("tenbit.mkv"), output = root.appendingPathComponent("tenbit.mp4")
        _ = try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24", "-t", "1", "-c:v", "libx265", "-pix_fmt", "yuv420p10le", "-x265-params", "pools=1:log-level=error", "-color_trc", "bt709", source.path], timeout: 30)
        _ = try await AppleTVPreparationService.prepare(source: source, destination: output, mode: .preserve)
        let result = try await AppleTVPreparationService.inspect(source: output)
        XCTAssertEqual(result.videos.first?.profile, "Main 10")
        XCTAssertEqual(result.videos.first?.codec_tag_string, "hvc1")
        XCTAssertEqual(result.videos.first?.pix_fmt, "yuv420p10le")
        var hashes: [Data] = []
        for url in [source, output] {
            hashes.append(try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-i", url.path, "-map", "0:v:0", "-f", "hash", "-hash", "sha256", "-"], timeout: 30, capture: true))
        }
        XCTAssertEqual(hashes[0], hashes[1])
    }

    func testRealHDRFixtureIsNeverSilentlyConvertedToSDR() async throws {
        let tools = try AppleTVTools.discover()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("pq.mkv"), output = root.appendingPathComponent("sdr.mp4")
        _ = try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24,format=yuv420p10le,setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc", "-t", "1", "-c:v", "libx265", "-x265-params", "pools=1:log-level=error", source.path], timeout: 30)
        let original = try Data(contentsOf: source)
        let inspected = try await AppleTVPreparationService.inspect(source: source)
        XCTAssertEqual(inspected.videos.first?.color_transfer, "smpte2084")
        do {
            _ = try await AppleTVPreparationService.prepare(source: source, destination: output, mode: .convert)
            XCTFail("HDR was silently converted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("HDR")) }
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["pq.mkv"])
    }

    func testCacheBudgetFailureKeepsSourceAndForeignCacheThenAllowsRestart() async throws {
        let tools = try AppleTVTools.discover()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mkv"), output = root.appendingPathComponent("result.mp4")
        let foreign = root.appendingPathComponent(".appletv-foreign")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false)
        let sentinel = foreign.appendingPathComponent("partial.mp4")
        try Data("not ours".utf8).write(to: sentinel)
        _ = try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24", "-t", "1", "-c:v", "mpeg4", source.path], timeout: 30)
        let original = try Data(contentsOf: source)
        do {
            _ = try await AppleTVPreparationService.prepare(source: source, destination: output, mode: .convert, maximumBytes: 1)
            XCTFail("Budget violation published a file")
        } catch { XCTAssertTrue(error.localizedDescription.contains("cache")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), [".appletv-foreign", "source.mkv"])
        _ = try await AppleTVPreparationService.prepare(source: source, destination: output, mode: .convert)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("not ours".utf8))
    }

    func testPreparationCancellationCleansOnlyOwnedCache() async throws {
        let tools = try AppleTVTools.discover()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mkv"), output = root.appendingPathComponent("result.mp4")
        _ = try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24", "-t", "2", "-c:v", "mpeg4", source.path], timeout: 30)
        let original = try Data(contentsOf: source)
        let task = Task {
            try await AppleTVPreparationService.prepare(source: source, destination: output, mode: .convert)
        }
        // Wait for the exclusive cache rather than canceling before any work began.
        var observedCache = false
        for _ in 0..<200 {
            if try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".appletv-") }) {
                observedCache = true; break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled preparation succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(observedCache)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["source.mkv"])
    }

    func testCancellationStopsOwnedProcessPromptly() async throws {
        let tools = try AppleTVTools.discover()
        let task = Task {
            try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-re", "-f", "lavfi", "-i", "testsrc2=size=64x64:rate=1", "-t", "60", "-f", "null", "-"], timeout: 90)
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        let start = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled process succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
