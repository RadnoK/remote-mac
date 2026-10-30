import RemoteMacCore
import SwiftUI

struct HostRow: View {
    let entry: HostEntry
    let store: HostStore
    @State private var isHovered = false

    /// Fixed-width slot for each hover-revealed action button. Reserving the
    /// space even while hidden keeps the trailing edge of every row aligned
    /// instead of the text reflowing sideways as the buttons pop in and out
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

            // Read live rather than from `entry.host.monitorInput`, so the
            // button appears as soon as the input is set in Settings instead
            // of after the next refresh.
            if store.settings.monitorInputs[entry.host.id] != nil {
                MonitorSwitchButton(
                    help: store.l10n(.rowSwitchMonitor),
                    onSwitch: { await store.switchMonitor(to: entry.host) }
                )
                .opacity(isHovered ? 1 : 0)
                .frame(width: Self.trailingActionWidth)
                .allowsHitTesting(isHovered)
            }

            CopyIconButton(
                text: entry.host.ipv4,
                help: store.l10n(.rowCopyAddress),
                copiedHelp: store.l10n(.rowCopyAddressCopied),
                onCopy: { store.copyAddress(of: entry.host) }
            )
            .opacity(isHovered ? 1 : 0)
            .frame(width: Self.trailingActionWidth)
            .allowsHitTesting(isHovered)

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
            if store.settings.monitorInputs[entry.host.id] != nil {
                Button(store.l10n(.rowSwitchMonitor)) {
                    Task { await store.switchMonitor(to: entry.host) }
                }
            }
            Divider()
            Button(store.l10n(.rowCopyAddress)) { store.copyAddress(of: entry.host) }
        }
    }
}

/// Ported from RouterMenu's `PopoverView.CopyIconButton`: flips the glyph to
/// a green checkmark for ~1.5s after copying, giving clear feedback that the
/// click actually did something — a plain doc-on-doc icon with no state
/// change here would leave the user unsure whether the copy succeeded.
/// `onCopy` (rather than writing to the pasteboard directly) lets the caller
/// route the actual copy through `HostStore.copyAddress(of:)`, keeping
/// clipboard access centralized in the launcher.
private struct CopyIconButton: View {
    let text: String
    let help: String
    let copiedHelp: String
    let onCopy: () -> Void
    @State private var copied = false

    var body: some View {
        Button {
            onCopy()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied ? AnyShapeStyle(.green)
                                        : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .help(copied ? copiedHelp : help)
    }
}

/// Same feedback idea as `CopyIconButton`: a spinner while the Macs answer
/// (an SSH round-trip can take a few seconds), then a green checkmark or a
/// red cross for ~1.5s. The reason for a failure goes to the menu's error
/// banner through `HostStore.launchError`.
private struct MonitorSwitchButton: View {
    enum Phase { case idle, working, switched, failed }

    let help: String
    let onSwitch: () async -> Bool
    @State private var phase = Phase.idle

    var body: some View {
        Button {
            guard phase != .working else { return }
            phase = .working
            Task {
                phase = await onSwitch() ? .switched : .failed
                try? await Task.sleep(for: .seconds(1.5))
                phase = .idle
            }
        } label: {
            switch phase {
            case .working:
                ProgressView().controlSize(.mini)
            case .switched:
                Image(systemName: "checkmark").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark").foregroundStyle(.red)
            case .idle:
                Image(systemName: "display").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
