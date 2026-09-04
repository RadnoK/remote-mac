import RemoteMacCore
import SwiftUI

struct HostRow: View {
    let entry: HostEntry
    let store: HostStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: entry.status)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.host.displayName)
                    .lineLimit(1)
                Text(hostSubtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isHovered {
                Button {
                    store.openSSH(to: entry.host)
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help("Otwórz SSH")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(isHovered ? Color.secondary.opacity(0.15) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .onTapGesture { store.connect(to: entry.host) }
        .contextMenu {
            Button("Połącz (Screen Sharing)") { store.connect(to: entry.host) }
            Button("Otwórz SSH") { store.openSSH(to: entry.host) }
            Button("Otwórz pliki (SMB)") { store.openFiles(for: entry.host) }
            Divider()
            Button("Kopiuj adres IP") { store.copyAddress(of: entry.host) }
        }
    }
}
