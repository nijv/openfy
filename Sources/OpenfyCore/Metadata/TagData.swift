import Foundation

/// Tags read from a file. Every field is optional; missing values are filled in from the folder structure.
public struct TagData: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    public var discTotal: Int?
    public var year: Int?
    public var genre: String?
    public var artwork: Data?

    public init() {}

    /// Fills fields that are empty here with values from `other`.
    public mutating func merge(fallback other: TagData) {
        title = title.nonEmpty ?? other.title
        artist = artist.nonEmpty ?? other.artist
        albumArtist = albumArtist.nonEmpty ?? other.albumArtist
        album = album.nonEmpty ?? other.album
        trackNumber = trackNumber ?? other.trackNumber
        trackTotal = trackTotal ?? other.trackTotal
        discNumber = discNumber ?? other.discNumber
        discTotal = discTotal ?? other.discTotal
        year = year ?? other.year
        genre = genre.nonEmpty ?? other.genre
        artwork = artwork ?? other.artwork
    }

    var isEmpty: Bool {
        title == nil && artist == nil && album == nil && trackNumber == nil && artwork == nil
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

enum TagParsing {
    /// "3", "03", "3/12" -> (3, 12)
    static func numberPair(_ s: String?) -> (Int?, Int?) {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return (nil, nil) }
        let parts = s.split(separator: "/", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let n = parts.first.flatMap { Int($0) }
        let total = parts.count > 1 ? Int(parts[1]) : nil
        return (n.flatMap { $0 > 0 ? $0 : nil }, total.flatMap { $0 > 0 ? $0 : nil })
    }

    /// "2001", "2001-05-01", "2001-05-01T00:00:00Z" -> 2001
    static func year(_ s: String?) -> Int? {
        guard let s else { return nil }
        let digits = s.trimmingCharacters(in: .whitespaces).prefix(4)
        guard digits.count == 4, let y = Int(digits), (1000...2999).contains(y) else { return nil }
        return y
    }

    /// Resolves ID3-style genres: "(17)", "17", "(17)Rock", "Rock".
    static func genre(_ s: String?) -> String? {
        guard var g = s?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty else { return nil }
        if g.hasPrefix("("), let close = g.firstIndex(of: ")") {
            let inner = g[g.index(after: g.startIndex)..<close]
            let rest = g[g.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
            g = String(inner)
        }
        if let n = Int(g) {
            return n >= 0 && n < id3Genres.count ? id3Genres[n] : nil
        }
        return g
    }

    static let id3Genres = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
        "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop",
        "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House", "Game",
        "Sound Clip", "Gospel", "Noise", "Alternative Rock", "Bass", "Soul", "Punk", "Space", "Meditative",
        "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic", "Darkwave", "Techno-Industrial",
        "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
        "Psychedelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka",
        "Retro", "Musical", "Rock & Roll", "Hard Rock", "Folk", "Folk-Rock", "National Folk", "Swing",
        "Fast Fusion", "Bebop", "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde", "Gothic Rock",
        "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock", "Big Band", "Chorus",
        "Easy Listening", "Acoustic", "Humour", "Speech", "Chanson", "Opera", "Chamber Music", "Sonata",
        "Symphony", "Booty Bass", "Primus", "Porn Groove", "Satire", "Slow Jam", "Club", "Tango", "Samba",
        "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle", "Duet", "Punk Rock", "Drum Solo",
        "A Cappella", "Euro-House", "Dance Hall",
    ]
}

/// Bounds-checked big/little-endian reads over a byte buffer.
struct ByteReader {
    let data: [UInt8]
    var offset: Int = 0

    init(_ data: [UInt8]) { self.data = data }
    init(_ data: Data) { self.data = [UInt8](data) }

    var remaining: Int { data.count - offset }

    mutating func u8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func u32be() -> UInt32? {
        guard remaining >= 4 else { return nil }
        defer { offset += 4 }
        return data[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func u32le() -> UInt32? {
        guard remaining >= 4 else { return nil }
        defer { offset += 4 }
        return data[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func bytes(_ n: Int) -> [UInt8]? {
        guard n >= 0, remaining >= n else { return nil }
        defer { offset += n }
        return Array(data[offset..<offset + n])
    }

    mutating func skip(_ n: Int) -> Bool {
        guard n >= 0, remaining >= n else { return false }
        offset += n
        return true
    }
}

extension FileHandle {
    func readBytes(_ count: Int) -> [UInt8]? {
        guard count >= 0, let d = try? read(upToCount: count), d.count == count else { return nil }
        return [UInt8](d)
    }
}
