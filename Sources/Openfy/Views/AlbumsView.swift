import OpenfyCore
import SwiftUI

struct AlbumsView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(BrowseState.self) private var browse

    var body: some View {
        let albums = browse.albumSort.sort(browse.filter.apply(library.index.albums))
        VStack(spacing: 0) {
            BrowseHeader(title: "Albums", subtitle: subtitle(albums), showSort: true)
            if albums.isEmpty {
                NoResultsView()
            } else {
                ScrollView {
                    AlbumGrid(albums: albums)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                }
            }
        }
    }

    func subtitle(_ albums: [Album]) -> String {
        let total = library.index.albums.count
        return albums.count == total ? "\(total)" : "\(albums.count) of \(total)"
    }
}

struct AlbumGrid: View {
    let albums: [Album]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 164, maximum: 230), spacing: 24, alignment: .top)],
                  alignment: .leading, spacing: 30) {
            ForEach(albums) { album in
                AlbumCard(album: album)
            }
        }
    }
}

struct AlbumCard: View {
    let album: Album
    @Environment(PlayerController.self) private var player
    @Environment(BrowseState.self) private var browse
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            CoverView(key: album.artworkKey)
                .shadow(color: .black.opacity(hovering ? 0.5 : 0.25), radius: hovering ? 14 : 6, y: hovering ? 8 : 3)
                .overlay(alignment: .bottomTrailing) {
                    if hovering {
                        Button {
                            player.play(album.tracks)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.black)
                                .offset(x: 1)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(.white))
                                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .scaleEffect(hovering ? 1.015 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    QualityTag(text: album.qualitySummary, tier: album.quality)
                    if let year = album.year {
                        Text(String(year))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .padding(.top, 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .onTapGesture { browse.open(album) }
        .contextMenu { AlbumMenu(album: album) }
    }
}

struct AlbumMenu: View {
    let album: Album
    @Environment(PlayerController.self) private var player
    @Environment(BrowseState.self) private var browse

    var body: some View {
        Button("Play") { player.play(album.tracks) }
        Button("Shuffle") { player.play(album.tracks, shuffled: true) }
        Divider()
        Button("Play Next") { player.playNext(album.tracks) }
        Button("Add to Queue") { player.addToQueue(album.tracks) }
        Divider()
        Button("Go to Artist") { browse.showArtist(album.artist) }
        Button("Show in Finder") { revealInFinder(Array(album.tracks.prefix(1))) }
    }
}
