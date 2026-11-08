import AppKit
import SwiftUI

/// Player bar button: phone icon with a dot while the remote is on.
struct RemoteButton: View {
    @Environment(RemoteControl.self) private var remote
    /// `devRemotePopover`: open on launch for development screenshots.
    @State private var showing = UserDefaults.standard.bool(forKey: "devRemotePopover")

    var body: some View {
        IconButton(systemName: "iphone", size: 13, isActive: showing || remote.enabled, help: "Phone Remote") {
            showing.toggle()
        }
        .popover(isPresented: $showing, arrowEdge: .top) {
            RemoteView()
                .environment(remote)
        }
    }
}

struct RemoteView: View {
    @Environment(RemoteControl.self) private var remote
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Phone Remote").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                Toggle("", isOn: Binding(get: { remote.enabled }, set: { remote.enabled = $0 }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            Text("See what’s playing and control it from your iPhone. The music keeps playing from this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = remote.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if remote.enabled, let link = remote.link {
                connected(link)
            } else if remote.enabled {
                ProgressView().controlSize(.small)
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func connected(_ link: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let qr = RemoteControl.qrCode(for: link) {
                Image(nsImage: qr)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 128, height: 128)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white))
            }
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Point the iPhone camera at the code and open the link.")
                step(2, "In Safari tap Share → Add to Home Screen.")
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(link)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.text.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            }
            if let ip = remote.ipLink {
                Text("Won’t open? Try \(ip)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        HStack {
            Text("Your phone needs to be on the same Wi-Fi.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiary)
            Spacer()
            Button("New Link") { remote.resetLink() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .help("Makes a new code. Phones using the old one stop working until they scan it.")
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(n)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.background)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.secondary))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
