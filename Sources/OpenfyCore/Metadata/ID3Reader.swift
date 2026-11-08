import Foundation

/// ID3v2.2 / 2.3 / 2.4 and ID3v1 reader (MP3, and ID3 chunks embedded in WAV/AIFF).
public enum ID3Reader {
    public static func read(url: URL, includeArtwork: Bool = true) -> TagData? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        var tags: TagData?
        if let header = fh.readBytes(10), header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 {
            let size = syncsafe(header[6], header[7], header[8], header[9])
            if let body = fh.readBytes(min(size, 64 * 1024 * 1024)) {
                tags = parse(header + body, includeArtwork: includeArtwork)
            }
        }

        // ID3v1 lives in the last 128 bytes; use it to fill gaps (common on old CD rips).
        if let end = try? fh.seekToEnd(), end >= 128 {
            try? fh.seek(toOffset: end - 128)
            if let v1Bytes = fh.readBytes(128), let v1 = parseV1(v1Bytes) {
                var merged = tags ?? TagData()
                merged.merge(fallback: v1)
                tags = merged
            }
        }
        return tags
    }

    // MARK: ID3v2

    /// Parses a complete ID3v2 tag (10-byte header + body).
    public static func parse(_ bytes: [UInt8], includeArtwork: Bool = true) -> TagData? {
        guard bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else { return nil }
        let major = bytes[3]
        guard (2...4).contains(major) else { return nil }
        let flags = bytes[5]
        let size = syncsafe(bytes[6], bytes[7], bytes[8], bytes[9])
        var body = Array(bytes[10..<min(10 + size, bytes.count)])
        if flags & 0x80 != 0 && major < 4 { body = deunsynchronise(body) }

        var pos = 0
        if flags & 0x40 != 0 && major >= 3 && body.count >= 4 {
            if major == 3 {
                pos = 4 + Int(be32(body[0], body[1], body[2], body[3]))
            } else {
                pos = syncsafe(body[0], body[1], body[2], body[3])
            }
        }

        var tags = TagData()
        var pictures: [(type: UInt8, data: Data)] = []
        var originalYear: Int?
        let headerLen = major == 2 ? 6 : 10

        while pos + headerLen <= body.count {
            if body[pos] == 0 { break } // padding
            let id: String
            let frameSize: Int
            var formatFlags: UInt8 = 0
            if major == 2 {
                id = String(bytes: body[pos..<pos + 3], encoding: .ascii) ?? ""
                frameSize = Int(body[pos + 3]) << 16 | Int(body[pos + 4]) << 8 | Int(body[pos + 5])
            } else {
                id = String(bytes: body[pos..<pos + 4], encoding: .ascii) ?? ""
                let b = (body[pos + 4], body[pos + 5], body[pos + 6], body[pos + 7])
                if major == 4 && (b.0 | b.1 | b.2 | b.3) & 0x80 == 0 {
                    frameSize = syncsafe(b.0, b.1, b.2, b.3)
                } else {
                    // v2.3, or a v2.4 tag written with plain sizes (an old iTunes bug).
                    frameSize = Int(be32(b.0, b.1, b.2, b.3))
                }
                formatFlags = body[pos + 9]
            }
            pos += headerLen
            guard frameSize > 0, pos + frameSize <= body.count,
                  id.allSatisfy({ $0.isUppercase || $0.isNumber }) else { break }
            var frame = Array(body[pos..<pos + frameSize])
            pos += frameSize

            if major == 4 {
                if formatFlags & 0x0C != 0 { continue } // compressed / encrypted
                if formatFlags & 0x02 != 0 { frame = deunsynchronise(frame) }
                if formatFlags & 0x01 != 0 { frame = Array(frame.dropFirst(4)) } // data length indicator
            } else if major == 3, formatFlags & 0xC0 != 0 {
                continue // compressed / encrypted
            }

            switch id {
            case "TIT2", "TT2": tags.title = text(frame)
            case "TPE1", "TP1": tags.artist = text(frame)
            case "TPE2", "TP2": tags.albumArtist = text(frame)
            case "TALB", "TAL": tags.album = text(frame)
            case "TRCK", "TRK": (tags.trackNumber, tags.trackTotal) = TagParsing.numberPair(text(frame))
            case "TPOS", "TPA": (tags.discNumber, tags.discTotal) = TagParsing.numberPair(text(frame))
            case "TYER", "TYE", "TDRC": tags.year = tags.year ?? TagParsing.year(text(frame))
            case "TDOR", "TORY", "TOR": originalYear = originalYear ?? TagParsing.year(text(frame))
            case "TCON", "TCO": tags.genre = TagParsing.genre(text(frame)?.components(separatedBy: ", ").first)
            case "APIC" where includeArtwork: if let p = apic(frame) { pictures.append(p) }
            case "PIC" where includeArtwork: if let p = pic(frame) { pictures.append(p) }
            default: break
            }
        }

        tags.year = originalYear ?? tags.year
        tags.artwork = (pictures.first { $0.type == 3 } ?? pictures.first)?.data
        return tags
    }

    // MARK: ID3v1

    static func parseV1(_ b: [UInt8]) -> TagData? {
        guard b.count == 128, b[0] == 0x54, b[1] == 0x41, b[2] == 0x47 else { return nil } // "TAG"
        func field(_ range: Range<Int>) -> String? {
            let raw = b[range].prefix { $0 != 0 }
            return String(bytes: raw, encoding: .isoLatin1)?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        }
        var t = TagData()
        t.title = field(3..<33)
        t.artist = field(33..<63)
        t.album = field(63..<93)
        t.year = TagParsing.year(field(93..<97))
        if b[125] == 0 && b[126] != 0 { t.trackNumber = Int(b[126]) }
        if b[127] != 255 { t.genre = TagParsing.genre(String(b[127])) }
        return t.isEmpty && t.year == nil ? nil : t
    }

    // MARK: Frame decoding

    static func text(_ frame: [UInt8]) -> String? {
        guard let enc = frame.first else { return nil }
        guard let s = decode(Array(frame.dropFirst()), encoding: enc) else { return nil }
        // v2.4 separates multiple values with NUL.
        let values = s.split(separator: "\0").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    static func decode(_ bytes: [UInt8], encoding: UInt8) -> String? {
        switch encoding {
        case 0: return String(bytes: bytes, encoding: .isoLatin1)
        case 1:
            if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF {
                return String(bytes: bytes.dropFirst(2), encoding: .utf16BigEndian)
            }
            if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE {
                return String(bytes: bytes.dropFirst(2), encoding: .utf16LittleEndian)
            }
            return String(bytes: bytes, encoding: .utf16LittleEndian)
        case 2: return String(bytes: bytes, encoding: .utf16BigEndian)
        case 3: return String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1)
        default: return nil
        }
    }

    /// Index just past the NUL terminator of a string starting at `start`.
    static func skipTerminated(_ b: [UInt8], from start: Int, encoding: UInt8) -> Int? {
        if encoding == 1 || encoding == 2 {
            var i = start
            while i + 1 < b.count {
                if b[i] == 0 && b[i + 1] == 0 { return i + 2 }
                i += 2
            }
            return nil
        }
        guard let nul = b[start...].firstIndex(of: 0) else { return nil }
        return nul + 1
    }

    static func apic(_ f: [UInt8]) -> (type: UInt8, data: Data)? {
        guard f.count > 4 else { return nil }
        let enc = f[0]
        guard let afterMime = skipTerminated(f, from: 1, encoding: 0), afterMime < f.count else { return nil }
        let type = f[afterMime]
        guard let afterDesc = skipTerminated(f, from: afterMime + 1, encoding: enc), afterDesc < f.count
        else { return nil }
        return (type, Data(f[afterDesc...]))
    }

    static func pic(_ f: [UInt8]) -> (type: UInt8, data: Data)? {
        guard f.count > 6 else { return nil }
        let enc = f[0]
        let type = f[4]
        guard let afterDesc = skipTerminated(f, from: 5, encoding: enc), afterDesc < f.count else { return nil }
        return (type, Data(f[afterDesc...]))
    }

    // MARK: Helpers

    static func syncsafe(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        Int(a & 0x7F) << 21 | Int(b & 0x7F) << 14 | Int(c & 0x7F) << 7 | Int(d & 0x7F)
    }

    static func be32(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
        UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)
    }

    /// Removes the 0x00 inserted after every 0xFF by unsynchronisation.
    static func deunsynchronise(_ b: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(b.count)
        var i = 0
        while i < b.count {
            out.append(b[i])
            if b[i] == 0xFF && i + 1 < b.count && b[i + 1] == 0x00 { i += 1 }
            i += 1
        }
        return out
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
