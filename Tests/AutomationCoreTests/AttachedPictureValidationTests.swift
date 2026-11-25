import XCTest
@testable import AutomationCore

/// MKV cover art (attachment / attached picture) must not count as a playable video track.
final class AttachedPictureValidationTests: XCTestCase {
    private func counts(_ json: String) throws -> MediaValidationService.ProbeCounts {
        try MediaValidationService.probeCounts(fromProbeJSON: json)
    }

    func testPNGCoverAttachmentIsNotVideo() throws {
        // Real shape of the failing OSS 117 source (hevc + ac3 + subrip + 2 PGS + cover.png).
        let json = """
        {"streams":[
          {"codec_name":"hevc","codec_type":"video","disposition":{"attached_pic":0}},
          {"codec_name":"ac3","codec_type":"audio","disposition":{"attached_pic":0}},
          {"codec_name":"subrip","codec_type":"subtitle","disposition":{"attached_pic":0}},
          {"codec_name":"hdmv_pgs_subtitle","codec_type":"subtitle"},
          {"codec_name":"hdmv_pgs_subtitle","codec_type":"subtitle"},
          {"codec_name":"png","codec_type":"video","disposition":{"attached_pic":0},"tags":{"filename":"cover.png","mimetype":"image/png"}}
        ],"format":{"duration":"5964.5"}}
        """
        let c = try counts(json)
        XCTAssertEqual(c.video, 1)
        XCTAssertEqual(c.audio, 1)
        XCTAssertEqual(c.duration, 5964.5, accuracy: 0.001)
    }

    func testMJPEGAttachedPicIsNotVideo() throws {
        let json = """
        {"streams":[
          {"codec_name":"h264","codec_type":"video","disposition":{"attached_pic":0}},
          {"codec_name":"aac","codec_type":"audio"},
          {"codec_name":"mjpeg","codec_type":"video","disposition":{"attached_pic":1}}
        ],"format":{"duration":"10"}}
        """
        XCTAssertEqual(try counts(json).video, 1)
    }

    func testImageMimetypeOrFilenameTagIsNotVideo() throws {
        let json = """
        {"streams":[
          {"codec_name":"h264","codec_type":"video"},
          {"codec_name":"unknown","codec_type":"video","tags":{"mimetype":"image/jpeg"}},
          {"codec_name":"unknown2","codec_type":"video","tags":{"filename":"poster.jpg"}}
        ],"format":{"duration":"10"}}
        """
        XCTAssertEqual(try counts(json).video, 1)
    }

    func testTwoRealVideosStillCountTwo() throws {
        let json = """
        {"streams":[
          {"codec_name":"hevc","codec_type":"video","disposition":{"attached_pic":0}},
          {"codec_name":"h264","codec_type":"video","disposition":{"attached_pic":0}},
          {"codec_name":"aac","codec_type":"audio"}
        ],"format":{"duration":"10"}}
        """
        XCTAssertEqual(try counts(json).video, 2)
    }

    func testAudioCountUnchanged() throws {
        let json = """
        {"streams":[
          {"codec_name":"hevc","codec_type":"video"},
          {"codec_name":"ac3","codec_type":"audio"},
          {"codec_name":"dts","codec_type":"audio"},
          {"codec_name":"png","codec_type":"video","tags":{"filename":"cover.png","mimetype":"image/png"}}
        ],"format":{"duration":"10"}}
        """
        let c = try counts(json)
        XCTAssertEqual(c.video, 1)
        XCTAssertEqual(c.audio, 2)
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try counts("not json"))
    }
}
