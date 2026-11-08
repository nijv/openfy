import AppKit
import CoreImage
import Foundation
import Observation
import OpenfyCore
import SystemConfiguration

/// Phone remote: serves a small web app on the local network so an iPhone (Safari, or added to
/// the Home Screen) can see what's playing and control it. The audio never leaves the Mac.
///
/// Every data/control request needs the secret token from the link Openfy shows, so other
/// devices on the Wi-Fi can't use it unless you share the link.
@Observable
final class RemoteControl {
    var enabled: Bool = UserDefaults.standard.bool(forKey: "remote.enabled") {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: "remote.enabled")
            enabled ? start() : stop()
        }
    }
    private(set) var port: UInt16?
    private(set) var errorMessage: String?
    private(set) var token: String

    @ObservationIgnored private let server = HTTPServer()
    @ObservationIgnored private let player: PlayerController
    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private lazy var iconPNG: Data? = Self.renderIcon()

    static let defaultPort: UInt16 = 8517

    init(player: PlayerController, library: LibraryModel) {
        self.player = player
        self.library = library
        if let saved = UserDefaults.standard.string(forKey: "remote.token"), saved.count >= 16 {
            token = saved
        } else {
            token = Self.newToken()
            UserDefaults.standard.set(token, forKey: "remote.token")
        }
        server.handler = { [weak self] request in self?.handle(request) ?? .notFound }
        server.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready(let port):
                self.port = port
                errorMessage = nil
            case .failed(let message):
                port = nil
                errorMessage = "Couldn't start the remote: \(message)"
            }
        }
    }

    func startIfEnabled() {
        if enabled { start() }
    }

    func stop() {
        server.stop()
        port = nil
    }

    private func start() {
        errorMessage = nil
        let saved = UserDefaults.standard.integer(forKey: "remote.port")
        server.start(port: (1024...65_000).contains(saved) ? UInt16(saved) : Self.defaultPort)
    }

    /// Makes a new link; phones with the old one stop working until they scan the new one.
    func resetLink() {
        token = Self.newToken()
        UserDefaults.standard.set(token, forKey: "remote.token")
    }

    // MARK: Links

    /// "http://Your-MacBook-Air.local:8517/?t=…" — the .local name survives the Mac's IP changing.
    var link: String? {
        port.map { "http://\(Self.hostName):\($0)/?t=\(token)" }
    }

    /// Same, by IP address, for networks where .local names don't resolve.
    var ipLink: String? {
        guard let port, let ip = Self.ipAddress() else { return nil }
        return "http://\(ip):\(port)/?t=\(token)"
    }

    static var hostName: String {
        if let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty { return "\(name).local" }
        return ProcessInfo.processInfo.hostName
    }

    /// The Mac's IPv4 address on Wi-Fi/Ethernet.
    static func ipAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var candidates: [(name: String, ip: String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  ifa.ifa_flags & UInt32(IFF_UP) != 0, ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue } // skip VPN tunnels, bridges, etc.
            candidates.append((name, String(cString: host)))
        }
        return candidates.sorted { $0.name < $1.name }.first?.ip
    }

    /// QR code for the link, crisp at any size (draw with interpolation off).
    static func qrCode(for text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }

    private static func newToken() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    // MARK: Requests

    private func handle(_ r: HTTPServer.Request) -> HTTPServer.Response {
        // The page itself holds no data; everything below needs the token.
        switch r.path {
        case "/", "/index.html":
            return HTTPServer.Response(contentType: "text/html; charset=utf-8", body: Data(RemotePage.html.utf8),
                                       cacheControl: "no-cache")
        case "/manifest.webmanifest":
            return HTTPServer.Response(contentType: "application/manifest+json", body: Data(RemotePage.manifest.utf8),
                                       cacheControl: "no-cache")
        case "/icon.png":
            guard let iconPNG else { return .notFound }
            return HTTPServer.Response(contentType: "image/png", body: iconPNG, cacheControl: "max-age=86400")
        default:
            break
        }

        guard r.query["t"] == token else { return .text("Unauthorized", status: 401) }

        if r.path.hasPrefix("/art/") { return artwork(String(r.path.dropFirst(5)), size: r.query["s"]) }

        switch (r.method, r.path) {
        case ("GET", "/api/state"):
            return .json(state())
        case ("GET", "/api/albums"):
            return .json(albums())
        case ("GET", "/api/album"):
            guard let id = r.query["id"], let album = library.index.albumsByID[id] else { return .notFound }
            return .json(albumDetail(album))
        case ("POST", let path) where path.hasPrefix("/api/"):
            guard perform(String(path.dropFirst(5)), r.query) else { return .notFound }
            return .json(state())
        default:
            return .notFound
        }
    }

    private func perform(_ command: String, _ q: [String: String]) -> Bool {
        let value = q["v"].flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
        switch command {
        case "toggle": player.togglePlayPause()
        case "next": player.next()
        case "prev": player.previous()
        case "shuffle": player.toggleShuffle()
        case "repeat": player.cycleRepeat()
        case "seek":
            if let value { player.seek(to: min(max(0, value), player.duration)) }
        case "volume":
            if let value { setVolume(value) }
        case "jump":
            if let value { player.jump(to: Int(value.rounded())) }
        case "album":
            guard let id = q["id"], let album = library.index.albumsByID[id], !album.tracks.isEmpty else { return true }
            let start = q["start"].flatMap(Int.init).map { min(max($0, 0), album.tracks.count - 1) } ?? 0
            player.play(album.tracks, startAt: start, shuffled: q["shuffle"] == "1")
        default:
            return false
        }
        return true
    }

    // MARK: Volume

    /// The phone controls the Mac's output volume (keeps playback bit-perfect), falling back to
    /// Openfy's own volume on outputs without a volume control.
    private var macVolume: Float? {
        AudioDevice.defaultOutput().flatMap { AudioDevice.volume($0) }
    }

    private func setVolume(_ v: Double) {
        let v = min(max(v, 0), 1)
        if let device = AudioDevice.defaultOutput(), AudioDevice.setVolume(device, Float(v)) { return }
        player.volume = v
    }

    // MARK: JSON

    private func state() -> [String: Any] {
        var s: [String: Any] = [
            "playing": player.isPlaying,
            "position": player.position,
            "shuffle": player.shuffle,
            "repeat": player.repeatMode.rawValue,
            "device": player.output.deviceName,
            "bitPerfect": player.output.active && player.output.isBitPerfect,
        ]
        if let mac = macVolume {
            s["volume"] = Double(mac)
            s["volumeKind"] = "mac"
        } else {
            s["volume"] = player.volume
            s["volumeKind"] = "app"
        }
        if let track = player.current {
            var t: [String: Any] = [
                "title": track.title,
                "artist": track.artist,
                "album": track.album,
                "duration": track.duration,
                "quality": "\(track.codec.displayName) · \(track.qualityLabel)",
                "hiRes": track.quality == .hiRes,
            ]
            if let year = track.year { t["year"] = year }
            if let art = track.artworkKey { t["art"] = art }
            if let album = library.album(for: track) {
                t["albumID"] = album.id
                if let i = album.tracks.firstIndex(where: { $0.path == track.path }) { t["albumIndex"] = i }
            }
            s["track"] = t
        }
        if let index = player.index {
            s["index"] = index
            let end = min(player.queue.count, index + 101)
            s["upNext"] = (index + 1 < end ? Array(index + 1..<end) : []).map { i -> [String: Any] in
                let track = player.queue[i]
                var row: [String: Any] = ["i": i, "title": track.title, "artist": track.artist, "duration": track.duration]
                if let art = track.artworkKey { row["art"] = art }
                return row
            }
        }
        return s
    }

    private func albums() -> [[String: Any]] {
        library.index.albums
            .sorted {
                let a = $0.artist.localizedCaseInsensitiveCompare($1.artist)
                if a != .orderedSame { return a == .orderedAscending }
                if $0.year != $1.year { return ($0.year ?? 0) < ($1.year ?? 0) }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .map { album in
                var a: [String: Any] = ["id": album.id, "title": album.title, "artist": album.artist,
                                        "tracks": album.tracks.count]
                if let year = album.year { a["year"] = year }
                if let art = album.artworkKey { a["art"] = art }
                return a
            }
    }

    private func albumDetail(_ album: Album) -> [String: Any] {
        var a: [String: Any] = [
            "id": album.id, "title": album.title, "artist": album.artist, "duration": album.duration,
            "quality": album.qualitySummary, "discCount": album.discCount,
            "tracks": album.tracks.map { track -> [String: Any] in
                var t: [String: Any] = ["title": track.title, "duration": track.duration]
                if let n = track.trackNumber { t["n"] = n }
                if let d = track.discNumber { t["disc"] = d }
                // Only show a track's artist when it differs from the album's (features, compilations).
                if track.artist.caseInsensitiveCompare(album.artist) != .orderedSame { t["artist"] = track.artist }
                return t
            },
        ]
        if let year = album.year { a["year"] = year }
        if let art = album.artworkKey { a["art"] = art }
        return a
    }

    // MARK: Files

    private func artwork(_ key: String, size: String?) -> HTTPServer.Response {
        // Keys are hex digests; anything else is refused (no path tricks).
        guard !key.isEmpty, key.count <= 64, key.allSatisfy(\.isHexDigit) else { return .notFound }
        let url = library.artwork.url(for: key, size: size == "t" ? .thumb : .large)
        guard let data = try? Data(contentsOf: url) else { return .notFound }
        // Covers are content-addressed, so a key's image never changes.
        return HTTPServer.Response(contentType: "image/jpeg", body: data, cacheControl: "max-age=31536000, immutable")
    }

    /// Home Screen icon: the app icon's squircle body (iOS rounds the corners itself).
    private static func renderIcon() -> Data? {
        let source = NSApp.applicationIconImage ?? NSImage()
        let px = 180
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.06, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: px, height: px).fill()
        // macOS icon grid: the body is 824/1024 of the canvas, inset 100.
        let scale = CGFloat(px) / (824.0 / 1024.0)
        let inset = scale * 100.0 / 1024.0
        source.draw(in: NSRect(x: -inset, y: -inset, width: scale, height: scale),
                    from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
