import AppKit
import OpenfyCore
import SwiftUI

/// Shared app state. Created once; the window and menus observe it.
enum AppState {
    static let library = LibraryModel()
    static let player = PlayerController()
    static let browse = BrowseState()
    static let window = WindowModel()
    static let remote = RemoteControl(player: player, library: library)
}

@main
struct OpenfyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let library = AppState.library
    private let player = AppState.player
    private let browse = AppState.browse
    private let windowModel = AppState.window
    private let remote = AppState.remote

    var body: some Scene {
        WindowGroup("Openfy") {
            RootView()
                .environment(library)
                .environment(player)
                .environment(browse)
                .environment(windowModel)
                .environment(remote)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Music Folder…") { library.chooseFolders() }
                    .keyboardShortcut("o")
                Button("Rescan Library") { library.rescan() }
                    .keyboardShortcut("r")
            }
            CommandGroup(after: .textEditing) {
                Button("Search Library") {
                    browse.openAlbumID = nil
                    browse.searchFocusToken += 1
                }
                .keyboardShortcut("f")
            }
            CommandGroup(before: .sidebar) {
                ForEach(Array(Section.allCases.enumerated()), id: \.element) { i, section in
                    Button(section.title) {
                        browse.section = section
                        browse.openAlbumID = nil
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
            }
            CommandGroup(before: .windowArrangement) {
                Button(windowModel.isMini ? "Show Full Window" : "Mini Player") { windowModel.toggleMini() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Toggle("Keep Mini Player on Top", isOn: Binding(get: { windowModel.keepMiniOnTop },
                                                                set: { windowModel.keepMiniOnTop = $0 }))
                Divider()
            }
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
                    .disabled(player.current == nil)
                Button("Next") { player.next() }
                    .keyboardShortcut(.rightArrow)
                Button("Previous") { player.previous() }
                    .keyboardShortcut(.leftArrow)
                Divider()
                Button("Skip Forward 10s") { player.skip(by: 10) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Skip Back 10s") { player.skip(by: -10) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Divider()
                Button("Volume Up") { player.changeVolume(by: 0.1) }
                    .keyboardShortcut(.upArrow)
                Button("Volume Down") { player.changeVolume(by: -0.1) }
                    .keyboardShortcut(.downArrow)
                Divider()
                Toggle("Shuffle", isOn: Binding(get: { player.shuffle }, set: { _ in player.toggleShuffle() }))
                Picker("Repeat", selection: Binding(get: { player.repeatMode }, set: { player.repeatMode = $0 })) {
                    Text("Off").tag(RepeatMode.off)
                    Text("All").tag(RepeatMode.all)
                    Text("One").tag(RepeatMode.one)
                }
                Divider()
                Toggle("Phone Remote", isOn: Binding(get: { remote.enabled }, set: { remote.enabled = $0 }))
                Divider()
                Button(browse.showNowPlaying ? "Close Now Playing" : "Now Playing") { browse.toggleNowPlaying() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(player.current == nil && !browse.showNowPlaying)
                Button("Go to Current Album") {
                    if let t = player.current, let album = library.album(for: t) { browse.open(album) }
                }
                .keyboardShortcut("l")
                .disabled(player.current == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.runIfRequested() { return }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let library = AppState.library
        let player = AppState.player
        ImageCache.shared.store = library.artwork
        player.nowPlaying.artworkProvider = { ImageCache.shared.loadSync($0, .large) }
        library.onFirstLoad = {
            player.restoreSession(using: library.tracksByPath)
        }
        library.onScanFinished = {
            DevLaunch.applyOnce(library: library, player: player, browse: AppState.browse)
        }
        if library.hasLoaded { player.restoreSession(using: library.tracksByPath) }
        AppState.remote.startIfEnabled()

        // Space toggles playback unless you're typing in a text field.
        // In Now Playing: Esc closes, F toggles full screen, ← → skip tracks.
        // In the mini player: ← → skip tracks.
        let browse = AppState.browse
        let windowModel = AppState.window
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard mods.isEmpty else { return event }
            if windowModel.isMini {
                switch event.keyCode {
                case 124: player.next(); return nil                          // →
                case 123: player.previous(); return nil                      // ←
                default: break
                }
            } else if browse.viewerArtworkKey != nil, event.keyCode == 53 || event.keyCode == 49 {
                browse.closeCover()
                return nil
            } else if browse.showNowPlaying {
                switch event.keyCode {
                case 53: browse.dismissNowPlaying(); return nil              // esc
                case 3: browse.toggleWindowFullScreen(); return nil          // f
                case 124: player.next(); return nil                          // →
                case 123: player.previous(); return nil                      // ←
                default: break
                }
            }
            guard event.keyCode == 49 else { return event } // space
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            player.togglePlayPause()
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep the music playing; click the Dock icon to bring the window back
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.player.shutdown()
    }
}
