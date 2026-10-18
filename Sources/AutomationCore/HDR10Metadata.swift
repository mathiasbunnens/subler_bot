import Foundation

/// Static HDR10 values, not a claim that ten-bit pixels alone constitute HDR.
internal struct HDR10Metadata: Equatable {
    let chromaticities: [Double]
    let minimumLuminance: Double
    let maximumLuminance: Double
    let maximumContent: Int
    let maximumAverage: Int

    init(video: AppleTVMedia.Stream) throws {
        let failure = AutomationServiceError.message("HDR10 exige HEVC Main 10 4:2:0, BT.2020/PQ limité et des métadonnées mastering/CLL complètes et valides. HLG, SDR et conversions couleur non implémentées sont refusés.")
        guard video.codec_name == "hevc", video.profile == "Main 10", video.pix_fmt == "yuv420p10le",
              video.color_transfer == "smpte2084", video.color_primaries == "bt2020",
              video.color_space == "bt2020nc", video.color_range == "tv" else { throw failure }
        let side = video.side_data_list ?? []
        if video.dolbyVision {
            let configs = side.filter { $0.dv_profile != nil }
            guard configs.count == 1, let dv = configs.first, dv.dv_profile == 8,
                  dv.dv_bl_signal_compatibility_id == 1, dv.bl_present_flag == 1,
                  dv.el_present_flag == 0, dv.rpu_present_flag == 1 else {
                throw AutomationServiceError.message("Dolby Vision : seule une base HDR10 explicitement compatible profil 8.1 sans enhancement layer est acceptée ; RPU jamais recopiées.")
            }
        }
        let masters = side.filter { $0.side_data_type == "Mastering display metadata" }
        let lights = side.filter { $0.side_data_type == "Content light level metadata" }
        guard let master = masters.first, let light = lights.first else { throw failure }
        func rational(_ text: String?) throws -> Double {
            let parts = (text ?? "").split(separator: "/").compactMap { Double($0) }
            guard parts.count == 2, parts[0].isFinite, parts[1].isFinite, parts[1] > 0 else { throw failure }
            let value = parts[0] / parts[1]
            guard value.isFinite, value >= 0 else { throw failure }
            return value
        }
        chromaticities = try [master.red_x, master.red_y, master.green_x, master.green_y,
                              master.blue_x, master.blue_y, master.white_point_x, master.white_point_y].map(rational)
        minimumLuminance = try rational(master.min_luminance)
        maximumLuminance = try rational(master.max_luminance)
        guard chromaticities.allSatisfy({ $0 > 0 && $0 <= 1 }), maximumLuminance > minimumLuminance,
              maximumLuminance <= 10000, let content = light.max_content, let average = light.max_average,
              content > 0, content <= 10000, average > 0, average <= content else { throw failure }
        maximumContent = content
        maximumAverage = average
    }
}

extension AppleTVPlan {
    /// Publication gate independent of whether FFmpeg returned success.
    public static func validateHDR10Output(source: AppleTVMedia, output: AppleTVMedia) throws {
        guard let original = source.videos.first, output.videos.count == 1, let encoded = output.videos.first else {
            throw AutomationServiceError.message("Piste HDR10 absente : publication bloquée.")
        }
        guard !encoded.dolbyVision,
              !(encoded.side_data_list ?? []).contains(where: {
                  let type = ($0.side_data_type ?? "").lowercased()
                  return type.contains("dynamic") || type.contains("2094") || type.contains("dovi") || type.contains("dolby")
              }),
              encoded.codec_tag_string == "hvc1", original.width == encoded.width, original.height == encoded.height,
              abs(original.fps - encoded.fps) < 0.001,
              try HDR10Metadata(video: original) == HDR10Metadata(video: encoded) else {
            throw AutomationServiceError.message("Métadonnées HDR10, dimensions ou cadence altérées, ou signal Dolby Vision/HDR10+ résiduel : publication bloquée.")
        }
    }
}
