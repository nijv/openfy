import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Content-addressed cover cache. Identical covers (every track of an album) are stored once.
public final class ArtworkStore: @unchecked Sendable {
    public enum Size: String, Sendable {
        case thumb = "t"
        case large = "l"

        var maxPixels: Int {
            switch self {
            case .thumb: 440   // grid tiles (~200pt on Retina)
            case .large: 1600  // album page and full-window Now Playing
            }
        }
    }

    public let directory: URL
    private let lock = NSLock()
    private var known: Set<String> = []

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func url(for key: String, size: Size) -> URL {
        directory.appendingPathComponent("\(key)-\(size.rawValue).jpg")
    }

    /// Stores image data (JPEG/PNG/...) and returns its key, or nil if it isn't a decodable image.
    public func store(_ data: Data) -> String? {
        let digest = SHA256.hash(data: data)
        let key = digest.prefix(12).map { String(format: "%02x", $0) }.joined()

        lock.lock()
        if known.contains(key) { lock.unlock(); return key }
        known.insert(key)
        lock.unlock()

        let fm = FileManager.default
        if fm.fileExists(atPath: url(for: key, size: .thumb).path),
           fm.fileExists(atPath: url(for: key, size: .large).path) {
            return key
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            lock.lock(); known.remove(key); lock.unlock()
            return nil
        }
        for size in [Size.thumb, .large] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size.maxPixels,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                lock.lock(); known.remove(key); lock.unlock()
                return nil
            }
            // Write to a temp file and move, so readers never see a half-written image.
            let tmp = directory.appendingPathComponent(".\(UUID().uuidString).jpg")
            guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { try? fm.removeItem(at: tmp); return nil }
            let final = url(for: key, size: size)
            try? fm.removeItem(at: final)
            try? fm.moveItem(at: tmp, to: final)
        }
        return key
    }

    /// Finds cover art next to the audio files: cover.jpg, folder.jpg, front.png, ...
    public static func folderImage(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey],
                                                      options: [.skipsHiddenFiles]) else { return nil }
        let images = items.filter { ["jpg", "jpeg", "png", "heic", "webp", "bmp", "tif", "tiff"].contains($0.pathExtension.lowercased()) }

        func base(_ u: URL) -> String { u.deletingPathExtension().lastPathComponent.lowercased() }
        for preferred in ["cover", "folder", "front", "album", "albumart", "albumartlarge", "art", "artwork"] {
            if let hit = images.first(where: { base($0) == preferred }) { return hit }
        }
        if let hit = images.first(where: { base($0).contains("cover") || base($0).contains("front") }) { return hit }
        // Otherwise the largest image that isn't obviously the back/disc/booklet.
        let excluded = ["back", "cd", "disc", "inlay", "inside", "booklet", "tray"]
        let candidates = images.filter { img in !excluded.contains { base(img).contains($0) } }
        return candidates.max { a, b in
            ((try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                < ((try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
