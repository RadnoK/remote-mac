import RemoteMacCore
import SwiftUI

struct HostRow: View {
    let entry: HostEntry
    let store: HostStore
    @State private var isHovered = false

    /// Fixed-width slot for the hover-revealed SSH button. Reserving the
    /// space even while hidden keeps the trailing edge of every row aligned
    /// instead of the text reflowing sideways as the button pops in and out
    /// — the same ragged-edge fix RouterMenu applies to its row glyphs.
    private static let trailingActionWidth: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: entry.status, l10n: store.l10n)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.host.displayName)
                    .lineLimit(1)
                Text(hostSubtitle(for: entry, l10n: store.l10n))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                store.openSSH(to: entry.host)
            } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(.borderless)
            .help(store.l10n(.rowOpenSSH))
            .opacity(isHovered ? 1 : 0)
            .frame(width: Self.trailingActionWidth)
            .allowsHitTesting(isHovered)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(isHovered ? Color.secondary.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture { store.connect(to: entry.host) }
        .contextMenu {
            Button(store.l10n(.rowConnect)) { store.connect(to: entry.host) }
            Button(store.l10n(.rowOpenSSH)) { store.openSSH(to: entry.host) }
            Button(store.l10n(.rowOpenFiles)) { store.openFiles(for: entry.host) }
            Divider()
            Button(store.l10n(.rowCopyAddress)) { store.copyAddress(of: entry.host) }
        }
    }
}
