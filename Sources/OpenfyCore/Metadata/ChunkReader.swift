import Foundation

/// Tags inside WAV (RIFF) and AIFF files: an embedded "id3 " chunk, or WAV LIST/INFO.
public enum ChunkReader {
    public static func read(url: URL, includeArtwork: Bool = true) -> TagData? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let header = fh.readBytes(12) else { return nil }
        let form = String(bytes: header[0..<4], encoding: .ascii)
        let kind = String(bytes: header[8..<12], encoding: .ascii)

        let littleEndian: Bool
        switch (form, kind) {
        case ("RIFF", "WAVE"), ("RF64", "WAVE"): littleEndian = true
        case ("FORM", "AIFF"), ("FORM", "AIFC"): littleEndian = false
        default: return nil
        }

        guard let end = try? fh.seekToEnd() else { return nil }
        var offset: UInt64 = 12
        var id3Tags: TagData?
        var infoTags: TagData?

        while offset + 8 <= end {
            try? fh.seek(toOffset: offset)
            guard let h = fh.readBytes(8) else { break }
            let id = String(bytes: h[0..<4], encoding: .ascii) ?? ""
            let sizeBytes = Array(h[4..<8])
            let size = UInt64(littleEndian
                ? sizeBytes.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                : sizeBytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })

            switch id.lowercased() {
            case "id3 ":
                if size < 64 * 1024 * 1024, let body = fh.readBytes(Int(size)) {
                    id3Tags = ID3Reader.parse(body, includeArtwork: includeArtwork)
                }
            case "list" where littleEndian:
                if size < 1024 * 1024, let body = fh.readBytes(Int(size)) {
                    infoTags = parseInfo(body)
                }
            default: break
            }
            // Chunks are padded to an even size.
            offset += 8 + size + (size % 2)
        }

        guard var result = id3Tags ?? infoTags else { return nil }
        if let infoTags { result.merge(fallback: infoTags) }
        return result
    }

    /// LIST chunk of type INFO: sub-chunks like INAM (title), IART (artist), IPRD (album).
    static func parseInfo(_ b: [UInt8]) -> TagData? {
        guard b.count >= 4, String(bytes: b[0..<4], encoding: .ascii) == "INFO" else { return nil }
        var tags = TagData()
        var i = 4
        while i + 8 <= b.count {
            let id = String(bytes: b[i..<i + 4], encoding: .ascii) ?? ""
            let size = Int(b[i + 4]) | Int(b[i + 5]) << 8 | Int(b[i + 6]) << 16 | Int(b[i + 7]) << 24
            let start = i + 8
            guard size >= 0, start + size <= b.count else { break }
            let raw = b[start..<start + size].prefix { $0 != 0 }
            let value = (String(bytes: raw, encoding: .utf8) ?? String(bytes: raw, encoding: .isoLatin1))?
                .trimmingCharacters(in: .whitespaces)
            switch id {
            case "INAM": tags.title = value
            case "IART": tags.artist = value
            case "IPRD": tags.album = value
            case "ICRD": tags.year = TagParsing.year(value)
            case "IGNR": tags.genre = value
            case "ITRK", "IPRT": (tags.trackNumber, tags.trackTotal) = TagParsing.numberPair(value)
            default: break
            }
            i = start + size + (size % 2)
        }
        return tags.isEmpty ? nil : tags
    }
}
