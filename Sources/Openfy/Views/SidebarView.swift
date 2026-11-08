import OpenfyCore
import SwiftUI

struct SidebarView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(BrowseState.self) private var browse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("openfy")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .padding(.leading, 22)
                .padding(.top, 48)
                .padding(.bottom, 22)

            VStack(spacing: 2) {
                ForEach(Section.allCases) { section in
                    SidebarRow(title: section.title, icon: section.icon, count: count(section),
                               selected: browse.section == section && browse.openAlbumID == nil) {
                        browse.section = section
                        browse.openAlbumID = nil
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            if !library.tracks.isEmpty {
                LibraryStats()
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
            }

            FoldersSection()
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
        .focusEffectDisabled()
    }

    func count(_ section: Section) -> Int {
        switch section {
        case .albums: library.index.albums.count
        case .artists: library.index.artists.count
        case .songs: library.tracks.count
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let icon: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .hoverHighlight(hovering, selected: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct LibraryStats: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        let albums = library.index.albums
        let hiRes = albums.filter { $0.quality == .hiRes }.count
        let cd = albums.filter { $0.quality == .cd }.count
        let lossy = albums.count - hiRes - cd
        VStack(alignment: .leading, spacing: 8) {
            Text("LIBRARY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.tertiary)
            QualityBar(hiRes: hiRes, cd: cd, lossy: lossy)
            VStack(alignment: .leading, spacing: 3) {
                stat(Theme.hiRes, "Hi-Res", hiRes)
                stat(Theme.secondary, "CD Quality", cd)
                if lossy > 0 { stat(Theme.tertiary, "Lossy", lossy) }
            }
            Text(Format.longDuration(library.totalDuration) + " of music")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
                .padding(.top, 2)
        }
    }

    func stat(_ color: Color, _ label: String, _ n: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).foregroundStyle(Theme.secondary)
            Spacer()
            Text("\(n)").foregroundStyle(Theme.tertiary).monospacedDigit()
        }
        .font(.system(size: 11))
    }
}

private struct QualityBar: View {
    let hiRes: Int, cd: Int, lossy: Int

    var body: some View {
        GeometryReader { geo in
            let total = max(1, hiRes + cd + lossy)
            HStack(spacing: 2) {
                if hiRes > 0 { Theme.hiRes.frame(width: geo.size.width * CGFloat(hiRes) / CGFloat(total)) }
                if cd > 0 { Theme.secondary.frame(width: geo.size.width * CGFloat(cd) / CGFloat(total)) }
                if lossy > 0 { Theme.tertiary.frame(maxWidth: .infinity) }
            }
            .clipShape(Capsule())
        }
        .frame(height: 3)
    }
}

private struct FoldersSection: View {
    @Environment(LibraryModel.self) private var library
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if library.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(progressText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if expanded {
                ForEach(library.folders, id: \.self) { folder in
                    FolderRow(folder: folder)
                }
            }

            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder").font(.system(size: 11))
                        Text(library.folders.count == 1 ? "1 folder" : "\(library.folders.count) folders")
                        Image(systemName: expanded ? "chevron.down" : "chevron.up").font(.system(size: 8, weight: .bold))
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(library.folders.isEmpty)

                Spacer()
                IconButton(systemName: "arrow.clockwise", size: 11, help: "Rescan library (⌘R)") { library.rescan() }
                    .disabled(library.isScanning || library.folders.isEmpty)
                IconButton(systemName: "plus", size: 12, help: "Add music folder (⌘O)") { library.chooseFolders() }
            }
        }
    }

    var progressText: String {
        guard let p = library.scanProgress, p.total > 0 else { return "Scanning…" }
        return "Reading \(p.processed) of \(p.total)"
    }
}

private struct FolderRow: View {
    let folder: URL
    @Environment(LibraryModel.self) private var library
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(folder.lastPathComponent)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folder.path)
            Spacer()
            if hovering {
                Button {
                    library.removeFolder(folder)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from library (files are not deleted)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .hoverHighlight(hovering)
        .onHover { hovering = $0 }
    }
}
