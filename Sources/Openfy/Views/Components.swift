import AppKit
import OpenfyCore
import SwiftUI

enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.047)
    static let sidebar = Color(red: 0.055, green: 0.055, blue: 0.06)
    static let surface = Color.white.opacity(0.045)
    static let hover = Color.white.opacity(0.07)
    static let selected = Color.white.opacity(0.1)
    static let hairline = Color.white.opacity(0.07)
    static let text = Color(white: 0.94)
    static let secondary = Color(white: 0.58)
    static let tertiary = Color(white: 0.38)
    static let placeholder = Color(white: 0.1)
    static let perfect = Color(red: 0.45, green: 0.86, blue: 0.58)
    static let warning = Color(red: 0.95, green: 0.72, blue: 0.38)
    static let hiRes = Color(red: 0.9, green: 0.77, blue: 0.5)
}

// MARK: - Artwork

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()
    var store: ArtworkStore?

    init() { cache.countLimit = 400 }

    func cached(_ key: String?, _ size: ArtworkStore.Size) -> NSImage? {
        guard let key else { return nil }
        return cache.object(forKey: "\(key)-\(size.rawValue)" as NSString)
    }

    func load(_ key: String, _ size: ArtworkStore.Size) async -> NSImage? {
        if let hit = cached(key, size) { return hit }
        guard let url = store?.url(for: key, size: size) else { return nil }
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let img = NSImage(contentsOf: url) else { return nil }
            // Force decode off the main thread so scrolling stays smooth.
            _ = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            return img
        }.value
        if let image { cache.setObject(image, forKey: "\(key)-\(size.rawValue)" as NSString) }
        return image
    }

    func loadSync(_ key: String, _ size: ArtworkStore.Size) -> NSImage? {
        if let hit = cached(key, size) { return hit }
        guard let url = store?.url(for: key, size: size), let img = NSImage(contentsOf: url) else { return nil }
        cache.setObject(img, forKey: "\(key)-\(size.rawValue)" as NSString)
        return img
    }
}

struct CoverView: View {
    let key: String?
    var size: ArtworkStore.Size = .thumb
    var cornerRadius: CGFloat = 6

    @State private var image: NSImage?

    init(key: String?, size: ArtworkStore.Size = .thumb, cornerRadius: CGFloat = 6) {
        self.key = key
        self.size = size
        self.cornerRadius = cornerRadius
        _image = State(initialValue: ImageCache.shared.cached(key, size))
    }

    var body: some View {
        Theme.placeholder
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    GeometryReader { geo in
                        Image(systemName: "opticaldisc")
                            .font(.system(size: geo.size.width * 0.28, weight: .ultraLight))
                            .foregroundStyle(Theme.tertiary.opacity(0.6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .task(id: key) {
                guard let key else { image = nil; return }
                if let loaded = await ImageCache.shared.load(key, size) {
                    withAnimation(.easeOut(duration: 0.15)) { image = loaded }
                }
            }
    }
}

// MARK: - Controls

struct Chip: View {
    let title: String
    var isOn: Bool
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? Color.black : (tint ?? Theme.secondary))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(isOn ? (tint ?? Theme.text) : (hovering ? Theme.hover : Theme.surface)))
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A menu that looks like a chip.
struct ChipMenu<Content: View>: View {
    let title: String
    var isActive: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isActive ? Theme.text : Theme.secondary)
        .tint(isActive ? Theme.text : Theme.secondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Capsule().fill(isActive ? Theme.selected : Theme.surface))
        .overlay(Capsule().strokeBorder(isActive ? Color.white.opacity(0.25) : Theme.hairline, lineWidth: 1))
    }
}

struct IconButton: View {
    let systemName: String
    var size: CGFloat = 14
    var isActive = false
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isActive ? Theme.text : (hovering ? Theme.text : Theme.secondary))
                .frame(width: size + 16, height: size + 16)
                .overlay(alignment: .bottom) {
                    if isActive {
                        Circle().fill(Theme.text).frame(width: 3, height: 3).offset(y: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct PillButton: View {
    let title: String
    let systemName: String
    var primary = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemName).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(primary ? Color.black : Theme.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Capsule().fill(primary ? Color.white.opacity(hovering ? 1 : 0.92) : (hovering ? Theme.selected : Theme.surface)))
            .overlay(Capsule().strokeBorder(primary ? Color.clear : Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Thin horizontal slider used for seeking and volume.
struct ThinSlider: View {
    var value: Double              // 0...1
    var live = false               // report every change (volume) vs. only on release (seek)
    var onDragChange: ((Double?) -> Void)? = nil
    let onCommit: (Double) -> Void

    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let fraction = min(max(dragFraction ?? value, 0), 1)
            let active = hovering || dragFraction != nil
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.13))
                    .frame(height: active ? 5 : 3)
                Capsule().fill(Color.white.opacity(active ? 0.95 : 0.7))
                    .frame(width: max(0, geo.size.width * fraction), height: active ? 5 : 3)
                Circle()
                    .fill(Color.white)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: geo.size.width * fraction - 5.5)
                    .opacity(active ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                        dragFraction = f
                        onDragChange?(f)
                        if live { onCommit(f) }
                    }
                    .onEnded { g in
                        let f = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                        onCommit(f)
                        dragFraction = nil
                        onDragChange?(nil)
                    }
            )
            .animation(.easeOut(duration: 0.12), value: active)
        }
        .frame(height: 16)
        .onHover { hovering = $0 }
    }
}

// MARK: - Quality

struct QualityTag: View {
    let text: String
    let tier: QualityTier
    var large = false

    var body: some View {
        Text(text)
            .font(.system(size: large ? 11 : 9.5, weight: .semibold, design: .rounded))
            .tracking(0.3)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, large ? 8 : 5)
            .padding(.vertical, large ? 3 : 1.5)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(color.opacity(0.45), lineWidth: 1)
            )
    }

    var color: Color {
        switch tier {
        case .hiRes: Theme.hiRes
        case .cd: Theme.secondary
        case .lossy: Theme.tertiary
        }
    }
}

extension View {
    func hoverHighlight(_ hovering: Bool, selected: Bool = false, radius: CGFloat = 6) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(selected ? Theme.selected : (hovering ? Theme.hover : Color.clear))
        )
    }
}

func revealInFinder(_ tracks: [Track]) {
    NSWorkspace.shared.activateFileViewerSelecting(tracks.prefix(20).map(\.url))
}
