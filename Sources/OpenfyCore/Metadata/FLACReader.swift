import Foundation

/// Native FLAC metadata reader: STREAMINFO, VORBIS_COMMENT and PICTURE blocks.
public enum FLACReader {
    public struct StreamInfo: Equatable, Sendable {
        public var sampleRate: Int
        public var channels: Int
        public var bitsPerSample: Int
        public var totalSamples: UInt64

        public var duration: Double { sampleRate > 0 ? Double(totalSamples) / Double(sampleRate) : 0 }
    }

    public struct Result: Sendable {
        public var streamInfo: StreamInfo?
        public var tags = TagData()
    }

    public static func read(url: URL, includeArtwork: Bool = true) -> Result? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        guard var magic = fh.readBytes(4) else { return nil }
        // Some taggers put an ID3v2 tag in front of the FLAC stream; skip it.
        if magic[0] == 0x49, magic[1] == 0x44, magic[2] == 0x33, let rest = fh.readBytes(6) {
            let header = magic + rest
            let size = Int(header[6]) << 21 | Int(header[7]) << 14 | Int(header[8]) << 7 | Int(header[9])
            let footer = (header[5] & 0x10) != 0 ? 10 : 0
            try? fh.seek(toOffset: UInt64(10 + size + footer))
            guard let m = fh.readBytes(4) else { return nil }
            magic = m
        }
        guard magic == [0x66, 0x4C, 0x61, 0x43] else { return nil } // "fLaC"

        var result = Result()
        var pictures: [(type: UInt32, data: Data)] = []

        var isLast = false
        var guardCount = 0
        while !isLast, guardCount < 512 {
            guardCount += 1
            guard let header = fh.readBytes(4) else { break }
            isLast = (header[0] & 0x80) != 0
            let type = header[0] & 0x7F
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])

            switch type {
            case 0: // STREAMINFO
                guard let b = fh.readBytes(length), b.count >= 18 else { return nil }
                let sampleRate = Int(b[10]) << 12 | Int(b[11]) << 4 | Int(b[12]) >> 4
                let channels = Int((b[12] >> 1) & 0x07) + 1
                let bps = (Int(b[12] & 0x01) << 4 | Int(b[13]) >> 4) + 1
                let total = UInt64(b[13] & 0x0F) << 32 | UInt64(b[14]) << 24 | UInt64(b[15]) << 16
                    | UInt64(b[16]) << 8 | UInt64(b[17])
                result.streamInfo = StreamInfo(sampleRate: sampleRate, channels: channels,
                                               bitsPerSample: bps, totalSamples: total)
            case 4: // VORBIS_COMMENT
                guard let b = fh.readBytes(length) else { break }
                parseVorbisComments(b, into: &result.tags)
            case 6 where includeArtwork: // PICTURE
                guard let b = fh.readBytes(length) else { break }
                if let pic = parsePicture(b) { pictures.append(pic) }
            default:
                guard let pos = try? fh.offset() else { return result }
                try? fh.seek(toOffset: pos + UInt64(length))
            }
        }

        // Prefer the front cover (type 3), otherwise whatever picture is there.
        result.tags.artwork = (pictures.first { $0.type == 3 } ?? pictures.first)?.data
        return result
    }

    /// Vorbis comments are little-endian: vendor string, then `count` entries of "KEY=value".
    static func parseVorbisComments(_ bytes: [UInt8], into tags: inout TagData) {
        var r = ByteReader(bytes)
        guard let vendorLen = r.u32le(), r.skip(Int(vendorLen)), let count = r.u32le() else { return }
        var fields: [String: [String]] = [:]
        for _ in 0..<min(count, 10_000) {
            guard let len = r.u32le(), let raw = r.bytes(Int(len)),
                  let s = String(bytes: raw, encoding: .utf8),
                  let eq = s.firstIndex(of: "=") else { break }
            let key = s[..<eq].uppercased()
            let value = String(s[s.index(after: eq)...])
            fields[key, default: []].append(value)
        }
        applyVorbisFields(fields, to: &tags)
    }

    static func applyVorbisFields(_ fields: [String: [String]], to tags: inout TagData) {
        func first(_ keys: String...) -> String? {
            for k in keys { if let v = fields[k]?.first(where: { !$0.isEmpty }) { return v } }
            return nil
        }
        func joined(_ key: String) -> String? {
            // Some stores repeat a value with different case ("Radiohead" + "RADIOHEAD"): keep the first spelling.
            var seen = Set<String>()
            let values = (fields[key] ?? [])
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            return values.isEmpty ? nil : values.joined(separator: ", ")
        }
        tags.title = first("TITLE")
        tags.artist = joined("ARTIST")
        tags.albumArtist = first("ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST", "BAND")
        tags.album = first("ALBUM")
        let (track, trackTotalInline) = TagParsing.numberPair(first("TRACKNUMBER"))
        tags.trackNumber = track
        tags.trackTotal = Int(first("TRACKTOTAL", "TOTALTRACKS") ?? "") ?? trackTotalInline
        let (disc, discTotalInline) = TagParsing.numberPair(first("DISCNUMBER"))
        tags.discNumber = disc
        tags.discTotal = Int(first("DISCTOTAL", "TOTALDISCS") ?? "") ?? discTotalInline
        // Prefer the original release date: remasters/reissues put the reissue date in DATE.
        tags.year = TagParsing.year(first("ORIGINALDATE", "ORIGINALYEAR", "ORIGINAL_YEAR"))
            ?? TagParsing.year(first("DATE", "YEAR"))
        tags.genre = TagParsing.genre(first("GENRE"))
    }

    /// PICTURE block, big-endian.
    static func parsePicture(_ bytes: [UInt8]) -> (type: UInt32, data: Data)? {
        var r = ByteReader(bytes)
        guard let type = r.u32be(),
              let mimeLen = r.u32be(), r.skip(Int(mimeLen)),
              let descLen = r.u32be(), r.skip(Int(descLen)),
              r.skip(16), // width, height, depth, colors
              let dataLen = r.u32be(), let data = r.bytes(Int(dataLen)), !data.isEmpty
        else { return nil }
        return (type, Data(data))
    }
}
