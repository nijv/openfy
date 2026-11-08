import Foundation

/// Albums, artists and facets derived from the flat track list.
public struct LibraryIndex: Sendable {
    public var albums: [Album] = []
    public var albumsByID: [String: Album] = [:]
    public var artists: [ArtistSummary] = []
    public var genres: [String] = []
    public var decades: [Int] = []
    public var codecs: [AudioCodec] = []

    public init() {}

    /// Tracks belong to the same album when they share an album title and either the same
    /// ALBUMARTIST tag or (untagged) the same folder — so compilations stay together.
    public static func albumKey(for t: Track) -> String {
        let album = t.album.folded
        if let aa = t.albumArtistTag, !aa.isEmpty {
            return "\(album)\u{1F}aa:\(aa.folded)"
        }
        var dir = t.url.deletingLastPathComponent()
        if dir.lastPathComponent.firstMatch(of: #/^(?i)(?:cd|disc|disk)\s*\d+$/#) != nil {
            dir = dir.deletingLastPathComponent()
        }
        return "\(album)\u{1F}dir:\(dir.path.lowercased())"
    }

    public static func build(_ tracks: [Track]) -> LibraryIndex {
        var index = LibraryIndex()
        let groups = Dictionary(grouping: tracks, by: albumKey(for:))

        var albums: [Album] = []
        albums.reserveCapacity(groups.count)
        for (key, group) in groups {
            let sorted = group.sorted { a, b in
                let da = a.discNumber ?? 1, db = b.discNumber ?? 1
                if da != db { return da < db }
                let ta = a.trackNumber ?? Int.max, tb = b.trackNumber ?? Int.max
                if ta != tb { return ta < tb }
                return a.path.localizedStandardCompare(b.path) == .orderedAscending
            }
            let first = sorted[0]

            let artist: String
            if let aa = mostCommon(sorted.compactMap { $0.albumArtistTag.nonEmpty }) {
                artist = aa
            } else if Set(sorted.map { $0.artist.folded }).count == 1 {
                artist = first.artist
            } else {
                artist = "Various Artists"
            }

            let codecs = Array(Set(sorted.map(\.codec))).sorted()
            let lossless = sorted.filter { $0.codec.isLossless }
            let searchText = ([first.album, artist, first.genre ?? "", first.year.map(String.init) ?? ""]
                + sorted.map(\.title) + sorted.map(\.artist)).joined(separator: " ").folded

            albums.append(Album(
                id: key,
                title: first.album,
                artist: artist,
                year: sorted.compactMap(\.year).min(),
                genre: mostCommon(sorted.compactMap(\.genre)),
                tracks: sorted,
                artworkKey: sorted.first(where: { $0.artworkKey != nil })?.artworkKey,
                codecs: codecs,
                quality: sorted.map(\.quality).max() ?? .lossy,
                maxSampleRate: (lossless.isEmpty ? sorted : lossless).map(\.sampleRate).max() ?? 0,
                maxBitDepth: lossless.compactMap(\.bitDepth).max(),
                duration: sorted.reduce(0) { $0 + $1.duration },
                added: sorted.map(\.added).min() ?? Date(),
                discCount: Set(sorted.map { $0.discNumber ?? 1 }).count,
                searchText: searchText
            ))
        }

        albums.sort { a, b in
            if a.artist.sortKey != b.artist.sortKey { return a.artist.sortKey < b.artist.sortKey }
            if a.year != b.year { return (a.year ?? 0) < (b.year ?? 0) }
            return a.title.sortKey < b.title.sortKey
        }
        index.albums = albums
        index.albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })

        let byArtist = Dictionary(grouping: albums, by: { $0.artist })
        index.artists = byArtist.map { name, list in
            let ordered = list.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
            return ArtistSummary(name: name, albumIDs: ordered.map(\.id),
                                 trackCount: list.reduce(0) { $0 + $1.tracks.count },
                                 artworkKey: ordered.last(where: { $0.artworkKey != nil })?.artworkKey)
        }.sorted { $0.name.sortKey < $1.name.sortKey }

        index.genres = Array(Set(albums.compactMap(\.genre))).sorted { $0.folded < $1.folded }
        index.decades = Array(Set(albums.compactMap(\.decade))).sorted(by: >)
        index.codecs = Array(Set(tracks.map(\.codec))).sorted()
        return index
    }

    static func mostCommon(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
    }
}

// MARK: - Filtering & sorting

public enum AlbumSort: String, CaseIterable, Sendable, Identifiable {
    case artist, title, year, recentlyAdded, quality
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .artist: "Artist"
        case .title: "Title"
        case .year: "Year"
        case .recentlyAdded: "Recently Added"
        case .quality: "Quality"
        }
    }

    public func sort(_ albums: [Album]) -> [Album] {
        switch self {
        case .artist: return albums // index order is already artist / year / title
        case .title: return albums.sorted { $0.title.sortKey < $1.title.sortKey }
        case .year: return albums.sorted { ($0.year ?? 0, $0.artist.sortKey) > ($1.year ?? 0, $1.artist.sortKey) }
        case .recentlyAdded: return albums.sorted { $0.added > $1.added }
        case .quality:
            return albums.sorted {
                ($0.quality, $0.maxBitDepth ?? 0, $0.maxSampleRate) > ($1.quality, $1.maxBitDepth ?? 0, $1.maxSampleRate)
            }
        }
    }
}

public struct LibraryFilter: Equatable, Sendable {
    public var search = ""
    public var qualities: Set<QualityTier> = []
    public var codecs: Set<AudioCodec> = []
    public var genre: String?
    public var decade: Int?

    public init() {}

    public var hasFacets: Bool { !qualities.isEmpty || !codecs.isEmpty || genre != nil || decade != nil }
    public var isActive: Bool { hasFacets || !tokens.isEmpty }

    var tokens: [String] {
        search.folded.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public func apply(_ albums: [Album]) -> [Album] {
        guard isActive else { return albums }
        let tokens = self.tokens
        return albums.filter { matches($0, tokens: tokens) }
    }

    public func apply(_ tracks: [Track]) -> [Track] {
        guard isActive else { return tracks }
        let tokens = self.tokens
        return tracks.filter { matches($0, tokens: tokens) }
    }

    func matches(_ a: Album, tokens: [String]) -> Bool {
        if !qualities.isEmpty && !qualities.contains(a.quality) { return false }
        if !codecs.isEmpty && codecs.isDisjoint(with: a.codecs) { return false }
        if let genre, a.genre != genre { return false }
        if let decade, a.decade != decade { return false }
        return tokens.allSatisfy { a.searchText.contains($0) }
    }

    func matches(_ t: Track, tokens: [String]) -> Bool {
        if !qualities.isEmpty && !qualities.contains(t.quality) { return false }
        if !codecs.isEmpty && !codecs.contains(t.codec) { return false }
        if let genre, t.genre != genre { return false }
        if let decade, t.year.map({ $0 / 10 * 10 }) != decade { return false }
        guard !tokens.isEmpty else { return true }
        let hay = [t.title, t.artist, t.album, t.albumArtistTag ?? "", t.genre ?? ""].joined(separator: " ").folded
        return tokens.allSatisfy { hay.contains($0) }
    }
}

// MARK: - Persistence

public enum LibraryDatabase {
    struct Payload: Codable {
        var version: Int
        var tracks: [Track]
    }

    /// Bump when tag reading changes so cached entries get re-read.
    /// v2: the original release date wins over a reissue's date; repeated artist values are merged.
    static let currentVersion = 2

    public static func load(from url: URL) -> [Track] {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        guard payload.version == currentVersion else {
            // Older cache: keep it for an instant first paint (and the "added" dates), but clear the
            // modification dates so the next scan re-reads every file.
            return payload.tracks.map { var t = $0; t.modified = .distantPast; return t }
        }
        return payload.tracks
    }

    public static func save(_ tracks: [Track], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Payload(version: currentVersion, tracks: tracks))
        try data.write(to: url, options: .atomic)
    }
}
