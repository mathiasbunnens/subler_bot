import Foundation

public enum AppleTVMode: String, CaseIterable, Sendable {
    case preserve = "Préserver la vidéo"
    case convert = "Convertir pour Apple TV"
    case hdr10 = "HEVC 10 bits HDR10"
}

/// Narrow, fail-closed profile: H.264 SDR for Apple TV HD; HEVC for Apple TV 4K.
public struct AppleTVMedia: Decodable, Sendable {
    public struct Stream: Decodable, Sendable {
        public let index: Int
        public let codec_type: String?
        public let codec_name: String?
        public let codec_tag_string: String?
        public let profile: String?
        public let pix_fmt: String?
        public let level: Int?
        public let width: Int?
        public let height: Int?
        public let avg_frame_rate: String?
        public let sample_aspect_ratio: String?
        public let color_transfer: String?
        public let color_primaries: String?
        public let color_space: String?
        public let color_range: String?
        public let channels: Int?
        public let sample_rate: String?
        public let disposition: Disposition?
        public let side_data_list: [SideData]?
        public struct Disposition: Decodable, Sendable { public let attached_pic: Int? }
        public struct SideData: Decodable, Sendable {
            public let side_data_type: String?
            public let dv_profile: Int?
            public let dv_bl_signal_compatibility_id: Int?
            public let bl_present_flag: Int?
            public let el_present_flag: Int?
            public let rpu_present_flag: Int?
            public let red_x: String?
            public let red_y: String?
            public let green_x: String?
            public let green_y: String?
            public let blue_x: String?
            public let blue_y: String?
            public let white_point_x: String?
            public let white_point_y: String?
            public let min_luminance: String?
            public let max_luminance: String?
            public let max_content: Int?
            public let max_average: Int?
        }
        var attached: Bool { disposition?.attached_pic == 1 }
        var fps: Double {
            let parts = (avg_frame_rate ?? "").split(separator: "/").compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0 { return parts[0] / parts[1] }
            return parts.count == 1 ? parts[0] : 0
        }
        var dolbyVision: Bool {
            side_data_list?.contains {
                $0.dv_profile != nil || ($0.side_data_type ?? "").localizedCaseInsensitiveContains("dovi") ||
                ($0.side_data_type ?? "").localizedCaseInsensitiveContains("Dolby Vision")
            } == true
        }
        var hdr: Bool {
            ["smpte2084", "arib-std-b67"].contains(color_transfer ?? "") || color_primaries == "bt2020" ||
            side_data_list?.contains { ($0.side_data_type ?? "").contains("Mastering display") || ($0.side_data_type ?? "").contains("Content light") } == true
        }
    }
    public struct Format: Decodable, Sendable { public let duration: String? }
    public let streams: [Stream]
    public let format: Format?
    public var duration: Double { Double(format?.duration ?? "") ?? 0 }
    public var videos: [Stream] { streams.filter { $0.codec_type == "video" && !$0.attached } }
    public var audios: [Stream] { streams.filter { $0.codec_type == "audio" } }
    public static func decode(_ data: Data) throws -> Self { try JSONDecoder().decode(Self.self, from: data) }
    public var diagnostic: String {
        streams.filter { !$0.attached }.map {
            let dv = $0.side_data_list?.compactMap(\.dv_profile).first
            let vision = dv.map { " ; Dolby Vision profil \($0)" } ?? ($0.dolbyVision ? " ; Dolby Vision profil inconnu" : "")
            return "Piste \($0.index) : \($0.codec_type ?? "?") / \($0.codec_name ?? "?") / tag \($0.codec_tag_string ?? "—") / \($0.profile ?? "—") / \($0.pix_fmt ?? "—") ; niveau \($0.level.map(String.init) ?? "—") ; \($0.width ?? 0)×\($0.height ?? 0) ; cadence \($0.avg_frame_rate ?? "inconnue") ; transfert \($0.color_transfer ?? "inconnu") ; canaux \($0.channels.map(String.init) ?? "—") / \($0.sample_rate ?? "—") Hz\(vision)"
        }.joined(separator: "\n")
    }
}

public struct AppleTVPlan: Sendable {
    public let videoIndex: Int
    public let audioIndices: [Int]
    public let videoArguments: [String]
    public let audioArguments: [String]
    public let summary: String

    public static func make(media: AppleTVMedia, mode: AppleTVMode, allowTrackLoss: Bool = false,
                            allowDynamicHDRLoss: Bool = false) throws -> Self {
        func refuse(_ text: String) -> AutomationServiceError { .message(text) }
        guard media.duration.isFinite, media.duration > 0, media.videos.count == 1, let video = media.videos.first else {
            throw refuse("Une seule piste vidéo lisible et une durée positive sont requises.")
        }
        guard !video.dolbyVision || mode == .hdr10 else {
            throw refuse("Dolby Vision détecté : profil/RPU non validés par cette préparation. Aucun remux ni réencodage automatique ; original conservé.")
        }
        let lostTracks = media.streams.contains { $0.codec_type != "audio" && $0.codec_type != "video" || $0.attached }
        guard !lostTracks || allowTrackLoss else {
            throw refuse("Sous-titres, pièces jointes ou données non repris : accord explicite requis. Les pistes audio sont toutes conservées ou converties en AAC stéréo.")
        }
        let dimensionsOK = (video.width ?? 0) > 0 && (video.height ?? 0) > 0
        let fpsOK = video.fps.isFinite && video.fps > 0
        let baseline = ["Baseline", "Constrained Baseline"].contains(video.profile ?? "")
        let h264 = video.codec_name == "h264" && ["Baseline", "Constrained Baseline", "Main", "High"].contains(video.profile ?? "") &&
            video.pix_fmt == "yuv420p" && (video.level ?? 999) <= (baseline ? 30 : 42) &&
            (video.width ?? 99999) <= 1920 && (video.height ?? 99999) <= 1080 && video.fps <= 60 && !video.hdr
        let hevc = video.codec_name == "hevc" && ["Main", "Main 10"].contains(video.profile ?? "") &&
            ["yuv420p", "yuv420p10le"].contains(video.pix_fmt ?? "") && (video.level ?? 999) <= 153 &&
            (video.width ?? 99999) <= 3840 && (video.height ?? 99999) <= 2160 && video.fps <= 60
        let hdr10 = !video.hdr || (video.profile == "Main 10" && video.pix_fmt == "yuv420p10le" &&
            video.color_transfer == "smpte2084" && video.color_primaries == "bt2020" && video.color_space == "bt2020nc" &&
            video.side_data_list?.contains { ($0.side_data_type ?? "").contains("Mastering display") } == true)
        let args: [String]
        let description: String
        switch mode {
        case .hdr10:
            _ = try HDR10Metadata(video: video)
            guard allowDynamicHDRLoss else {
                throw refuse("Accord explicite requis : réencodage avec perte, suppression Dolby Vision et HDR10+ dynamiques si présents ; sortie HDR10 statique uniquement.")
            }
            guard dimensionsOK, fpsOK, hevc,
                  video.sample_aspect_ratio == nil || ["1:1", "0:1", "N/A"].contains(video.sample_aspect_ratio!) else {
                throw refuse("HDR10 : seules les sources HEVC Main 10 4:2:0 ≤4K60 à pixels carrés sont validées ; aucune conversion couleur, cadence ou résolution implicite.")
            }
            // Planar -> semiplanar 10-bit only; no scale, tone mapping or color conversion.
            // Never pass source RPUs to newly encoded pixels.
            args = ["-c:v", "hevc_videotoolbox", "-allow_sw", "0", "-profile:v", "main10", "-pix_fmt", "p010le",
                    "-b:v", "25M", "-color_primaries", "bt2020", "-color_trc", "smpte2084", "-colorspace", "bt2020nc", "-color_range", "tv",
                    "-vf", "sidedata=delete:type=DOVI_RPU_BUFFER,sidedata=delete:type=DOVI_METADATA,sidedata=delete:type=DYNAMIC_HDR_PLUS",
                    "-tag:v", "hvc1"]
            description = "Réencodage matériel avec perte HEVC Main 10 HDR10, 25 Mbit/s — Apple TV 4K. BT.2020/PQ et métadonnées statiques conservés et vérifiés ; Dolby Vision/RPU et HDR10+ dynamiques supprimés. Aucun repli logiciel ; échec si VideoToolbox ne préserve pas le HDR10."
        case .preserve:
            guard dimensionsOK, fpsOK, (h264 || hevc), hdr10 else {
                throw refuse("Vidéo hors profil conservateur Apple TV : copie refusée. Conversion SDR possible seulement sur sélection explicite ; HDR/HLG non validé reste bloqué.")
            }
            args = ["-c:v", "copy", "-tag:v", hevc ? "hvc1" : "avc1"]
            description = hevc ? "Copie HEVC sans réencodage — Apple TV 4K, HDR10 si présent." : "Copie H.264 sans réencodage — Apple TV HD/4K."
        case .convert:
            let knownSDR = ["bt709", "smpte170m", "iec61966-2-1"].contains(video.color_transfer ?? "")
            let untaggedEightBit = (video.color_transfer == nil || video.color_transfer == "unknown") &&
                ["yuv420p", "yuv422p", "yuv444p", "nv12"].contains(video.pix_fmt ?? "")
            guard !video.hdr, knownSDR || untaggedEightBit else {
                throw refuse("Réencodage HDR/HLG ou transfert inconnu non pris en charge : aucun faux HDR ni conversion SDR silencieuse.")
            }
            guard dimensionsOK, fpsOK else { throw refuse("Dimensions ou cadence inconnues : conversion refusée.") }
            guard video.sample_aspect_ratio == nil || ["1:1", "0:1", "N/A"].contains(video.sample_aspect_ratio!) else {
                throw refuse("Vidéo anamorphique : conversion non validée, afin de ne pas déformer l’image. Préservation possible si le codec est compatible.")
            }
            args = ["-c:v", "h264_videotoolbox", "-allow_sw", "0", "-profile:v", "high", "-level:v", "4.1", "-b:v", "8M", "-maxrate", "10M", "-bufsize", "20M", "-pix_fmt", "yuv420p", "-vf", "scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1", "-r", "30", "-tag:v", "avc1"]
            description = "Réencodage avec perte H.264 SDR, maximum 1080p30, 8 Mbit/s — Apple TV HD/4K."
        }
        let copyAudio = media.audios.allSatisfy { $0.codec_name == "aac" && $0.profile == "LC" && ($0.channels ?? 99) <= 2 && (Int($0.sample_rate ?? "") ?? 999999) <= 48000 }
        let audioArgs = copyAudio ? ["-c:a", "copy"] : ["-c:a", "aac", "-profile:a", "aac_low", "-b:a", "256k", "-ac", "2", "-ar", "48000"]
        return Self(videoIndex: video.index, audioIndices: media.audios.map(\.index), videoArguments: args, audioArguments: audioArgs,
                    summary: description + (copyAudio ? " Audio AAC copié." : " Audio converti en AAC stéréo (perte surround/Atmos).") + (lostTracks ? " Sous-titres/pièces jointes/données exclus avec accord." : ""))
    }

    public func arguments(source: URL, output: URL) -> [String] {
        var args = ["-hide_banner", "-v", "error", "-nostdin", "-n", "-i", source.path, "-map", "0:\(videoIndex)"]
        for index in audioIndices { args += ["-map", "0:\(index)"] }
        return args + videoArguments + audioArguments + ["-map_metadata", "0", "-map_chapters", "0", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", "-f", "mp4", output.path]
    }
}
