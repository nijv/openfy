import OpenfyCore
import SwiftUI

/// Section title, search field and filter chips.
struct BrowseHeader: View {
    let title: String
    let subtitle: String
    var showSort = false

    @Environment(LibraryModel.self) private var library
    @Environment(BrowseState.self) private var browse

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
                    .monospacedDigit()
                Spacer()
                SearchField()
            }
            FilterBar(showSort: showSort)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 18)
    }
}

struct SearchField: View {
    @Environment(BrowseState.self) private var browse
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var browse = browse
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            TextField("Search", text: $browse.filter.search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focused($focused)
                .onExitCommand {
                    browse.filter.search = ""
                    focused = false
                }
            if !browse.filter.search.isEmpty {
                Button {
                    browse.filter.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 240)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(focused ? Theme.selected : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(focused ? Color.white.opacity(0.18) : Theme.hairline, lineWidth: 1))
        .onChange(of: browse.searchFocusToken) { focused = true }
    }
}

struct FilterBar: View {
    var showSort: Bool
    @Environment(LibraryModel.self) private var library
    @Environment(BrowseState.self) private var browse

    var body: some View {
        // Narrow window: the chips scroll sideways instead of being squeezed.
        ViewThatFits(in: .horizontal) {
            row(flexible: true)
            ScrollView(.horizontal, showsIndicators: false) { row(flexible: false) }
        }
    }

    @ViewBuilder private func row(flexible: Bool) -> some View {
        @Bindable var browse = browse
        HStack(spacing: 8) {
            ForEach([QualityTier.hiRes, .cd, .lossy], id: \.self) { tier in
                Chip(title: tier.displayName, isOn: browse.filter.qualities.contains(tier),
                     tint: tier == .hiRes ? Theme.hiRes : nil) {
                    if browse.filter.qualities.contains(tier) {
                        browse.filter.qualities.remove(tier)
                    } else {
                        browse.filter.qualities.insert(tier)
                    }
                }
            }

            Rectangle().fill(Theme.hairline).frame(width: 1, height: 16).padding(.horizontal, 4)

            ChipMenu(title: formatTitle, isActive: !browse.filter.codecs.isEmpty) {
                ForEach(library.index.codecs, id: \.self) { codec in
                    Toggle(codec.displayName + (codec.isLossless ? "  ·  lossless" : ""), isOn: Binding(
                        get: { browse.filter.codecs.contains(codec) },
                        set: { on in
                            if on { browse.filter.codecs.insert(codec) } else { browse.filter.codecs.remove(codec) }
                        }
                    ))
                }
                if !browse.filter.codecs.isEmpty {
                    Divider()
                    Button("Any Format") { browse.filter.codecs = [] }
                }
            }

            ChipMenu(title: browse.filter.genre ?? "Genre", isActive: browse.filter.genre != nil) {
                Button("Any Genre") { browse.filter.genre = nil }
                Divider()
                ForEach(library.index.genres, id: \.self) { genre in
                    Toggle(genre, isOn: Binding(
                        get: { browse.filter.genre == genre },
                        set: { browse.filter.genre = $0 ? genre : nil }
                    ))
                }
            }
            .disabled(library.index.genres.isEmpty)

            ChipMenu(title: browse.filter.decade.map { "\($0)s" } ?? "Decade", isActive: browse.filter.decade != nil) {
                Button("Any Decade") { browse.filter.decade = nil }
                Divider()
                ForEach(library.index.decades, id: \.self) { decade in
                    Toggle("\(decade)s", isOn: Binding(
                        get: { browse.filter.decade == decade },
                        set: { browse.filter.decade = $0 ? decade : nil }
                    ))
                }
            }
            .disabled(library.index.decades.isEmpty)

            if browse.filter.hasFacets {
                Button("Clear") {
                    let search = browse.filter.search
                    browse.filter = LibraryFilter()
                    browse.filter.search = search
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 4)
            }

            if flexible { Spacer() }

            if showSort {
                ChipMenu(title: "Sort: \(browse.albumSort.displayName)", isActive: false) {
                    Picker("Sort", selection: $browse.albumSort) {
                        ForEach(AlbumSort.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
        }
    }

    var formatTitle: String {
        let codecs = browse.filter.codecs.sorted()
        if codecs.isEmpty { return "Format" }
        if codecs.count <= 2 { return codecs.map(\.displayName).joined(separator: ", ") }
        return "\(codecs.count) formats"
    }
}

struct NoResultsView: View {
    @Environment(BrowseState.self) private var browse

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.tertiary)
            Text("Nothing matches these filters")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Button("Clear filters") { browse.filter = LibraryFilter() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
