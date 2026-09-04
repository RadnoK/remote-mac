import RemoteMacCore
import SwiftUI

struct QuickSwitcher: View {
    let store: HostStore
    @State private var query = ""
    @State private var selection = 0
    @Environment(\.dismiss) private var dismiss

    private var results: [HostEntry] {
        let hosts = searchHosts(store.entries.map(\.host), query: query)
        return hosts.compactMap { host in
            store.entries.first { $0.host.id == host.id }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Szukaj maszyny…", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(12)
                .onChange(of: query) { selection = 0 }
                .onSubmit { activate() }

            Divider()

            List(Array(results.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 8) {
                    StatusDot(status: entry.status)
                    Text(entry.host.displayName)
                    Spacer()
                    Text(entry.host.ipv4).foregroundStyle(.secondary).font(.caption)
                }
                .padding(.vertical, 2)
                .listRowBackground(
                    index == selection ? Color.accentColor.opacity(0.2) : Color.clear
                )
                .onTapGesture {
                    selection = index
                    activate()
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 420, height: 300)
        .onKeyPress(.upArrow) {
            guard !results.isEmpty else { return .handled }
            selection = max(0, selection - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !results.isEmpty else { return .handled }
            selection = min(results.count - 1, selection + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    /// Enter connects via Screen Sharing; ⌘-Enter opens SSH instead.
    ///
    /// `selection` is reset to 0 whenever the query changes, but `results` is
    /// recomputed independently and can be empty (e.g. a query that matches
    /// nothing). Guarding on `results.indices.contains(selection)` here
    /// ensures a stale or out-of-range selection — in particular an empty
    /// `results` array — never resolves to a host, so Enter with no matches
    /// does nothing instead of connecting to whatever was selected before.
    private func activate() {
        guard results.indices.contains(selection) else { return }
        let host = results[selection].host
        if NSEvent.modifierFlags.contains(.command) {
            store.openSSH(to: host)
        } else {
            store.connect(to: host)
        }
        dismiss()
    }
}
