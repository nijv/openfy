import AVFoundation
import CoreAudio
import Foundation

/// What's happening between the file and the speakers.
struct OutputStatus: Equatable {
    var deviceName = ""
    var deviceRate: Double = 0
    var sourceRate: Double = 0
    var isBluetooth = false
    var volumeIsUnity = true
    var active = false

    var rateMatched: Bool { deviceRate > 0 && abs(deviceRate - sourceRate) < 0.5 }
    /// Samples reach the device untouched: same sample rate (no resampling) and no volume scaling.
    var isBitPerfect: Bool { active && rateMatched && volumeIsUnity && !isBluetooth }
}

/// Plays files through AVAudioEngine with the device clocked at the file's native rate.
///
/// Lossless path: AVAudioFile decodes FLAC/ALAC/WAV/AIFF to 32-bit float, which represents every
/// 16- and 24-bit sample exactly. The output device is switched to the file's sample rate, so no
/// resampling happens, and at 100% volume the mixer multiplies by exactly 1.0. The result is a
/// bit-for-bit copy of the source reaching CoreAudio.
///
/// Gapless: when the next track has the same format it is scheduled right behind the current one.
/// All methods must be called on the main thread.
final class PlaybackEngine {
    var onAdvance: (() -> Void)?          // the pre-scheduled next track has begun (gapless)
    var onFinished: (() -> Void)?         // current track ended with nothing scheduled after it
    var onStatusChange: ((OutputStatus) -> Void)?
    var onRebuild: (() -> Void)?          // output was rebuilt (device change); position may have moved

    var volume: Float = 1 {
        didSet {
            engine?.mainMixerNode.outputVolume = volume
            publishStatus()
        }
    }

    private(set) var isPlaying = false
    private(set) var currentURL: URL?

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var connectedFormat: AVAudioFormat?
    private var configObserver: NSObjectProtocol?

    private var currentFile: AVAudioFile?
    private var startFrame: AVAudioFramePosition = 0
    private var segmentBase: AVAudioFramePosition = 0
    private var currentSegmentFrames: AVAudioFramePosition = 0
    private var currentSegmentID = -1

    private var nextURL: URL?
    private var nextFile: AVAudioFile?
    private var nextSegmentID: Int?
    private var segmentCounter = 0

    private var lastPosition: Double = 0
    private var rebuildScheduled = false
    private var originalDeviceRates: [AudioDeviceID: Double] = [:]

    var duration: Double {
        guard let f = currentFile else { return 0 }
        return Double(f.length) / f.processingFormat.sampleRate
    }

    var currentTime: Double {
        guard isPlaying, let player, let file = currentFile,
              let nodeTime = player.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return lastPosition }
        let frames = playerTime.sampleTime - segmentBase + startFrame
        let t = Double(frames) / file.processingFormat.sampleRate
        lastPosition = min(max(0, t), duration)
        return lastPosition
    }

    // MARK: Transport

    func load(url: URL, at seconds: Double = 0, autoplay: Bool) throws {
        let file = try AVAudioFile(forReading: url)
        try prepareOutput(for: file.processingFormat)
        resetSchedule()
        currentFile = file
        currentURL = url
        scheduleCurrent(from: AVAudioFramePosition(seconds * file.processingFormat.sampleRate))
        lastPosition = seconds
        if autoplay { play() } else { isPlaying = false }
        publishStatus()
    }

    func play() {
        guard let engine, let player, currentFile != nil else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        _ = currentTime
        isPlaying = false
        player?.pause()
        engine?.pause()
    }

    func stop() {
        resetSchedule()
        tearDown()
        currentFile = nil
        currentURL = nil
        isPlaying = false
        lastPosition = 0
        publishStatus()
    }

    func seek(to seconds: Double) {
        guard let file = currentFile, player != nil else { return }
        let wasPlaying = isPlaying
        let pendingNext = nextURL
        resetSchedule()
        let clamped = min(max(0, seconds), duration)
        scheduleCurrent(from: AVAudioFramePosition(clamped * file.processingFormat.sampleRate))
        lastPosition = clamped
        if let pendingNext { preloadNext(url: pendingNext) }
        if wasPlaying { play() }
    }

    /// Queue the next file for gapless playback. If its format differs from the current output,
    /// it's remembered but not scheduled; the switch happens when the current track ends.
    func preloadNext(url: URL?) {
        if nextSegmentID != nil {
            guard url != nextURL else { return }
            // A different track is already scheduled: re-schedule the current one from here.
            nextURL = url
            seek(to: currentTime)
            return
        }
        nextURL = url
        guard let url, let player, let format = connectedFormat, currentFile != nil,
              let file = try? AVAudioFile(forReading: url),
              file.processingFormat.sampleRate == format.sampleRate,
              file.processingFormat.channelCount == format.channelCount,
              file.length > 0 else { return }

        segmentCounter += 1
        let id = segmentCounter
        nextSegmentID = id
        nextFile = file
        player.scheduleSegment(file, startingFrame: 0, frameCount: AVAudioFrameCount(file.length), at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.segmentDidFinish(id) }
        }
    }

    /// Puts device sample rates back the way they were before Openfy changed them.
    func restoreDeviceRates() {
        for (device, rate) in originalDeviceRates {
            AudioDevice.setNominalSampleRate(device, rate)
        }
        originalDeviceRates.removeAll()
    }

    // MARK: Scheduling

    private func scheduleCurrent(from frame: AVAudioFramePosition) {
        guard let file = currentFile, let player else { return }
        let start = min(max(0, frame), file.length)
        startFrame = start
        segmentBase = 0
        currentSegmentFrames = file.length - start
        segmentCounter += 1
        let id = segmentCounter
        currentSegmentID = id
        guard currentSegmentFrames > 0 else {
            DispatchQueue.main.async { [weak self] in self?.segmentDidFinish(id) }
            return
        }
        player.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(currentSegmentFrames),
                               at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.segmentDidFinish(id) }
        }
    }

    /// Detects the end of the current track from the player's own sample clock.
    /// `.dataPlayedBack` completions can arrive seconds late (they're delivered in order, behind
    /// completions of segments cancelled by a seek), so they're only a fallback; whichever comes
    /// first wins and the other is ignored by the segment-ID check.
    func pollSegmentEnd() {
        guard isPlaying, currentSegmentID > 0, let player,
              let nodeTime = player.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return }
        if playerTime.sampleTime - segmentBase >= currentSegmentFrames {
            segmentDidFinish(currentSegmentID)
        }
    }

    private func segmentDidFinish(_ id: Int) {
        guard id == currentSegmentID else { return } // stale (stopped, seeked, or already handled)
        if let file = nextFile, let nextID = nextSegmentID {
            segmentBase += currentSegmentFrames
            startFrame = 0
            currentSegmentFrames = file.length
            currentSegmentID = nextID
            currentFile = file
            currentURL = nextURL
            nextFile = nil
            nextSegmentID = nil
            nextURL = nil
            lastPosition = 0
            onAdvance?()
        } else {
            currentSegmentID = -1
            lastPosition = duration
            onFinished?()
        }
    }

    /// Invalidate everything scheduled on the player.
    private func resetSchedule() {
        currentSegmentID = -1
        nextSegmentID = nil
        nextFile = nil
        segmentBase = 0
        player?.stop()
    }

    // MARK: Output

    private func prepareOutput(for format: AVAudioFormat) throws {
        let device = AudioDevice.defaultOutput()
        let targetRate = device.map { AudioDevice.bestRate(for: format.sampleRate, device: $0) }
        let deviceRate = device.flatMap(AudioDevice.nominalSampleRate)

        if engine != nil, let connected = connectedFormat,
           connected.sampleRate == format.sampleRate, connected.channelCount == format.channelCount,
           targetRate == nil || deviceRate == targetRate {
            return // already set up for this format
        }

        tearDown()

        if let device, let targetRate, let deviceRate, abs(deviceRate - targetRate) > 0.5 {
            if originalDeviceRates[device] == nil { originalDeviceRates[device] = deviceRate }
            if AudioDevice.setNominalSampleRate(device, targetRate) {
                AudioDevice.waitForRate(device, targetRate)
            }
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
        try engine.start()

        self.engine = engine
        self.player = player
        connectedFormat = format
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.scheduleRebuild() }
    }

    private func tearDown() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil
        connectedFormat = nil
    }

    /// Output device changed (headphones plugged in, DAC connected, rate changed elsewhere).
    private func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.rebuildScheduled = false
            guard let url = self.currentURL else {
                self.tearDown()
                self.publishStatus()
                return
            }
            let position = self.lastPosition
            let wasPlaying = self.isPlaying
            let next = self.nextURL
            self.resetSchedule()
            self.tearDown()
            do {
                try self.load(url: url, at: position, autoplay: wasPlaying)
                self.preloadNext(url: next)
            } catch {
                self.isPlaying = false
            }
            self.onRebuild?()
        }
    }

    private func publishStatus() {
        var s = OutputStatus()
        if let device = AudioDevice.defaultOutput() {
            s.deviceName = AudioDevice.name(device)
            s.deviceRate = AudioDevice.nominalSampleRate(device) ?? 0
            s.isBluetooth = AudioDevice.isBluetooth(device)
        }
        s.sourceRate = connectedFormat?.sampleRate ?? 0
        s.volumeIsUnity = volume >= 0.9999
        s.active = currentFile != nil
        onStatusChange?(s)
    }
}
