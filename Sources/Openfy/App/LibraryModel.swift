import SwiftUI
import AppKit
import Foundation
import Observation
import OpenfyCore

@Observable
final class LibraryModel {
    private(set) var tracks: [Track] = []
    private(set) var index = LibraryIndex()
    private(set) var tracksByPath: [String: Track] = [:]
    private(set) var folders: [URL] = []
    private(set) var isScanning = false
    private(set) var scanProgress: ScanProgress?
    private(set) var hasLoaded = false

    @ObservationIgnored let artwork: ArtworkStore
    @ObservationIgnored private let databaseURL: URL
    @ObservationIgnored private var rescanRequested = false
    @ObservationIgnored var onFirstLoad: (() -> Void)?
    @ObservationIgnored var onScanFinished: (() -> Void)?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.dataFolderName, isDirectory: true)
        artwork = ArtworkStore(directory: support.appendingPathComponent("Covers", isDirectory: true))
        databaseURL = support.appendingPathComponent("library.json")
        folders = (UserDefaults.standard.stringArray(forKey: "folders") ?? []).map { URL(fileURLWithPath: $0) }

        let dbURL = databaseURL
        Task { @MainActor in
            let (cached, index) = await Task.detached(priority: .userInitiated) {
                let cached = LibraryDatabase.load(from: dbURL)
                return (cached, LibraryIndex.build(cached))
            }.value
            self.apply(cached, index: index)
            self.hasLoaded = true
            self.onFirstLoad?()
            self.rescan()
        }
    }

    /// Builds with another bundle ID (e.g. a dev copy) keep their own library and covers.
    static var dataFolderName: String {
        guard let id = Bundle.main.bundleIdentifier, id != "io.github.openfy" else { return "Openfy" }
        return id
    }

    var totalDuration: Double { tracks.reduce(0) { $0 + $1.duration } }

    func album(for track: Track) -> Album? {
        index.albumsByID[LibraryIndex.albumKey(for: track)]
    }

    // MARK: Folders

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Library"
        panel.message = "Choose the folders that contain your music"
        panel.directoryURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK else { return }
        addFolders(panel.urls)
    }

    func addFolders(_ urls: [URL]) {
        var changed = false
        for url in urls {
            let std = url.standardizedFileURL
            // Skip folders already covered by (or inside) an existing folder.
            if folders.contains(where: { std.path.hasPrefix($0.path + "/") || std.path == $0.path }) { continue }
            folders.removeAll { $0.path.hasPrefix(std.path + "/") }
            folders.append(std)
            changed = true
        }
        guard changed else { return }
        saveFolders()
        rescan()
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
        saveFolders()
        rescan()
    }

    private func saveFolders() {
        UserDefaults.standard.set(folders.map(\.path), forKey: "folders")
    }

    // MARK: Scanning

    func rescan() {
        guard hasLoaded else { return }
        guard !isScanning else {
            rescanRequested = true
            return
        }
        isScanning = true
        scanProgress = nil
        let folders = self.folders
        let existing = tracksByPath
        let store = artwork
        let dbURL = databaseURL

        let sink = ProgressSink(self)
        Task { @MainActor in
            let (scanned, index) = await Task.detached(priority: .userInitiated) {
                let scanned = await LibraryScanner.scan(folders: folders, existing: existing, artwork: store) { p in
                    DispatchQueue.main.async { sink.model?.scanProgress = p }
                }
                let index = LibraryIndex.build(scanned)
                try? LibraryDatabase.save(scanned, to: dbURL)
                return (scanned, index)
            }.value
            self.apply(scanned, index: index)
            self.isScanning = false
            self.scanProgress = nil
            self.onScanFinished?()
            if self.rescanRequested {
                self.rescanRequested = false
                self.rescan()
            }
        }
    }

    private func apply(_ tracks: [Track], index: LibraryIndex) {
        self.tracks = tracks
        self.index = index
        tracksByPath = Dictionary(tracks.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

private final class ProgressSink: @unchecked Sendable {
    weak var model: LibraryModel?
    init(_ model: LibraryModel) { self.model = model }
}

enum Section: String, CaseIterable, Identifiable {
    case albums, artists, songs
    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: "Albums"
        case .artists: "Artists"
        case .songs: "Songs"
        }
    }

    var icon: String {
        switch self {
        case .albums: "square.grid.2x2"
        case .artists: "music.mic"
        case .songs: "music.note.list"
        }
    }
}

/// Navigation and filter state.
@Observable
final class BrowseState {
    var section: Section = .albums {
        didSet { if section != oldValue { openAlbumID = nil } }
    }
    var filter = LibraryFilter()
    var albumSort: AlbumSort = AlbumSort(rawValue: UserDefaults.standard.string(forKey: "albumSort") ?? "") ?? .artist {
        didSet { UserDefaults.standard.set(albumSort.rawValue, forKey: "albumSort") }
    }
    var openAlbumID: String?
    var selectedArtist: String?
    var searchFocusToken = 0

    func open(_ album: Album) { openAlbumID = album.id }

    func showArtist(_ name: String) {
        section = .artists
        selectedArtist = name
        openAlbumID = nil
    }

    // MARK: Now Playing / cover viewer

    /// Full-window Now Playing view (big cover, music keeps playing).
    private(set) var showNowPlaying = false
    /// Big-cover viewer for an album that isn't playing.
    private(set) var viewerArtworkKey: String?
    @ObservationIgnored private var enteredFullScreen = false

    func presentNowPlaying() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { showNowPlaying = true }
    }

    func dismissNowPlaying() {
        if enteredFullScreen, let window = Self.mainWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        enteredFullScreen = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.95)) { showNowPlaying = false }
    }

    func toggleNowPlaying() {
        showNowPlaying ? dismissNowPlaying() : presentNowPlaying()
    }

    /// Switches the window in or out of macOS full screen. If Now Playing turned it on,
    /// closing Now Playing turns it off again.
    func toggleWindowFullScreen() {
        guard let window = Self.mainWindow else { return }
        enteredFullScreen = !window.styleMask.contains(.fullScreen)
        window.toggleFullScreen(nil)
    }

    func showCover(_ key: String?) {
        guard let key else { return }
        withAnimation(.easeOut(duration: 0.25)) { viewerArtworkKey = key }
    }

    func closeCover() {
        withAnimation(.easeOut(duration: 0.2)) { viewerArtworkKey = nil }
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
    }
}
