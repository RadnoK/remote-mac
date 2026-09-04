import RemoteMacCore
import SwiftUI

struct MenuView: View {
    let store: HostStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let error = store.tailscaleError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }

            if let error = store.launchError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }

            if store.entries.isEmpty {
                Text("Brak maszyn")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.entries) { entry in
                    HostRow(entry: entry, store: store)
                }
            }

            Divider().padding(.vertical, 4)

            Button("Odśwież") {
                Task { await store.refresh() }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)

            Button("Ustawienia…") { openSettings() }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)

            Button("Zakończ") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .frame(width: 280)
        .task { await store.refresh() }
    }
}
