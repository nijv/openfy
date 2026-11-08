import AppKit
import Observation

/// Window sizing: below a threshold the main window becomes a mini player (just the cover, with
/// controls on hover). Letting go of a resize in that range snaps the window to a square, and it
/// keeps its square shape until you drag it big again.
@Observable
final class WindowModel {
    /// The content is shown as the mini player.
    private(set) var isMini = false
    /// Keep the mini player above other windows.
    var keepMiniOnTop: Bool = UserDefaults.standard.bool(forKey: "miniKeepOnTop") {
        didSet {
            UserDefaults.standard.set(keepMiniOnTop, forKey: "miniKeepOnTop")
            applyWindowState()
        }
    }

    /// Below either dimension the full layout no longer fits, so the mini player takes over.
    static let fullLayoutMinimum = CGSize(width: 720, height: 460)
    static let miniMinimumSide: CGFloat = 200
    static let miniDefaultSide: CGFloat = 320
    /// A mini player snaps to at most this size (bigger squares stay the full layout).
    static let miniMaximumSide: CGFloat = 640

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var frameBeforeResize: NSRect?

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willStartLiveResizeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, window === BrowseState.mainWindow else { return }
            frameBeforeResize = isMini ? nil : window.frame
        })
        observers.append(center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, window === BrowseState.mainWindow else { return }
            // Measure the window itself: the view's notion of "mini" can lag a frame behind.
            if Self.isMiniSize(window.contentView?.bounds.size ?? window.frame.size) {
                // Dragged down into mini range: remember the big frame to come back to, then square up.
                if let frameBeforeResize { saveFrame(frameBeforeResize, key: "window.fullFrame") }
                snapToSquare(window)
            }
            frameBeforeResize = nil
        })
    }

    static func isMiniSize(_ size: CGSize) -> Bool {
        size.width < fullLayoutMinimum.width || size.height < fullLayoutMinimum.height
    }

    /// Called by the root view whenever the content size changes.
    func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let mini = Self.isMiniSize(size)
        guard mini != isMini else { return }
        isMini = mini
        applyWindowState()
    }

    // MARK: Switching

    /// ⌥⌘M: shrink to the mini player, or go back to the full window.
    func toggleMini() {
        guard let window = BrowseState.mainWindow, !window.styleMask.contains(.fullScreen) else { return }
        if isMini {
            saveFrame(window.frame, key: "window.miniFrame")
            window.contentResizeIncrements = NSSize(width: 1, height: 1) // drops the square lock
            let target = savedFrame("window.fullFrame").map { fit($0, on: window) }
                ?? centered(NSSize(width: 1240, height: 800), on: window)
            window.setFrame(target, display: true, animate: true)
        } else {
            saveFrame(window.frame, key: "window.fullFrame")
            let target: NSRect
            if let mini = savedFrame("window.miniFrame") {
                target = fit(mini, on: window)
            } else {
                // Default: a square at the top-right corner of where the big window was.
                let side = Self.miniDefaultSide
                target = fit(NSRect(x: window.frame.maxX - side - 24, y: window.frame.maxY - side - 24,
                                    width: side, height: side), on: window)
            }
            window.setFrame(target, display: true, animate: true)
            window.contentAspectRatio = NSSize(width: 1, height: 1)
        }
    }

    private func snapToSquare(_ window: NSWindow) {
        let frame = window.frame
        let side = min(max(min(frame.width, frame.height), Self.miniMinimumSide), Self.miniMaximumSide - 1)
        // Keep the top-left corner where it is.
        let square = NSRect(x: frame.minX, y: frame.maxY - side, width: side, height: side)
        window.contentAspectRatio = NSSize(width: 1, height: 1)
        if square != frame { window.setFrame(fit(square, on: window), display: true, animate: true) }
    }

    // MARK: Window chrome

    /// Floating level, square lock, traffic lights and full-screen ability follow the mode.
    func applyWindowState() {
        guard let window = BrowseState.mainWindow else { return }
        if isMini {
            window.level = keepMiniOnTop ? .floating : .normal
            if !window.inLiveResize { window.contentAspectRatio = NSSize(width: 1, height: 1) }
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            setTrafficLightsVisible(false)
        } else {
            window.level = .normal
            window.contentResizeIncrements = NSSize(width: 1, height: 1)
            window.collectionBehavior.remove(.fullScreenNone)
            window.collectionBehavior.insert(.fullScreenPrimary)
            setTrafficLightsVisible(true)
        }
    }

    /// In the mini player the close/minimise/zoom buttons only show while the mouse is over it.
    func setTrafficLightsVisible(_ visible: Bool) {
        guard let window = BrowseState.mainWindow else { return }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = !visible
        }
    }

    // MARK: Frames

    private func saveFrame(_ frame: NSRect, key: String) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: key)
    }

    private func savedFrame(_ key: String) -> NSRect? {
        guard let s = UserDefaults.standard.string(forKey: key) else { return nil }
        let r = NSRectFromString(s)
        return r.width > 0 && r.height > 0 ? r : nil
    }

    /// Keeps a frame on the window's screen.
    private func fit(_ frame: NSRect, on window: NSWindow) -> NSRect {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return frame }
        var r = frame
        r.size.width = min(r.width, visible.width)
        r.size.height = min(r.height, visible.height)
        r.origin.x = min(max(r.minX, visible.minX), visible.maxX - r.width)
        r.origin.y = min(max(r.minY, visible.minY), visible.maxY - r.height)
        return r
    }

    private func centered(_ size: NSSize, on window: NSWindow) -> NSRect {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return NSRect(origin: window.frame.origin, size: size)
        }
        return fit(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                          width: size.width, height: size.height), on: window)
    }
}
