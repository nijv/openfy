import Foundation

public struct ScanProgress: Sendable, Equatable {
    public var processed: Int
    public var total: Int
}

public enum LibraryScanner {
    struct Candidate: Sendable {
        let url: URL
        let size: Int64
        let modified: Date
    }

    /// Scans folders recursively. Files whose size and modification date are unchanged reuse
    /// their existing entry, so re-scans of a large library take seconds.
    public static func scan(
        folders: [URL],
        existing: [String: Track],
        artwork: ArtworkStore,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async -> [Track] {
        let candidates = enumerate(folders: folders)
        var result: [Track] = []
        var pending: [Candidate] = []
        for c in candidates {
            if let old = existing[c.url.path], old.fileSize == c.size,
               abs(old.modified.timeIntervalSince(c.modified)) < 1 {
                result.append(old)
            } else {
                pending.append(c)
            }
        }

        let total = pending.count
        progress(ScanProgress(processed: 0, total: total))
        guard total > 0 else { return result }

        let folderArt = FolderArtCache(store: artwork)
        let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
        var processed = 0

        await withTaskGroup(of: Track?.self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<limit {
                guard let c = iterator.next() else { break }
                group.addTask { process(c, existing: existing[c.url.path], artwork: artwork, folderArt: folderArt) }
            }
            for await track in group {
                if let track { result.append(track) }
                processed += 1
                if processed % 10 == 0 || processed == total {
                    progress(ScanProgress(processed: processed, total: total))
                }
                if let c = iterator.next() {
                    group.addTask { process(c, existing: existing[c.url.path], artwork: artwork, folderArt: folderArt) }
                }
            }
        }
        return result
    }

    static func process(_ c: Candidate, existing: Track?, artwork: ArtworkStore, folderArt: FolderArtCache) -> Track? {
        guard let read = MetadataReader.read(url: c.url, fileSize: c.size, modified: c.modified) else {
            return nil
        }
        var track = read.track
        let embedded = read.artwork
        if let existing { track.added = existing.added }
        if let embedded, let key = artwork.store(embedded) {
            track.artworkKey = key
        } else {
            track.artworkKey = folderArt.key(for: c.url.deletingLastPathComponent())
        }
        return track
    }

    static func enumerate(folders: [URL]) -> [Candidate] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var seen = Set<String>()
        var out: [Candidate] = []
        for folder in folders {
            guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: keys,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                guard MetadataReader.supportedExtensions.contains(url.pathExtension.lowercased()),
                      let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      seen.insert(url.path).inserted else { continue }
                out.append(Candidate(url: url, size: Int64(v.fileSize ?? 0),
                                     modified: v.contentModificationDate ?? .distantPast))
            }
        }
        return out
    }
}

/// Looks up folder artwork once per directory.
final class FolderArtCache: @unchecked Sendable {
    private let store: ArtworkStore
    private let lock = NSLock()
    private var cache: [String: String?] = [:]

    init(store: ArtworkStore) { self.store = store }

    func key(for directory: URL) -> String? {
        lock.lock()
        if let cached = cache[directory.path] { lock.unlock(); return cached }
        lock.unlock()

        var key: String?
        var dir = directory
        // For "Album/CD1/track.flac", also look in "Album/".
        for _ in 0..<2 {
            if let img = ArtworkStore.folderImage(in: dir), let data = try? Data(contentsOf: img) {
                key = store.store(data)
                if key != nil { break }
            }
            guard dir.lastPathComponent.firstMatch(of: #/^(?i)(?:cd|disc|disk)\s*\d+$/#) != nil else { break }
            dir = dir.deletingLastPathComponent()
        }

        lock.lock()
        cache[directory.path] = key
        lock.unlock()
        return key
    }
}
