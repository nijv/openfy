import OpenfyCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(BrowseState.self) private var browse
    @Environment(WindowModel.self) private var windowModel
    @State private var dropTargeted = false

    var body: some View {
        GeometryReader { geo in
            Group {
                // Too small for the library: the window becomes the mini player.
                if WindowModel.isMiniSize(geo.size) {
                    MiniPlayerView()
                } else {
                    fullLayout(width: geo.size.width)
                }
            }
            .onAppear { windowModel.contentSizeChanged(geo.size) }
            .onChange(of: geo.size) { _, size in windowModel.contentSizeChanged(size) }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: WindowModel.miniMinimumSide, minHeight: WindowModel.miniMinimumSide)
        .background(Theme.background)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(10)
                    .overlay(Text("Drop folders to add them to your library")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text))
                    .background(Color.black.opacity(0.5))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return }
                    DispatchQueue.main.async { library.addFolders([url]) }
                }
            }
            return true
        }
    }

    private func fullLayout(width: CGFloat) -> some View {
        let sidebarWidth: CGFloat = width < 880 ? 184 : 220
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: sidebarWidth)
                Rectangle().fill(Theme.hairline).frame(width: 1)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.contentWidth, width - sidebarWidth - 1)
            }
            PlayerBar(compact: width < 1000)
        }
        .background(Theme.background)
        .overlay {
            if browse.showNowPlaying {
                NowPlayingView()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                            removal: .opacity))
                    .zIndex(1)
            }
        }
        .overlay {
            if let key = browse.viewerArtworkKey {
                CoverViewer(key: key)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if library.hasLoaded && library.tracks.isEmpty && !library.isScanning {
            EmptyLibraryView()
        } else if !library.hasLoaded || (library.tracks.isEmpty && library.isScanning) {
            ScanningView()
        } else if let id = browse.openAlbumID, let album = library.index.albumsByID[id] {
            AlbumDetailView(album: album)
                .id(album.id)
        } else {
            switch browse.section {
            case .albums: AlbumsView()
            case .artists: ArtistsView()
            case .songs: SongsView()
            }
        }
    }
}

private struct EmptyLibraryView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 54, weight: .ultraLight))
                .foregroundStyle(Theme.tertiary)
            VStack(spacing: 6) {
                Text("Your music, untouched")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Add the folder with your ripped CDs and downloads.\nFLAC, ALAC, WAV, AIFF, MP3 and AAC — played bit-perfect.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .lineSpacing(3)
            }
            PillButton(title: "Add Music Folder", systemName: "plus") { library.chooseFolders() }
                .padding(.top, 6)
            Text("or drag a folder here")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScanningView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.small)
            if let p = library.scanProgress, p.total > 0 {
                Text("Reading \(p.processed) of \(p.total) files")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                ProgressView(value: Double(p.processed), total: Double(p.total))
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 220)
            } else {
                Text(library.hasLoaded ? "Looking for music…" : "Loading library…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1000
}

extension EnvironmentValues {
    /// Width of the main content column (narrow windows get more compact headers).
    var contentWidth: CGFloat {
        get { self[ContentWidthKey.self] }
        set { self[ContentWidthKey.self] = newValue }
    }
}
