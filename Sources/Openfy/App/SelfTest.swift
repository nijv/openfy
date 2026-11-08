import AppKit
import Foundation

/// `Openfy --selftest a.flac b.flac c.flac` — silently exercises the playback engine
/// (rate switching, gapless hand-off, format change, seeking) and exits. Used during development.
enum SelfTest {
    static var engine: PlaybackEngine?

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest") else { return false }
        let files = args[(i + 1)...].map { URL(fileURLWithPath: $0) }
        run(files)
        return true
    }

    static func run(_ files: [URL]) {
        let start = Date()
        func log(_ s: String) { print(String(format: "[%5.2fs] ", Date().timeIntervalSince(start)) + s); fflush(stdout) }

        if let dev = AudioDevice.defaultOutput() {
            let rates = AudioDevice.availableSampleRates(dev).map { "\(Int($0.mMinimum))" }.joined(separator: ",")
            log("device=\(AudioDevice.name(dev)) rate=\(AudioDevice.nominalSampleRate(dev) ?? 0) supported=[\(rates)]")
        }

        let e = PlaybackEngine()
        engine = e
        e.volume = 0
        var queueIndex = 0
        e.onStatusChange = { s in
            log("status device=\(s.deviceRate) source=\(s.sourceRate) matched=\(s.rateMatched) bitPerfect=\(s.isBitPerfect)")
        }
        e.onAdvance = {
            queueIndex += 1
            log("GAPLESS advance → \(files[queueIndex].lastPathComponent) pos=\(String(format: "%.3f", e.currentTime))")
            e.preloadNext(url: queueIndex + 1 < files.count ? files[queueIndex + 1] : nil)
        }
        e.onFinished = {
            queueIndex += 1
            guard queueIndex < files.count else {
                log("finished all")
                e.stop()
                e.restoreDeviceRates()
                if let dev = AudioDevice.defaultOutput() { log("restored rate=\(AudioDevice.nominalSampleRate(dev) ?? 0)") }
                exit(0)
            }
            log("ended; loading \(files[queueIndex].lastPathComponent) (format change)")
            try? e.load(url: files[queueIndex], autoplay: true)
            e.preloadNext(url: queueIndex + 1 < files.count ? files[queueIndex + 1] : nil)
        }

        do {
            try e.load(url: files[0], autoplay: true)
            log("loaded \(files[0].lastPathComponent) duration=\(e.duration)")
            e.preloadNext(url: files.count > 1 ? files[1] : nil)
        } catch {
            log("load failed: \(error)")
            exit(1)
        }

        // Exercise seek + pause/resume on the first track.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            log("pos before seek=\(String(format: "%.3f", e.currentTime)); seeking to 1.2")
            e.seek(to: 1.2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            log("pos after seek=\(String(format: "%.3f", e.currentTime)); pausing")
            e.pause()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            log("paused pos=\(String(format: "%.3f", e.currentTime)); resuming")
            e.play()
        }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            log("tick \(e.currentURL?.lastPathComponent ?? "-") pos=\(String(format: "%.3f", e.currentTime))")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            log("TIMEOUT")
            e.restoreDeviceRates()
            exit(2)
        }
    }
}

/// Developer launch options for UI checks, e.g.
/// `open Openfy.app --args -devSection songs -devOpenAlbum "Album" -devCueTrack 2`
/// Cueing loads the track paused, so nothing is heard.
enum DevLaunch {
    private static var applied = false

    static func applyOnce(library: LibraryModel, player: PlayerController, browse: BrowseState) {
        guard !applied else { return }
        applied = true
        apply(library: library, player: player, browse: browse)
    }

    static func apply(library: LibraryModel, player: PlayerController, browse: BrowseState) {
        let d = UserDefaults.standard
        if let s = d.string(forKey: "devWindowSize"), let window = BrowseState.mainWindow { // e.g. 520x380
            let parts = s.split(separator: "x").compactMap { Double($0) }
            let size = NSSize(width: parts.first ?? 1240, height: parts.last ?? 800)
            window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - size.height,
                                   width: size.width, height: size.height), display: true)
            if d.bool(forKey: "devFakeResizeEnd") { // as if the user just let go of a drag-resize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
                }
            }
        }
        if d.bool(forKey: "devMini") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { AppState.window.toggleMini() }
            if d.double(forKey: "devMiniBackAfter") > 0 { // round trip: back to the full window
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + d.double(forKey: "devMiniBackAfter")) {
                    AppState.window.toggleMini()
                }
            }
        }
        if let s = d.string(forKey: "devSection"), let section = Section(rawValue: s) { browse.section = section }
        if let artist = d.string(forKey: "devArtist") { browse.showArtist(artist) }
        if let q = d.string(forKey: "devSearch") { browse.filter.search = q }
        if let title = d.string(forKey: "devOpenAlbum"),
           let album = library.index.albums.first(where: { $0.title == title }) {
            browse.open(album)
            if d.object(forKey: "devStageTrack") != nil {
                player.stage(album.tracks, index: d.integer(forKey: "devStageTrack"))
            } else if d.object(forKey: "devPlayTrack") != nil {
                // Real playback from N seconds before the end (dev copy runs at volume 0).
                let i = d.integer(forKey: "devPlayTrack")
                player.play(album.tracks, startAt: i)
                let from = max(0, album.tracks[i].duration - d.double(forKey: "devPlayTail"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { player.seek(to: from) }
            } else if d.object(forKey: "devCueTrack") != nil {
                player.play(album.tracks, startAt: d.integer(forKey: "devCueTrack"), autoplay: false)
            }
            if d.bool(forKey: "devNowPlaying") { browse.presentNowPlaying() }
            if d.bool(forKey: "devFullScreen") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { browse.toggleWindowFullScreen() }
            }
            // Simulate the track changing N seconds later (no audio is loaded).
            if d.object(forKey: "devStageTrack") != nil, d.double(forKey: "devAdvanceAfter") > 0 {
                let next = d.integer(forKey: "devStageTrack") + 1
                DispatchQueue.main.asyncAfter(deadline: .now() + d.double(forKey: "devAdvanceAfter")) {
                    player.stage(album.tracks, index: next)
                }
            }
            // Keep the staged track but show the album grid.
            if d.bool(forKey: "devBackToGrid") { browse.openAlbumID = nil }
        }
    }
}
