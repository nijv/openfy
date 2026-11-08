import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import OpenfyCore

/// Builds real audio files on disk for tests, using macOS's `afconvert` for encoding.
enum Fixtures {
    static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("openfy-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// PCM WAV with a quiet sine wave. 16-bit or 24-bit.
    static func wav(at url: URL, sampleRate: Int = 44_100, bits: Int = 16, channels: Int = 2,
                    seconds: Double = 0.5, extraChunks: [(String, [UInt8])] = []) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let frames = Int(Double(sampleRate) * seconds)
        let bytesPerSample = bits / 8
        var pcm: [UInt8] = []
        pcm.reserveCapacity(frames * channels * bytesPerSample)
        let maxAmp = Double((1 << (bits - 1)) - 1) * 0.1
        for i in 0..<frames {
            let v = Int(sin(Double(i) * 2 * .pi * 440 / Double(sampleRate)) * maxAmp)
            for _ in 0..<channels {
                for b in 0..<bytesPerSample { pcm.append(UInt8(truncatingIfNeeded: v >> (8 * b))) }
            }
        }
        var fmt: [UInt8] = []
        fmt += le16(1) + le16(channels) + le32(sampleRate) + le32(sampleRate * channels * bytesPerSample)
        fmt += le16(channels * bytesPerSample) + le16(bits)

        var body: [UInt8] = Array("WAVE".utf8)
        body += Array("fmt ".utf8) + le32(fmt.count) + fmt
        body += Array("data".utf8) + le32(pcm.count) + pcm
        if pcm.count % 2 == 1 { body.append(0) }
        for (id, payload) in extraChunks {
            body += Array(id.utf8) + le32(payload.count) + payload
            if payload.count % 2 == 1 { body.append(0) }
        }
        let file = Array("RIFF".utf8) + le32(body.count) + body
        try! Data(file).write(to: url)
    }

    /// Encodes with afconvert. `format` e.g. "flac", "m4af"; `codec` e.g. "flac", "alac", "aac".
    static func convert(_ src: URL, to dst: URL, fileFormat: String, dataFormat: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        p.arguments = ["-f", fileFormat, "-d", dataFormat, src.path, dst.path]
        try! p.run()
        p.waitUntilExit()
        precondition(p.terminationStatus == 0, "afconvert failed for \(dst.lastPathComponent)")
    }

    static func png(width: Int = 64, height: Int = 64, red: CGFloat = 0.8) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: red, green: 0.2, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    // MARK: FLAC tagging

    /// Rewrites a FLAC file's metadata: STREAMINFO + VORBIS_COMMENT (+ PICTURE), dropping other blocks.
    static func tagFLAC(_ url: URL, comments: [String], picture: Data? = nil) {
        let bytes = [UInt8](try! Data(contentsOf: url))
        precondition(Array(bytes[0..<4]) == Array("fLaC".utf8))
        var pos = 4
        var streamInfo: [UInt8] = []
        var last = false
        while !last {
            last = bytes[pos] & 0x80 != 0
            let type = bytes[pos] & 0x7F
            let len = Int(bytes[pos + 1]) << 16 | Int(bytes[pos + 2]) << 8 | Int(bytes[pos + 3])
            if type == 0 { streamInfo = Array(bytes[pos + 4..<pos + 4 + len]) }
            pos += 4 + len
        }
        let audio = bytes[pos...]

        var vc: [UInt8] = le32(6) + Array("openfy".utf8) + le32(comments.count)
        for c in comments { vc += le32(c.utf8.count) + Array(c.utf8) }

        var blocks: [(UInt8, [UInt8])] = [(0, streamInfo), (4, vc)]
        if let picture {
            let mime = Array("image/png".utf8)
            var pic: [UInt8] = be32(3) + be32(mime.count) + mime + be32(0)
            pic += be32(64) + be32(64) + be32(24) + be32(0) + be32(picture.count) + [UInt8](picture)
            blocks.append((6, pic))
        }

        var out: [UInt8] = Array("fLaC".utf8)
        for (i, (type, data)) in blocks.enumerated() {
            let isLast = i == blocks.count - 1
            out.append((isLast ? 0x80 : 0) | type)
            out += [UInt8(data.count >> 16 & 0xFF), UInt8(data.count >> 8 & 0xFF), UInt8(data.count & 0xFF)]
            out += data
        }
        out += audio
        try! Data(out).write(to: url)
    }

    // MARK: ID3

    static func id3Frame(_ id: String, _ payload: [UInt8], v4: Bool) -> [UInt8] {
        let size = v4 ? syncsafe(payload.count) : be32(payload.count)
        return Array(id.utf8) + size + [0, 0] + payload
    }

    static func id3Text(_ id: String, _ s: String, v4: Bool) -> [UInt8] {
        if v4 { return id3Frame(id, [3] + Array(s.utf8), v4: true) }
        // v2.3: UTF-16 with BOM
        var p: [UInt8] = [1, 0xFF, 0xFE]
        for u in s.utf16 { p += [UInt8(u & 0xFF), UInt8(u >> 8)] }
        return id3Frame(id, p, v4: false)
    }

    static func id3Tag(major: UInt8, frames: [[UInt8]]) -> [UInt8] {
        let body = frames.flatMap { $0 } + [UInt8](repeating: 0, count: 32) // padding
        return Array("ID3".utf8) + [major, 0, 0] + syncsafe(body.count) + body
    }

    // MARK: MP4

    /// A minimal MP4 container: ftyp + mdat + moov/udta/meta/ilst (moov after mdat, like many encoders).
    /// `freeform` adds iTunes "----" atoms (mean/name/data), e.g. ("ORIGINALDATE", "1997").
    static func syntheticM4A(items: [(String, [UInt8], UInt32)], freeform: [(String, String)] = []) -> [UInt8] {
        func atom(_ type: String, _ payload: [UInt8]) -> [UInt8] {
            be32(payload.count + 8) + Array(type.data(using: .isoLatin1)!) + payload
        }
        let ilstPayload = items.flatMap { name, value, kind in
            atom(name, atom("data", be32(Int(kind)) + be32(0) + value))
        } + freeform.flatMap { name, value in
            atom("----", atom("mean", be32(0) + Array("com.apple.iTunes".utf8))
                + atom("name", be32(0) + Array(name.utf8))
                + atom("data", be32(1) + be32(0) + Array(value.utf8)))
        }
        let hdlr = atom("hdlr", [0, 0, 0, 0] + [0, 0, 0, 0] + Array("mdirappl".utf8) + [UInt8](repeating: 0, count: 9))
        let meta = atom("meta", [0, 0, 0, 0] + hdlr + atom("ilst", ilstPayload))
        let moov = atom("moov", atom("mvhd", [UInt8](repeating: 0, count: 100)) + atom("udta", meta))
        return atom("ftyp", Array("M4A ".utf8) + be32(0)) + atom("mdat", [UInt8](repeating: 7, count: 4096)) + moov
    }

    // MARK: Byte helpers

    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    static func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8(v >> (8 * $0) & 0xFF) } }
    static func be32(_ v: Int) -> [UInt8] { (0..<4).reversed().map { UInt8(v >> (8 * $0) & 0xFF) } }
    static func syncsafe(_ v: Int) -> [UInt8] { [UInt8(v >> 21 & 0x7F), UInt8(v >> 14 & 0x7F), UInt8(v >> 7 & 0x7F), UInt8(v & 0x7F)] }
}
