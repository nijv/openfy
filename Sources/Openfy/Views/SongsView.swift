import OpenfyCore
import SwiftUI

struct SongsView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(BrowseState.self) private var browse

    var body: some View {
        let tracks = browse.filter.apply(library.tracks)
        VStack(spacing: 0) {
            BrowseHeader(title: "Songs", subtitle: tracks.count == library.tracks.count
                         ? "\(tracks.count)" : "\(tracks.count) of \(library.tracks.count)")
            if tracks.isEmpty {
                NoResultsView()
            } else {
                SongsTable(tracks: tracks)
            }
        }
    }
}

private struct SongsTable: View {
    let tracks: [Track]
    @Environment(PlayerController.self) private var player
    @Environment(LibraryModel.self) private var library
    @Environment(BrowseState.self) private var browse
    @State private var selection = Set<Track.ID>()
    @State private var sortOrder: [KeyPathComparator<Track>] = [
        KeyPathComparator(\Track.albumArtist.sortKey),
        KeyPathComparator(\Track.yearValue),
        KeyPathComparator(\Track.album.sortKey),
        KeyPathComparator(\Track.discValue),
        KeyPathComparator(\Track.trackValue),
    ]

    var body: some View {
        let sorted = tracks.sorted(using: sortOrder)
        Table(sorted, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title.sortKey) { t in
                HStack(spacing: 6) {
                    if player.current?.path == t.path {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.text)
                    }
                    Text(t.title).foregroundStyle(Theme.text)
                }
            }
            .width(min: 160, ideal: 280)
            TableColumn("Artist", value: \.artist.sortKey) { t in
                Text(t.artist).foregroundStyle(Theme.secondary)
            }
            .width(min: 100, ideal: 180)
            TableColumn("Album", value: \.album.sortKey) { t in
                Text(t.album).foregroundStyle(Theme.secondary)
            }
            .width(min: 100, ideal: 200)
            TableColumn("Year", value: \.yearValue) { t in
                Text(t.year.map(String.init) ?? "").foregroundStyle(Theme.tertiary).monospacedDigit()
            }
            .width(46)
            TableColumn("Quality", value: \.qualityRank) { t in
                QualityTag(text: t.compactQuality, tier: t.quality)
            }
            .width(min: 80, ideal: 96)
            TableColumn("Time", value: \.duration) { t in
                Text(Format.duration(t.duration)).foregroundStyle(Theme.tertiary).monospacedDigit()
            }
            .width(52)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .font(.system(size: 12.5))
        .padding(.horizontal, 20)
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            let picked = sorted.filter { ids.contains($0.id) }
            Button("Play") { play(ids, in: sorted) }
            Button("Play Next") { player.playNext(picked) }
            Button("Add to Queue") { player.addToQueue(picked) }
            if picked.count == 1, let album = library.album(for: picked[0]) {
                Divider()
                Button("Go to Album") { browse.open(album) }
            }
            Divider()
            Button("Show in Finder") { revealInFinder(picked) }
        } primaryAction: { ids in
            play(ids, in: sorted)
        }
    }

    /// Double-click plays from that song through the rest of the list as shown.
    private func play(_ ids: Set<Track.ID>, in list: [Track]) {
        guard let start = list.firstIndex(where: { ids.contains($0.id) }) else { return }
        player.play(list, startAt: start)
    }
}

extension Track {
    var yearValue: Int { year ?? 0 }
    var discValue: Int { discNumber ?? 1 }
    var trackValue: Int { trackNumber ?? 0 }
    var qualityRank: Double {
        switch quality {
        case .lossy: Double(bitrate ?? 0)
        case .cd, .hiRes: 10_000 + Double(bitDepth ?? 16) * 1_000_000 + sampleRate
        }
    }
}
