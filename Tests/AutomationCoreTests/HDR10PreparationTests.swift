import XCTest
@testable import AutomationCore

final class HDR10PreparationTests: XCTestCase {
    private let mastering = """
    {"side_data_type":"Mastering display metadata","red_x":"34000/50000","red_y":"16000/50000","green_x":"13250/50000","green_y":"34500/50000","blue_x":"7500/50000","blue_y":"3000/50000","white_point_x":"15635/50000","white_point_y":"16450/50000","min_luminance":"50/10000","max_luminance":"40000000/10000"},{"side_data_type":"Content light level metadata","max_content":1100,"max_average":668}
    """
    private func source(transfer: String = "smpte2084", pixel: String = "yuv420p10le", extra: String = "", metadata: String? = nil) throws -> AppleTVMedia {
        try AppleTVMedia.decode(Data("""
        {"streams":[{"index":0,"codec_type":"video","codec_name":"hevc","codec_tag_string":"hvc1","profile":"Main 10","pix_fmt":"\(pixel)","level":120,"width":320,"height":180,"avg_frame_rate":"24/1","color_transfer":"\(transfer)","color_primaries":"bt2020","color_space":"bt2020nc","color_range":"tv","side_data_list":[\(metadata ?? mastering)\(extra)]}],"format":{"duration":"1"}}
        """.utf8))
    }
    func testHDR10RequiresExplicitDynamicLossConsentAndRealTenBitPQ() throws {
        let media = try source()
        XCTAssertThrowsError(try AppleTVPlan.make(media: media, mode: .hdr10))
        let plan = try AppleTVPlan.make(media: media, mode: .hdr10, allowDynamicHDRLoss: true)
        XCTAssertTrue(plan.videoArguments.contains("hevc_videotoolbox"))
        XCTAssertTrue(plan.videoArguments.contains("p010le"))
        XCTAssertFalse(plan.videoArguments.contains("copy"))
        XCTAssertTrue(plan.videoArguments.joined().contains("DOVI_RPU_BUFFER"))
        XCTAssertTrue(try AppleTVPlan.make(media: media, mode: .preserve).videoArguments.contains("copy"))
        for invalid in [try source(transfer: "arib-std-b67"), try source(transfer: "bt709"), try source(pixel: "yuv420p"), try source(metadata: "") ] {
            XCTAssertThrowsError(try AppleTVPlan.make(media: invalid, mode: .hdr10, allowDynamicHDRLoss: true))
        }
    }
    func testOnlyExplicitlyHDR10CompatibleDolbyVisionBaseIsAccepted() throws {
        for (profile, compatibility) in [(5, 0), (7, 1), (8, 0), (8, 1)] {
            let media = try source(extra: ",{\"side_data_type\":\"DOVI configuration record\",\"dv_profile\":\(profile),\"dv_bl_signal_compatibility_id\":\(compatibility),\"bl_present_flag\":1,\"el_present_flag\":0,\"rpu_present_flag\":1}")
            XCTAssertThrowsError(try AppleTVPlan.make(media: media, mode: .hdr10))
            if profile == 8 && compatibility == 1 {
                XCTAssertNoThrow(try AppleTVPlan.make(media: media, mode: .hdr10, allowDynamicHDRLoss: true))
            } else {
                XCTAssertThrowsError(try AppleTVPlan.make(media: media, mode: .hdr10, allowDynamicHDRLoss: true))
            }
            XCTAssertThrowsError(try AppleTVPlan.make(media: media, mode: .preserve))
        }
    }
    func testPublicationRejectsMissingOrChangedStaticMetadataAndDynamicResidue() throws {
        let original = try source()
        XCTAssertNoThrow(try AppleTVPlan.validateHDR10Output(source: original, output: original))
        for bad in [try source(metadata: mastering.replacingOccurrences(of: "1100", with: "1000")),
                    try source(metadata: ""), try source(transfer: "bt709"),
                    try source(extra: ",{\"side_data_type\":\"Dolby Vision RPU Data\"}")] {
            XCTAssertThrowsError(try AppleTVPlan.validateHDR10Output(source: original, output: bad))
        }
        let orphanRPU = try source(extra: ",{\"side_data_type\":\"Dolby Vision RPU Data\"}")
        XCTAssertThrowsError(try AppleTVPlan.make(media: orphanRPU, mode: .hdr10, allowDynamicHDRLoss: true))
    }
    func testRealHardwareHDR10EncodingPreservesStaticMetadataAndCodeValues() async throws {
        let tools = try AppleTVTools.discover()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("hdr.mkv"), output = root.appendingPathComponent("hdr.mp4")
        // Moving colors on the left, full legal PQ code-value ramp on the right:
        // a silent SDR clipping/range transform must not pass merely by retaining labels.
        let pattern = "testsrc2=size=320x180:rate=24,format=yuv420p10le,geq=lum='if(lt(X,W/2),lum(X,Y),64+876*(X-W/2)/(W/2-1))':cb='if(lt(X,W/2),cb(X,Y),512)':cr='if(lt(X,W/2),cr(X,Y),512)',setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc:range=limited"
        _ = try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", pattern, "-t", "1", "-c:v", "libx265", "-x265-params", "pools=1:log-level=error:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(40000000,50):max-cll=1100,668", input.path], timeout: 30)
        let original = try Data(contentsOf: input)
        let before = try await AppleTVPreparationService.inspect(source: input)
        XCTAssertNoThrow(try HDR10Metadata(video: XCTUnwrap(before.videos.first)))
        _ = try await AppleTVPreparationService.prepare(source: input, destination: output, mode: .hdr10, allowDynamicHDRLoss: true)
        let after = try await AppleTVPreparationService.inspect(source: output)
        try AppleTVPlan.validateHDR10Output(source: before, output: after)
        XCTAssertEqual(after.videos.first?.codec_tag_string, "hvc1")
        try await AppleTVPreparationService.verifyDecodableImage(output)
        // Compare decoded 10-bit samples with PSNR, not bit equality: this is lossy encoding.
        let stats = root.appendingPathComponent("psnr.log")
        _ = try await PreparationProcess.run(tools.ffmpeg, ["-v", "error", "-i", input.path, "-i", output.path, "-lavfi", "[0:v]settb=1/24,setpts=N[a];[1:v]settb=1/24,setpts=N[b];[a][b]psnr=stats_file=\(stats.path):shortest=1", "-fps_mode", "passthrough", "-f", "null", "-"], timeout: 30)
        let lines = try String(contentsOf: stats).split(separator: "\n")
        XCTAssertEqual(lines.count, 24)
        for line in lines {
            let value = line.split(separator: " ").first { $0.hasPrefix("psnr_avg:") }.flatMap { Double($0.dropFirst(9)) }
            XCTAssertGreaterThan(try XCTUnwrap(value), 35, "Unexpected color/range transform or severe clipping")
        }
        XCTAssertEqual(try Data(contentsOf: input), original)
        // The selected HDR path uses the same disk/cancellation guards as older profiles.
        let refused = root.appendingPathComponent("budget.mp4")
        do {
            _ = try await AppleTVPreparationService.prepare(source: input, destination: refused, mode: .hdr10, allowDynamicHDRLoss: true, maximumBytes: 1)
            XCTFail("Budget exceeded")
        } catch { XCTAssertTrue(error.localizedDescription.contains("cache")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: refused.path))
        let cancelled = root.appendingPathComponent("cancelled.mp4")
        let task = Task {
            try await AppleTVPreparationService.prepare(source: input, destination: cancelled, mode: .hdr10, allowDynamicHDRLoss: true)
        }
        var observed = false
        for _ in 0..<400 {
            if try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".appletv-") }) { observed = true; break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled HDR encode published") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(observed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.path))
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".appletv-") })
    }
}
