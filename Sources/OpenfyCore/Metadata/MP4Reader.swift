import Foundation

/// Reads iTunes-style metadata (moov/udta/meta/ilst) from MP4 audio: .m4a (AAC and ALAC).
public enum MP4Reader {
    public static func read(url: URL, includeArtwork: Bool = true) -> TagData? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let fileEnd = try? fh.seekToEnd() else { return nil }

        // Walk top-level atoms to find "moov" (it may sit after "mdat").
        var offset: UInt64 = 0
        var moov: [UInt8]?
        while offset + 8 <= fileEnd {
            try? fh.seek(toOffset: offset)
            guard let h = fh.readBytes(8) else { break }
            var size = UInt64(be32(h, 0))
            var headerLen: UInt64 = 8
            if size == 1, let ext = fh.readBytes(8) {
                size = ext.reduce(0) { $0 << 8 | UInt64($1) }
                headerLen = 16
            } else if size == 0 {
                size = fileEnd - offset
            }
            guard size >= headerLen else { break }
            if h[4...7].elementsEqual("moov".utf8) {
                let payloadSize = size - headerLen
                guard payloadSize < 128 * 1024 * 1024 else { return nil }
                moov = fh.readBytes(Int(payloadSize))
                break
            }
            offset += size
        }
        guard let moov else { return nil }
        return parseMoov(moov, includeArtwork: includeArtwork)
    }

    static func parseMoov(_ b: [UInt8], includeArtwork: Bool) -> TagData? {
        guard let udta = children(b, 0..<b.count).first(where: { $0.type == "udta" }),
              let meta = children(b, udta.payload).first(where: { $0.type == "meta" }) else { return nil }
        // "meta" is normally a full box (4 bytes version/flags) — QuickTime-style files omit that.
        var metaStart = meta.payload.lowerBound
        if meta.payload.count >= 8, !b[metaStart + 4..<metaStart + 8].elementsEqual("hdlr".utf8) {
            metaStart += 4
        }
        guard let ilst = children(b, metaStart..<meta.payload.upperBound).first(where: { $0.type == "ilst" })
        else { return nil }

        var tags = TagData()
        var originalYear: Int?
        for item in children(b, ilst.payload) {
            guard let data = children(b, item.payload).first(where: { $0.type == "data" }),
                  data.payload.count >= 8 else { continue }
            let value = Array(b[data.payload.lowerBound + 8..<data.payload.upperBound])
            let str = { String(bytes: value, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }

            switch item.type {
            case "\u{A9}nam": tags.title = str()
            case "\u{A9}ART": tags.artist = str()
            case "aART": tags.albumArtist = str()
            case "\u{A9}alb": tags.album = str()
            case "\u{A9}day": tags.year = TagParsing.year(str())
            case "\u{A9}gen": tags.genre = str()
            case "gnre":
                if value.count >= 2, tags.genre == nil {
                    let idx = Int(value[0]) << 8 | Int(value[1])
                    tags.genre = TagParsing.genre(String(idx - 1))
                }
            case "trkn":
                if value.count >= 6 {
                    let n = Int(value[2]) << 8 | Int(value[3]), t = Int(value[4]) << 8 | Int(value[5])
                    tags.trackNumber = n > 0 ? n : nil
                    tags.trackTotal = t > 0 ? t : nil
                }
            case "disk":
                if value.count >= 6 {
                    let n = Int(value[2]) << 8 | Int(value[3]), t = Int(value[4]) << 8 | Int(value[5])
                    tags.discNumber = n > 0 ? n : nil
                    tags.discTotal = t > 0 ? t : nil
                }
            case "----": // freeform iTunes atom, e.g. com.apple.iTunes:ORIGINALDATE
                if let name = children(b, item.payload).first(where: { $0.type == "name" }),
                   name.payload.count > 4,
                   let key = String(bytes: b[name.payload.lowerBound + 4..<name.payload.upperBound], encoding: .utf8)?.uppercased(),
                   ["ORIGINALDATE", "ORIGINALYEAR", "ORIGINAL YEAR"].contains(key) {
                    originalYear = originalYear ?? TagParsing.year(str())
                }
            case "covr" where includeArtwork:
                if !value.isEmpty { tags.artwork = Data(value) }
            default: break
            }
        }
        tags.year = originalYear ?? tags.year
        return tags
    }

    struct Atom {
        let type: String
        let payload: Range<Int>
    }

    /// Child atoms in `range`. Atom types are decoded as ISO Latin-1 so "©" (0xA9) survives.
    static func children(_ b: [UInt8], _ range: Range<Int>) -> [Atom] {
        var out: [Atom] = []
        var i = range.lowerBound
        while i + 8 <= range.upperBound {
            var size = Int(be32(b, i))
            var header = 8
            if size == 1 {
                guard i + 16 <= range.upperBound else { break }
                size = Int(b[i + 8..<i + 16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
                header = 16
            } else if size == 0 {
                size = range.upperBound - i
            }
            guard size >= header, i + size <= range.upperBound else { break }
            let type = String(bytes: b[i + 4..<i + 8], encoding: .isoLatin1) ?? ""
            out.append(Atom(type: type, payload: i + header..<i + size))
            i += size
        }
        return out
    }

    static func be32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }
}
