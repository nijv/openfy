import AppKit
import OpenfyCore
import SwiftUI

/// Full-window "Now Playing": a big cover over a blurred backdrop of the same artwork.
/// Controls and the cursor fade out after a few seconds without mouse movement.
struct NowPlayingView: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryModel.self) private var library
    @Environment(BrowseState.self) private var browse

    @State private var chromeVisible = true
    @State private var lastActivity = Date()
    @State private var isFullScreen = BrowseState.mainWindow?.styleMask.contains(.fullScreen) ?? false

    var body: some View {
        GeometryReader { geo in
            let horizontal = geo.size.width > geo.size.height * 1.3
            ZStack {
                Backdrop(key: player.current?.artworkKey)

                if let track = player.current {
                    Group {
                        if horizontal {
                            HStack(spacing: max(40, geo.size.width * 0.05)) {
                                cover(track, size: min(geo.size.height - 190, geo.size.width * 0.5))
                                details(track, alignment: .leading)
                                    .frame(width: min(440, geo.size.width * 0.34), alignment: .leading)
                            }
                        } else {
                            VStack(spacing: 34) {
                                cover(track, size: max(200, min(geo.size.width - 140, geo.size.height - 360)))
                                details(track, alignment: .center)
                                    .frame(width: min(520, geo.size.width - 80))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 20)
                } else {
                    Text("Nothing playing")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }

                topBar
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .contentShape(Rectangle())
        .task {
            // Fade the controls (and hide the cursor) after 3 s without the mouse moving.
            var lastMouse = NSEvent.mouseLocation
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                let mouse = NSEvent.mouseLocation
                if mouse != lastMouse {
                    lastMouse = mouse
                    wake()
                } else if chromeVisible, Date().timeIntervalSince(lastActivity) > 3 {
                    withAnimation(.easeInOut(duration: 0.6)) { chromeVisible = false }
                    NSCursor.setHiddenUntilMouseMoves(true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
    }

    private func wake() {
        lastActivity = Date()
        if !chromeVisible { withAnimation(.easeOut(duration: 0.2)) { chromeVisible = true } }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 6) {
            Spacer()
            IconButton(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                       size: 14, help: isFullScreen ? "Exit Full Screen (F)" : "Full Screen (F)") {
                browse.toggleWindowFullScreen()
            }
            IconButton(systemName: "chevron.down", size: 16, help: "Close (Esc)") {
                browse.dismissNowPlaying()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, isFullScreen ? 18 : 12)
        .opacity(chromeVisible ? 1 : 0)
    }

    private func cover(_ track: Track, size: CGFloat) -> some View {
        CoverView(key: track.artworkKey, size: .large, cornerRadius: 10)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.55), radius: 40, y: 22)
            .id(track.artworkKey ?? track.path) // cross-fade when the album changes
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.5), value: track.artworkKey)
            .onTapGesture(count: 2) { browse.toggleWindowFullScreen() }
            .help("Double-click for full screen")
    }

    private func details(_ track: Track, alignment: HorizontalAlignment) -> some View {
        let textAlignment: TextAlignment = alignment == .center ? .center : .leading
        let frameAlignment: Alignment = alignment == .center ? .center : .leading
        return VStack(alignment: alignment, spacing: 0) {
            Text(track.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(textAlignment)
                .lineLimit(3)
            Text(track.artist)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text.opacity(0.8))
                .lineLimit(1)
                .padding(.top, 8)
            Button {
                if let album = library.album(for: track) {
                    browse.open(album)
                    browse.dismissNowPlaying()
                }
            } label: {
                Text(track.album + (track.year.map { "  ·  \($0)" } ?? ""))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Go to album")
            .padding(.top, 4)

            HStack(spacing: 8) {
                Circle()
                    .fill(player.output.isBitPerfect ? Theme.perfect : (player.output.active ? Theme.warning : Theme.tertiary))
                    .frame(width: 6, height: 6)
                Text("\(track.codec.displayName)  \(track.qualityLabel)")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(track.quality == .hiRes ? Theme.hiRes : Theme.secondary)
                if player.output.isBitPerfect {
                    Text("Bit-perfect")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.top, 14)

            VStack(spacing: 18) {
                NowPlayingPosition()
                NowPlayingTransport()
            }
            .padding(.top, 30)
            .opacity(chromeVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
}

private struct NowPlayingPosition: View {
    @Environment(PlayerController.self) private var player
    @State private var dragFraction: Double?

    var body: some View {
        let duration = player.duration
        let shown = dragFraction.map { $0 * duration } ?? player.position
        VStack(spacing: 4) {
            ThinSlider(value: duration > 0 ? player.position / duration : 0,
                       onDragChange: { dragFraction = $0 }) { f in
                player.seek(to: f * duration)
            }
            HStack {
                Text(Format.duration(shown))
                Spacer()
                Text("-" + Format.duration(max(0, duration - shown)))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.secondary)
        }
    }
}

private struct NowPlayingTransport: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        HStack(spacing: 0) {
            IconButton(systemName: "shuffle", size: 15, isActive: player.shuffle, help: "Shuffle") {
                player.toggleShuffle()
            }
            Spacer()
            IconButton(systemName: "backward.fill", size: 20, help: "Previous") { player.previous() }
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .offset(x: player.isPlaying ? 0 : 2)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Color.white.opacity(0.95)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            IconButton(systemName: "forward.fill", size: 20, help: "Next") { player.next() }
            Spacer()
            IconButton(systemName: player.repeatMode == .one ? "repeat.1" : "repeat", size: 15,
                       isActive: player.repeatMode != .off, help: "Repeat") {
                player.cycleRepeat()
            }
        }
    }
}

/// The current artwork, heavily blurred and darkened, filling the window.
struct Backdrop: View {
    let key: String?
    @State private var image: NSImage?

    var body: some View {
        // The image lives in an overlay so its fill size never changes the layout size.
        Theme.background
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 90, opaque: true)
                        .saturation(1.25)
                        .opacity(0.55)
                        .transition(.opacity)
                }
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
        .ignoresSafeArea()
        .task(id: key) {
            guard let key else { image = nil; return }
            let loaded = await ImageCache.shared.load(key, .thumb)
            withAnimation(.easeInOut(duration: 0.8)) { image = loaded }
        }
    }
}

/// Big view of an album cover (for albums that aren't playing). Click or Esc to close.
struct CoverViewer: View {
    let key: String
    @Environment(BrowseState.self) private var browse

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Backdrop(key: key)
                CoverView(key: key, size: .large, cornerRadius: 10)
                    .frame(width: min(geo.size.width, geo.size.height) - 120,
                           height: min(geo.size.width, geo.size.height) - 120)
                    .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { browse.closeCover() }
    }
}
