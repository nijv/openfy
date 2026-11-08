import OpenfyCore
import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @Environment(PlayerController.self) private var player
    @Environment(BrowseState.self) private var browse
    @Environment(\.contentWidth) private var contentWidth

    private var narrow: Bool { contentWidth < 760 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    browse.openAlbumID = nil
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text(browse.section.title).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
                .padding(.bottom, 22)

                header
                    .padding(.bottom, 34)

                trackList
            }
            .padding(.horizontal, narrow ? 24 : 36)
            .padding(.top, 40)
            .padding(.bottom, 40)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onExitCommand { browse.openAlbumID = nil }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: narrow ? 22 : 30) {
            CoverView(key: album.artworkKey, size: .large, cornerRadius: 8)
                .frame(width: narrow ? 170 : 240, height: narrow ? 170 : 240)
                .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
                .onTapGesture {
                    if let current = player.current, album.tracks.contains(where: { $0.path == current.path }) {
                        browse.presentNowPlaying()
                    } else {
                        browse.showCover(album.artworkKey)
                    }
                }
                .help("View cover")

            VStack(alignment: .leading, spacing: 8) {
                Text(album.title)
                    .font(.system(size: narrow ? 26 : 34, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Button {
                    browse.showArtist(album.artist)
                } label: {
                    Text(album.artist)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.text.opacity(0.85))
                }
                .buttonStyle(.plain)

                Text(details)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 2)

                HStack(spacing: 8) {
                    QualityTag(text: qualityText, tier: album.quality, large: true)
                    if album.quality == .hiRes {
                        QualityTag(text: "HI-RES", tier: .hiRes, large: true)
                    } else if album.quality == .cd {
                        QualityTag(text: "LOSSLESS", tier: .cd, large: true)
                    }
                }
                .padding(.top, 4)

                HStack(spacing: 10) {
                    PillButton(title: "Play", systemName: "play.fill") { player.play(album.tracks) }
                    PillButton(title: "Shuffle", systemName: "shuffle", primary: false) {
                        player.play(album.tracks, shuffled: true)
                    }
                    Menu {
                        AlbumMenu(album: album)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(Theme.secondary)
                    .padding(.leading, 4)
                }
                .padding(.top, 14)
            }
        }
    }

    private var details: String {
        var parts: [String] = []
        if let y = album.year { parts.append(String(y)) }
        if let g = album.genre { parts.append(g) }
        parts.append(album.tracks.count == 1 ? "1 song" : "\(album.tracks.count) songs")
        if album.discCount > 1 { parts.append("\(album.discCount) discs") }
        parts.append(Format.longDuration(album.duration))
        return parts.joined(separator: "  ·  ")
    }

    private var qualityText: String {
        let codecs = album.codecs.map(\.displayName).joined(separator: " / ")
        if album.quality == .lossy {
            let rates = album.tracks.compactMap(\.bitrate)
            if let lo = rates.min(), let hi = rates.max() {
                return lo == hi ? "\(codecs)  \(hi) kbps" : "\(codecs)  \(lo)–\(hi) kbps"
            }
            return codecs
        }
        return "\(codecs)  \(album.maxBitDepth ?? 16)-bit / \(Format.sampleRate(album.maxSampleRate))"
    }

    private var trackList: some View {
        let discs = Dictionary(grouping: album.tracks.indices, by: { album.tracks[$0].discNumber ?? 1 })
        let showDiscs = discs.count > 1
        let mixedQuality = Set(album.tracks.map(\.compactQuality)).count > 1
        let showArtist = Set(album.tracks.map(\.artist)).count > 1 || album.tracks.first?.artist != album.artist

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(discs.keys.sorted(), id: \.self) { disc in
                if showDiscs {
                    HStack(spacing: 8) {
                        Image(systemName: "opticaldisc").font(.system(size: 11))
                        Text("Disc \(disc)").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.tertiary)
                    .padding(.top, disc == discs.keys.min() ? 0 : 22)
                    .padding(.bottom, 8)
                    .padding(.leading, 12)
                }
                ForEach(discs[disc]!, id: \.self) { i in
                    TrackRow(track: album.tracks[i], number: album.tracks[i].trackNumber ?? i + 1,
                             showArtist: showArtist, showQuality: mixedQuality) {
                        player.play(album.tracks, startAt: i)
                    }
                }
            }
        }
    }
}

struct TrackRow: View {
    let track: Track
    let number: Int
    var showArtist = false
    var showQuality = false
    let onPlay: () -> Void

    @Environment(PlayerController.self) private var player
    @State private var hovering = false

    var body: some View {
        let isCurrent = player.current?.path == track.path
        HStack(spacing: 14) {
            ZStack {
                if hovering {
                    Button(action: onPlay) {
                        Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(Theme.text)
                    }
                    .buttonStyle(.plain)
                } else if isCurrent {
                    Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if showArtist {
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if showQuality {
                QualityTag(text: track.compactQuality, tier: track.quality)
            }
            Text(Format.duration(track.duration))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, showArtist ? 6 : 9)
        .hoverHighlight(hovering, selected: isCurrent)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .contextMenu {
            Button("Play") { onPlay() }
            Button("Play Next") { player.playNext([track]) }
            Button("Add to Queue") { player.addToQueue([track]) }
            Divider()
            Button("Show in Finder") { revealInFinder([track]) }
        }
        .help("\(track.compactQuality) · \(track.channels == 1 ? "Mono" : track.channels == 2 ? "Stereo" : "\(track.channels) ch")")
    }
}
