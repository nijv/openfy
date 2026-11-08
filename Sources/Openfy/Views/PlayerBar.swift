import OpenfyCore
import SwiftUI

struct PlayerBar: View {
    /// Narrow window: fewer tools on the right.
    var compact = false
    @Environment(PlayerController.self) private var player
    @Environment(WindowModel.self) private var windowModel
    @Environment(LibraryModel.self) private var library
    @Environment(BrowseState.self) private var browse
    @State private var coverHovering = false

    var body: some View {
        HStack(spacing: 24) {
            nowPlaying
                .frame(width: compact ? 200 : 290, alignment: .leading)
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                TransportControls()
                PositionBar()
            }
            .frame(maxWidth: 580)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if !compact {
                    SignalPathButton()
                    VolumeControl()
                }
                QueueButton()
                RemoteButton()
                IconButton(systemName: "pip.enter", size: 12, help: "Mini Player (⌥⌘M)") {
                    windowModel.toggleMini()
                }
                IconButton(systemName: "arrow.up.left.and.arrow.down.right", size: 12, help: "Now Playing (⇧⌘F)") {
                    browse.presentNowPlaying()
                }
                .disabled(player.current == nil)
            }
            .frame(width: compact ? 150 : 350, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 84)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    @ViewBuilder private var nowPlaying: some View {
        if let track = player.current {
            HStack(spacing: 12) {
                CoverView(key: track.artworkKey, size: .thumb, cornerRadius: 5)
                    .frame(width: 54, height: 54)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    .overlay {
                        if coverHovering {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.45))
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .onHover { coverHovering = $0 }
                    .onTapGesture { browse.presentNowPlaying() }
                    .help("Now Playing (⇧⌘F)")
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    if let error = player.errorMessage {
                        Text(error).font(.system(size: 10)).foregroundStyle(Theme.warning).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let album = library.album(for: track) { browse.open(album) }
                }
                .help("Go to album")
            }
        } else {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 5).fill(Theme.placeholder).frame(width: 54, height: 54)
                Text("Not playing").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
        }
    }
}

private struct TransportControls: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        HStack(spacing: 20) {
            IconButton(systemName: "shuffle", size: 13, isActive: player.shuffle, help: "Shuffle") {
                player.toggleShuffle()
            }
            IconButton(systemName: "backward.fill", size: 15, help: "Previous (⌘←)") { player.previous() }
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .offset(x: player.isPlaying ? 0 : 1)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(player.current == nil ? 0.4 : 0.95)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)
            .help("Play / Pause (Space)")
            IconButton(systemName: "forward.fill", size: 15, help: "Next (⌘→)") { player.next() }
            IconButton(systemName: player.repeatMode == .one ? "repeat.1" : "repeat", size: 13,
                       isActive: player.repeatMode != .off, help: "Repeat: \(player.repeatMode.rawValue)") {
                player.cycleRepeat()
            }
        }
    }
}

/// Isolated so that only this view redraws as the position ticks.
private struct PositionBar: View {
    @Environment(PlayerController.self) private var player
    @State private var dragFraction: Double?

    var body: some View {
        let duration = player.duration
        let shown = dragFraction.map { $0 * duration } ?? player.position
        HStack(spacing: 10) {
            Text(Format.duration(shown))
                .frame(width: 44, alignment: .trailing)
            ThinSlider(value: duration > 0 ? player.position / duration : 0,
                       onDragChange: { dragFraction = $0 }) { f in
                player.seek(to: f * duration)
            }
            .disabled(player.current == nil)
            Text(duration > 0 ? "-" + Format.duration(max(0, duration - shown)) : "0:00")
                .frame(width: 44, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(Theme.tertiary)
    }
}

private struct VolumeControl: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        HStack(spacing: 6) {
            Button {
                player.volume = player.volume > 0 ? 0 : 1
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(player.volume >= 0.9999 ? "Volume 100% — bit-perfect" : "Volume \(Int(player.volume * 100))%")
            ThinSlider(value: player.volume, live: true) { f in
                // Snap to exactly 100% near the top so bit-perfect output is easy to hit.
                player.volume = f > 0.97 ? 1 : f
            }
            .frame(width: 84)
        }
    }

    var icon: String {
        switch player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

// MARK: - Signal path

struct SignalPathButton: View {
    @Environment(PlayerController.self) private var player
    @State private var showing = false

    var body: some View {
        if let track = player.current {
            Button {
                showing.toggle()
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(dotColor).frame(width: 6, height: 6)
                    Text(shortLabel(track))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(track.quality == .hiRes ? Theme.hiRes : Theme.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(player.output.isBitPerfect ? "Bit-perfect playback" : "Signal path")
            .popover(isPresented: $showing, arrowEdge: .top) {
                SignalPathView(track: track, output: player.output, volume: player.volume)
            }
        }
    }

    var dotColor: Color {
        let o = player.output
        if !o.active { return Theme.tertiary }
        return o.isBitPerfect ? Theme.perfect : Theme.warning
    }

    func shortLabel(_ t: Track) -> String {
        if t.codec.isLossless { return "\(t.bitDepth ?? 16)/\(Format.sampleRateShort(t.sampleRate))" }
        if let b = t.bitrate { return "\(t.codec.displayName) \(b)" }
        return t.codec.displayName
    }
}

struct SignalPathView: View {
    let track: Track
    let output: OutputStatus
    let volume: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(output.isBitPerfect ? Theme.perfect : Theme.warning).frame(width: 8, height: 8)
                Text(headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            }

            VStack(alignment: .leading, spacing: 10) {
                row("Source", "\(track.codec.displayName)  ·  \(track.qualityLabel)  ·  \(channels)")
                row("Decoder", track.codec.isLossless ? "Core Audio  ·  lossless → 32-bit float (exact)" : "Core Audio  ·  32-bit float")
                row("Resampling", output.rateMatched ? "None — device runs at \(Format.sampleRate(output.deviceRate))"
                    : "\(Format.sampleRate(output.sourceRate)) → \(Format.sampleRate(output.deviceRate)) (device limit)")
                row("Volume", volume >= 0.9999 ? "100%  ·  untouched" : "\(Int((volume * 100).rounded()))%  ·  scaled")
                row("Output", output.deviceName + (output.isBluetooth ? "  ·  Bluetooth" : ""))
            }

            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 360)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    var channels: String {
        switch track.channels {
        case 1: "Mono"
        case 2: "Stereo"
        default: "\(track.channels) ch"
        }
    }

    var headline: String {
        if output.isBitPerfect { return "Bit-perfect" }
        if output.isBluetooth { return "Bluetooth output" }
        if !output.rateMatched { return "Resampled by macOS" }
        if !output.volumeIsUnity { return "Volume below 100%" }
        return "Playing"
    }

    var note: String {
        if output.isBitPerfect {
            return "Every sample reaches your output device exactly as it is stored in the file. Use your Mac's or DAC's volume controls to stay bit-perfect."
        }
        if output.isBluetooth {
            return "Bluetooth headphones re-encode audio wirelessly (AAC/SBC), so no player can deliver lossless over Bluetooth. Use wired headphones or a USB DAC for full quality."
        }
        if !output.rateMatched {
            return "This output device doesn't support \(Format.sampleRate(output.sourceRate)), so macOS converts it with its high-quality resampler. A USB DAC that supports this rate will play it natively."
        }
        return "Set the app volume to 100% and use your Mac's volume keys instead to get bit-perfect output."
    }

    func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.tertiary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Queue

private struct QueueButton: View {
    @Environment(PlayerController.self) private var player
    @State private var showing = false

    var body: some View {
        IconButton(systemName: "list.bullet", size: 13, isActive: showing, help: "Queue") { showing.toggle() }
            .popover(isPresented: $showing, arrowEdge: .top) {
                QueueView()
                    .environment(player)
            }
    }
}

private struct QueueView: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                if !player.upNext.isEmpty {
                    Button("Clear") { player.clearUpNext() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            if let index = player.index, player.queue.indices.contains(index) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        label("Now Playing")
                        QueueRow(track: player.queue[index], position: index, isCurrent: true)
                        if !player.upNext.isEmpty {
                            label("Up Next").padding(.top, 10)
                            ForEach(Array(player.queue.enumerated()).dropFirst(index + 1), id: \.offset) { i, t in
                                QueueRow(track: t, position: i, isCurrent: false)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            } else {
                Text("Nothing queued")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(30)
            }
        }
        .frame(width: 340, height: 440)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    func label(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Theme.tertiary)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }
}

private struct QueueRow: View {
    let track: Track
    let position: Int
    let isCurrent: Bool
    @Environment(PlayerController.self) private var player
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            CoverView(key: track.artworkKey, cornerRadius: 3).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Theme.text).lineLimit(1)
                Text(track.artist).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer()
            if hovering && !isCurrent {
                Button {
                    player.removeFromQueue(at: position)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text(Format.duration(track.duration))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .hoverHighlight(hovering, selected: isCurrent)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { player.jump(to: position) }
    }
}
