import Foundation

// MARK: - Codec

public enum AudioCodec: String, Codable, CaseIterable, Sendable, Comparable {
    case flac, alac, wav, aiff, mp3, aac, vorbis, opus, other

    public var displayName: String {
        switch self {
        case .flac: "FLAC"
        case .alac: "ALAC"
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .mp3: "MP3"
        case .aac: "AAC"
        case .vorbis: "Vorbis"
        case .opus: "Opus"
        case .other: "Other"
        }
    }

    public var isLossless: Bool {
        switch self {
        case .flac, .alac, .wav, .aiff: true
        default: false
        }
    }

    private var order: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (lhs: AudioCodec, rhs: AudioCodec) -> Bool { lhs.order < rhs.order }
}

// MARK: - Quality

public enum QualityTier: String, Codable, CaseIterable, Sendable, Comparable {
    case lossy, cd, hiRes

    public var displayName: String {
        switch self {
        case .lossy: "Lossy"
        case .cd: "CD Quality"
        case .hiRes: "Hi-Res"
        }
    }

    private var rank: Int {
        switch self {
        case .lossy: 0
        case .cd: 1
        case .hiRes: 2
        }
    }

    public static func < (lhs: QualityTier, rhs: QualityTier) -> Bool { lhs.rank < rhs.rank }

    /// Lossless with more than 16 bits or more than 48 kHz is Hi-Res; other lossless is CD quality.
    public static func classify(codec: AudioCodec, sampleRate: Double, bitDepth: Int?) -> QualityTier {
        guard codec.isLossless else { return .lossy }
        if (bitDepth ?? 16) > 16 || sampleRate > 48_000 { return .hiRes }
        return .cd
    }
}

public enum Format {
    /// 44100 -> "44.1 kHz", 96000 -> "96 kHz"
    public static func sampleRate(_ rate: Double) -> String {
        let k = rate / 1000
        if k.rounded() == k { return "\(Int(k)) kHz" }
        return String(format: "%.1f kHz", k)
    }

    /// 44100 -> "44.1", 96000 -> "96"
    public static func sampleRateShort(_ rate: Double) -> String {
        let k = rate / 1000
        if k.rounded() == k { return "\(Int(k))" }
        return String(format: "%.1f", k)
    }

    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    public static func longDuration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 { return "\(minutes / 60) hr \(minutes % 60) min" }
        return "\(minutes) min"
    }
}

// MARK: - Track

public struct Track: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }

    public var path: String
    public var title: String
    public var artist: String
    /// The ALBUMARTIST tag as written in the file, if any.
    public var albumArtistTag: String?
    public var album: String
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    public var discTotal: Int?
    public var year: Int?
    public var genre: String?

    public var duration: Double
    public var sampleRate: Double
    /// Bits per sample of the source. nil for lossy codecs (they have no fixed bit depth).
    public var bitDepth: Int?
    public var channels: Int
    /// Average bitrate in kbps.
    public var bitrate: Int?
    public var codec: AudioCodec

    public var fileSize: Int64
    public var modified: Date
    public var added: Date
    public var artworkKey: String?

    public init(path: String, title: String, artist: String, albumArtistTag: String? = nil, album: String,
                trackNumber: Int? = nil, trackTotal: Int? = nil, discNumber: Int? = nil, discTotal: Int? = nil,
                year: Int? = nil, genre: String? = nil, duration: Double, sampleRate: Double, bitDepth: Int?,
                channels: Int, bitrate: Int?, codec: AudioCodec, fileSize: Int64, modified: Date,
                added: Date = Date(), artworkKey: String? = nil) {
        self.path = path
        self.title = title
        self.artist = artist
        self.albumArtistTag = albumArtistTag
        self.album = album
        self.trackNumber = trackNumber
        self.trackTotal = trackTotal
        self.discNumber = discNumber
        self.discTotal = discTotal
        self.year = year
        self.genre = genre
        self.duration = duration
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.bitrate = bitrate
        self.codec = codec
        self.fileSize = fileSize
        self.modified = modified
        self.added = added
        self.artworkKey = artworkKey
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public var albumArtist: String {
        if let a = albumArtistTag, !a.isEmpty { return a }
        return artist
    }

    public var quality: QualityTier { .classify(codec: codec, sampleRate: sampleRate, bitDepth: bitDepth) }

    /// "24-bit / 96 kHz" for lossless, "320 kbps" for lossy.
    public var qualityLabel: String {
        if codec.isLossless {
            return "\(bitDepth ?? 16)-bit / \(Format.sampleRate(sampleRate))"
        }
        if let bitrate { return "\(bitrate) kbps" }
        return Format.sampleRate(sampleRate)
    }

    /// "FLAC 24/96" style compact label.
    public var compactQuality: String {
        if codec.isLossless {
            return "\(codec.displayName) \(bitDepth ?? 16)/\(Format.sampleRateShort(sampleRate))"
        }
        if let bitrate { return "\(codec.displayName) \(bitrate)" }
        return codec.displayName
    }
}

// MARK: - Album

public struct Album: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let year: Int?
    public let genre: String?
    /// Sorted by disc, then track number, then title.
    public let tracks: [Track]
    public let artworkKey: String?
    public let codecs: [AudioCodec]
    public let quality: QualityTier
    public let maxSampleRate: Double
    public let maxBitDepth: Int?
    public let duration: Double
    public let added: Date
    public let discCount: Int
    /// Lowercased, diacritic-folded text used for searching.
    public let searchText: String

    public var decade: Int? { year.map { $0 / 10 * 10 } }

    /// "FLAC · 24/96" — summarises the album's best source quality.
    public var qualitySummary: String {
        let codecNames = codecs.map(\.displayName).joined(separator: "/")
        if quality == .lossy {
            let rates = tracks.compactMap(\.bitrate)
            if let maxRate = rates.max() { return "\(codecNames) · \(maxRate) kbps" }
            return codecNames
        }
        return "\(codecNames) · \(maxBitDepth ?? 16)/\(Format.sampleRateShort(maxSampleRate))"
    }
}

public struct ArtistSummary: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let albumIDs: [String]
    public let trackCount: Int
    public let artworkKey: String?
}

public extension String {
    /// Lowercased, accent-insensitive form used for searching and sorting.
    var folded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Sort key that ignores a leading "The ".
    var sortKey: String {
        let f = folded
        if f.hasPrefix("the ") { return String(f.dropFirst(4)) }
        return f
    }
}
