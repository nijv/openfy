import OpenfyCore
import SwiftUI

struct ArtistsView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.contentWidth) private var contentWidth
    @Environment(BrowseState.self) private var browse

    var body: some View {
        let all = library.index.albums
        let visibleIDs = Set(browse.filter.apply(all).map(\.id))
        // Albums that pass the chips (quality/format/genre/decade) regardless of the search text.
        let facetIDs = Set(Self.withoutSearch(browse.filter).apply(all).map(\.id))
        let query = browse.filter.search.trimmingCharacters(in: .whitespaces).folded
        let nameMatches = { (a: ArtistSummary) in !query.isEmpty && a.name.folded.contains(query) }
        let albumsOf = { (a: ArtistSummary) -> [Album] in
            let match = nameMatches(a)
            return a.albumIDs.filter { visibleIDs.contains($0) || (match && facetIDs.contains($0)) }
                .compactMap { library.index.albumsByID[$0] }
        }
        let artists = library.index.artists.filter { !albumsOf($0).isEmpty }
        let selected = artists.first { $0.name == browse.selectedArtist } ?? artists.first

        VStack(spacing: 0) {
            BrowseHeader(title: "Artists", subtitle: "\(artists.count)")
            if artists.isEmpty {
                NoResultsView()
            } else {
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(artists) { artist in
                                    ArtistRow(artist: artist, selected: artist.name == selected?.name) {
                                        browse.selectedArtist = artist.name
                                    }
                                    .id(artist.name)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                        .onAppear {
                            if let name = browse.selectedArtist { proxy.scrollTo(name, anchor: .center) }
                        }
                    }
                    .frame(width: contentWidth < 760 ? 210 : 270)

                    Rectangle().fill(Theme.hairline).frame(width: 1)

                    if let selected {
                        ArtistDetail(artist: selected, albums: albumsOf(selected))
                        .id(selected.name)
                    }
                }
            }
        }
    }
}

extension ArtistsView {
    static func withoutSearch(_ filter: LibraryFilter) -> LibraryFilter {
        var f = filter
        f.search = ""
        return f
    }
}

private struct ArtistRow: View {
    let artist: ArtistSummary
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                CoverView(key: artist.artworkKey, cornerRadius: 18)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(artist.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Theme.text : Theme.text.opacity(0.85))
                        .lineLimit(1)
                    Text(artist.albumIDs.count == 1 ? "1 album" : "\(artist.albumIDs.count) albums")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .hoverHighlight(hovering, selected: selected, radius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ArtistDetail: View {
    let artist: ArtistSummary
    let albums: [Album]
    @Environment(PlayerController.self) private var player

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Buttons beside the name, or under it when the pane is narrow.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        titleBlock
                        Spacer()
                        buttons
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        titleBlock
                        buttons
                    }
                }
                AlbumGrid(albums: albums)
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(artist.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            Text("\(albums.count) albums  ·  \(albums.reduce(0) { $0 + $1.tracks.count }) songs")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            PillButton(title: "Play", systemName: "play.fill") {
                player.play(albums.flatMap(\.tracks))
            }
            PillButton(title: "Shuffle", systemName: "shuffle", primary: false) {
                player.play(albums.flatMap(\.tracks), shuffled: true)
            }
        }
    }
}
