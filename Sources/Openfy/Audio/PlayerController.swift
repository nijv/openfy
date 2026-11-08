import AppKit
import Foundation
import Observation
import OpenfyCore

enum RepeatMode: String {
    case off, all, one
}

/// Queue, transport and state for the UI. Main thread only.
@Observable
final class PlayerController {
    private(set) var queue: [Track] = []
    private(set) var index: Int?
    private(set) var isPlaying = false
    /// Updated ~5×/s. Only the scrubber should read this, so the rest of the UI doesn't redraw.
    private(set) var position: Double = 0
    private(set) var shuffle = false
    var repeatMode: RepeatMode = .off {
        didSet {
            preloadNext()
            UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
        }
    }
    var volume: Double = 1 {
        didSet {
            engine.volume = Float(min(max(volume, 0), 1))
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }
    private(set) var output = OutputStatus()
    var errorMessage: String?

    @ObservationIgnored private let engine = PlaybackEngine()
    @ObservationIgnored private var unshuffledQueue: [Track] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored lazy var nowPlaying = NowPlayingCenter(player: self)

    var current: Track? { index.flatMap { queue.indices.contains($0) ? queue[$0] : nil } }
    var duration: Double { current?.duration ?? 0 }
    var upNext: [Track] {
        guard let index, index + 1 < queue.count else { return [] }
        return Array(queue[(index + 1)...])
    }

    init() {
        let d = UserDefaults.standard
        if d.object(forKey: "volume") != nil { volume = d.double(forKey: "volume") }
        engine.volume = Float(volume)
        repeatMode = RepeatMode(rawValue: d.string(forKey: "repeatMode") ?? "") ?? .off

        engine.onAdvance = { [weak self] in self?.handleGaplessAdvance() }
        engine.onFinished = { [weak self] in self?.handleFinished() }
        engine.onStatusChange = { [weak self] s in self?.output = s }
        engine.onRebuild = { [weak self] in self?.syncFromEngine() }

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common) // keeps ticking during full-screen transitions and resizes
        self.timer = timer
    }

    // MARK: Starting playback

    func play(_ tracks: [Track], startAt start: Int = 0, shuffled: Bool = false, autoplay: Bool = true) {
        guard !tracks.isEmpty else { return }
        unshuffledQueue = tracks
        if shuffled {
            var rest = tracks
            let first = rest.remove(at: Int.random(in: 0..<rest.count))
            queue = [first] + rest.shuffled()
            shuffle = true
            begin(at: 0, autoplay: autoplay)
        } else {
            queue = tracks
            shuffle = false
            begin(at: min(max(0, start), tracks.count - 1), autoplay: autoplay)
        }
    }

    func playNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard let index else { return play(tracks) }
        queue.insert(contentsOf: tracks, at: index + 1)
        unshuffledQueue.append(contentsOf: tracks)
        preloadNext()
    }

    func addToQueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard index != nil else { return play(tracks) }
        queue.append(contentsOf: tracks)
        unshuffledQueue.append(contentsOf: tracks)
        preloadNext()
    }

    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        begin(at: i)
    }

    func removeFromQueue(at i: Int) {
        guard queue.indices.contains(i), i != index else { return }
        let removed = queue.remove(at: i)
        if let u = unshuffledQueue.firstIndex(of: removed) { unshuffledQueue.remove(at: u) }
        if let index, i < index { self.index = index - 1 }
        preloadNext()
    }

    func clearUpNext() {
        guard let index else { return }
        queue.removeSubrange((index + 1)...)
        preloadNext()
    }

    // MARK: Transport

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        guard isPlaying else { return }
        engine.pause()
        isPlaying = false
        position = engine.currentTime
        nowPlaying.update()
    }

    func resume() {
        guard let index else {
            if !queue.isEmpty { begin(at: 0) }
            return
        }
        if engine.currentURL == nil {
            // Nothing loaded (stopped at the end, or restored session): load at the saved position.
            begin(at: index, from: position >= duration - 0.5 ? 0 : position)
            return
        }
        engine.play()
        isPlaying = engine.isPlaying
        nowPlaying.update()
    }

    func next() {
        guard let index, !queue.isEmpty else { return }
        if index + 1 < queue.count {
            begin(at: index + 1)
        } else if repeatMode != .off {
            begin(at: 0)
        }
    }

    func previous() {
        guard let index else { return }
        if position > 3 || index == 0 && repeatMode == .off {
            seek(to: 0)
        } else if index > 0 {
            begin(at: index - 1)
        } else {
            begin(at: queue.count - 1)
        }
    }

    func seek(to seconds: Double) {
        guard current != nil else { return }
        if engine.currentURL == nil {
            position = seconds
            return
        }
        engine.seek(to: seconds)
        position = engine.currentTime
        nowPlaying.update()
    }

    func changeVolume(by delta: Double) {
        volume = min(max(volume + delta, 0), 1)
    }

    func skip(by seconds: Double) {
        seek(to: min(max(0, position + seconds), duration))
    }

    func toggleShuffle() {
        guard let index, let current else {
            shuffle.toggle()
            return
        }
        if shuffle {
            // Restore the original order, keeping the current track playing.
            queue = unshuffledQueue
            self.index = queue.firstIndex(of: current) ?? 0
            shuffle = false
        } else {
            unshuffledQueue = queue
            var rest = queue
            rest.remove(at: index)
            queue = [current] + rest.shuffled()
            self.index = 0
            shuffle = true
        }
        preloadNext()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: Session

    func saveSession() {
        let d = UserDefaults.standard
        d.set(queue.map(\.path), forKey: "session.queue")
        d.set(index ?? -1, forKey: "session.index")
        d.set(position, forKey: "session.position")
    }

    /// Restores the last queue (paused) once the library has loaded.
    func restoreSession(using tracksByPath: [String: Track]) {
        guard queue.isEmpty else { return }
        let d = UserDefaults.standard
        let paths = d.stringArray(forKey: "session.queue") ?? []
        let restored = paths.compactMap { tracksByPath[$0] }
        let i = d.integer(forKey: "session.index")
        guard !restored.isEmpty, restored.count == paths.count, restored.indices.contains(i) else { return }
        queue = restored
        unshuffledQueue = restored
        index = i
        position = d.double(forKey: "session.position")
        nowPlaying.update()
    }

    /// Shows a queue without loading audio (development screenshots).
    func stage(_ tracks: [Track], index i: Int) {
        guard tracks.indices.contains(i) else { return }
        queue = tracks
        unshuffledQueue = tracks
        index = i
        position = 0
    }

    func shutdown() {
        saveSession()
        engine.stop()
        engine.restoreDeviceRates()
    }

    // MARK: Internals

    private func begin(at i: Int, from seconds: Double = 0, autoplay: Bool = true) {
        guard queue.indices.contains(i) else { return }
        index = i
        let track = queue[i]
        do {
            try engine.load(url: track.url, at: seconds, autoplay: autoplay)
            consecutiveFailures = 0
            isPlaying = engine.isPlaying
            position = seconds
            errorMessage = nil
            preloadNext()
        } catch {
            consecutiveFailures += 1
            errorMessage = "Couldn't play “\(track.title)” — the file may have moved."
            isPlaying = false
            if consecutiveFailures < 5, i + 1 < queue.count {
                begin(at: i + 1, autoplay: autoplay)
                return
            }
        }
        nowPlaying.update()
        saveSession()
    }

    /// Index of the track that follows automatically (repeat-one loops the same track).
    private func automaticNextIndex() -> Int? {
        guard let index else { return nil }
        if repeatMode == .one { return index }
        if index + 1 < queue.count { return index + 1 }
        if repeatMode == .all && !queue.isEmpty { return 0 }
        return nil
    }

    private func preloadNext() {
        guard engine.currentURL != nil else { return }
        engine.preloadNext(url: automaticNextIndex().map { queue[$0].url })
    }

    private func handleGaplessAdvance() {
        guard let next = automaticNextIndex() else { return }
        index = next
        position = 0
        preloadNext()
        nowPlaying.update()
        saveSession()
    }

    private func handleFinished() {
        if let next = automaticNextIndex() {
            begin(at: next) // different format: the output is re-clocked for the next file
        } else {
            engine.stop()
            isPlaying = false
            position = 0
            nowPlaying.update()
        }
    }

    private func syncFromEngine() {
        isPlaying = engine.isPlaying
        position = engine.currentTime
        nowPlaying.update()
    }

    private func tick() {
        guard isPlaying else { return }
        engine.pollSegmentEnd() // may advance to the next track or finish the queue
        guard isPlaying else { return }
        let t = engine.currentTime
        if abs(t - position) > 0.05 { position = t }
    }
}
