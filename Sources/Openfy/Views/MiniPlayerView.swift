import AppKit
import OpenfyCore
import SwiftUI

/// The window shrunk to a small square: just the cover. Hovering shows the title,
/// play/pause, previous/next, a progress bar, and buttons to pin on top or expand.
struct MiniPlayerView: View {
    @Environment(PlayerController.self) private var player
    @Environment(WindowModel.self) private var windowModel
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Backdrop(key: player.current?.artworkKey)

                if let track = player.current {
                    CoverView(key: track.artworkKey, size: side > 260 ? .large : .thumb, cornerRadius: 0)
                        .frame(width: side, height: side)
                        .id(track.artworkKey ?? track.path)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.5), value: track.artworkKey)
                } else {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: side * 0.3, weight: .ultraLight))
                        .foregroundStyle(Theme.tertiary)
                }

                // Drag anywhere on the cover to move the window; double-click to expand; right-click for a menu.
                WindowDragArea(onDoubleClick: { windowModel.toggleMini() }, menu: contextMenu)

                controls(side: side)
                    .opacity(hovering || Self.devShowControls ? 1 : 0)
                    .allowsHitTesting(hovering)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onHover { inside in
            withAnimation(.easeOut(duration: inside ? 0.15 : 0.3)) { hovering = inside }
            windowModel.setTrafficLightsVisible(inside)
        }
        .onAppear { windowModel.setTrafficLightsVisible(false) }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false // respect isEnabled (nothing playing)
        let hasTrack = player.current != nil
        menu.addItem(ClosureMenuItem(player.isPlaying ? "Pause" : "Play", enabled: hasTrack) { player.togglePlayPause() })
        menu.addItem(ClosureMenuItem("Next", enabled: hasTrack) { player.next() })
        menu.addItem(ClosureMenuItem("Previous", enabled: hasTrack) { player.previous() })
        menu.addItem(.separator())
        let onTop = ClosureMenuItem("Keep on Top") { windowModel.keepMiniOnTop.toggle() }
        onTop.state = windowModel.keepMiniOnTop ? .on : .off
        menu.addItem(onTop)
        menu.addItem(ClosureMenuItem("Show Full Window") { windowModel.toggleMini() })
        return menu
    }

    /// Development screenshots: show the hover controls without a mouse.
    private static let devShowControls = UserDefaults.standard.bool(forKey: "devMiniControls")

    private func controls(side: CGFloat) -> some View {
        let scale = min(max(side / 320, 0.7), 1.4)
        return ZStack {
            // Dim the whole cover (readable on bright artwork), darker at the edges.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.6), location: 0),
                .init(color: .black.opacity(0.35), location: 0.25),
                .init(color: .black.opacity(0.4), location: 0.6),
                .init(color: .black.opacity(0.85), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    Spacer()
                    MiniButton(systemName: windowModel.keepMiniOnTop ? "pin.fill" : "pin", size: 11,
                               help: windowModel.keepMiniOnTop ? "Stop keeping on top" : "Keep on top") {
                        windowModel.keepMiniOnTop.toggle()
                    }
                    MiniButton(systemName: "arrow.up.left.and.arrow.down.right", size: 11, help: "Full window (⌥⌘M)") {
                        windowModel.toggleMini()
                    }
                }
                .padding(.top, 6)
                .padding(.horizontal, 6)

                Spacer(minLength: 0)

                HStack(spacing: 22 * scale) {
                    MiniButton(systemName: "backward.fill", size: 18 * scale, help: "Previous") { player.previous() }
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20 * scale, weight: .bold))
                            .foregroundStyle(.black)
                            .offset(x: player.isPlaying ? 0 : 2 * scale)
                            .frame(width: 50 * scale, height: 50 * scale)
                            .background(Circle().fill(Color.white.opacity(0.95)))
                            .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(player.current == nil)
                    MiniButton(systemName: "forward.fill", size: 18 * scale, help: "Next") { player.next() }
                }

                Spacer(minLength: 0)

                if let track = player.current {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 13 * min(scale, 1.15), weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 11 * min(scale, 1.15)))
                            .foregroundStyle(Theme.text.opacity(0.7))
                            .lineLimit(1)
                        MiniPosition()
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
    }
}

/// White icon button that stays visible on any cover.
private struct MiniButton: View {
    let systemName: String
    var size: CGFloat = 14
    var help = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                .frame(width: size + 18, height: size + 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Isolated so only the bar redraws as the position ticks.
private struct MiniPosition: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        let duration = player.duration
        ThinSlider(value: duration > 0 ? player.position / duration : 0) { f in
            player.seek(to: f * duration)
        }
    }
}

/// A transparent area that moves the window when dragged (the mini player has no title bar
/// to grab) and reports double-clicks.
struct WindowDragArea: NSViewRepresentable {
    var onDoubleClick: () -> Void
    var menu: (() -> NSMenu)? = nil

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.onDoubleClick = onDoubleClick
        view.menuProvider = menu
    }

    final class DragView: NSView {
        var onDoubleClick: (() -> Void)?
        var menuProvider: (() -> NSMenu)?
        override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
