import RemoteMacCore
import SwiftUI

/// Device manager, modeled on RouterMenu's `DevicesSettingsTab`: a bordered,
/// inset list on the left with an add/remove strip attached to its bottom
/// edge, and the selected device's settings filling the right pane.
///
/// Lists everything from `store.entries` — Tailscale-discovered machines
/// alongside manually added ones — so a Tailscale machine can be configured
/// (SSH user, visibility, display name, Screen Sharing port) even though it
/// was never manually added. Only manual entries carry editable name/address
/// fields; a Tailscale entry's name and IP come from the tailnet and are
/// shown read-only. The +/− strip only ever adds/removes *manual* entries —
/// removing a Tailscale device is not a meaningful action here, so the
/// remove button is disabled whenever a Tailscale device is selected.
///
/// `store.entries` only ever contains manual hosts that already have an
/// address (`mergeHosts` drops address-less drafts, see its doc comment), so
/// a freshly-added blank row would be invisible if this view only read
/// `entries`. `MachineRow` merges `store.entries` with any manual host that
/// has not made it into `entries` yet, so a brand-new "+" row is immediately
/// selectable and editable.
private struct MachineRow: Identifiable {
    enum Kind {
        case entry(HostEntry)
        /// A manual host with no address yet — not in `store.entries`.
        case draft(index: Int)
    }

    let kind: Kind
    /// Stable per-row identity. Draft rows are identified by their index in
    /// `manualHosts` prefixed so they can never collide with a `Host.id`.
    let id: String
    let name: String
    let address: String
    let source: HostSource

    static func draft(index: Int, host: ManualHost) -> MachineRow {
        MachineRow(kind: .draft(index: index), id: "draft:\(index)",
                   name: host.name, address: host.address, source: .manual)
    }

    static func entry(_ entry: HostEntry) -> MachineRow {
        MachineRow(kind: .entry(entry), id: entry.host.id,
                   name: entry.host.displayName, address: entry.host.ipv4, source: entry.host.source)
    }
}

struct MachinesSettingsTab: View {
    @Bindable var store: HostStore

    @State private var selection: String?
    @State private var confirmingRemoval = false

    /// `store.entries`' manual hosts, plus any manual host still missing an
    /// address (draft rows), plus every Tailscale entry — see `MachineRow`.
    private var rows: [MachineRow] {
        let manualAddressesInEntries = Set(
            store.entries.filter { $0.host.source == .manual }.map(\.host.ipv4)
        )
        let drafts = store.settings.manualHosts.enumerated().compactMap { index, host -> MachineRow? in
            guard !manualAddressesInEntries.contains(host.address) else { return nil }
            return .draft(index: index, host: host)
        }
        return (store.entries.map(MachineRow.entry) + drafts)
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            machineBox
                .frame(width: 220)

            detail
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(12)
        .onAppear { selectFirstIfNeeded() }
        // `store.entries` is empty until the first refresh completes, so the
        // initially-empty list becomes populated asynchronously — re-run the
        // same "select something if nothing is selected" logic once real
        // data lands, instead of leaving the pane permanently on its empty
        // state just because `onAppear` fired before data existed.
        .onChange(of: store.isLoading) { selectFirstIfNeeded() }
    }

    private var selectedRow: MachineRow? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private var machineBox: some View {
        VStack(spacing: 0) {
            if store.isLoading && rows.isEmpty {
                // The first refresh has not landed yet — a blank list at this
                // point is a normal cold start, not "no machines", so show a
                // spinner rather than the empty-state copy.
                VStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                VStack {
                    Spacer()
                    Text(store.l10n(.settingsHostsEmpty))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(rows) { row in
                        rowView(for: row).tag(row.id)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Divider()

            // The classic add/remove strip: bare glyphs split by a hairline.
            HStack(spacing: 0) {
                Button {
                    let host = ManualHost(name: store.l10n(.settingsHostNameField), address: "")
                    store.settings.manualHosts.append(host)
                    selection = "draft:\(store.settings.manualHosts.count - 1)"
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .help(store.l10n(.settingsHostAdd))

                Divider().frame(height: 14)

                Button {
                    confirmingRemoval = true
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                // Only a manual entry can be removed — a Tailscale device is
                // discovered, not owned by this list, so deleting it here
                // would not be meaningful (it would just reappear on the
                // next refresh).
                .disabled(selectedRow?.source != .manual)
                .help(selectedRow?.source == .tailscale
                      ? store.l10n(.settingsHostRemoveTailscaleHelp)
                      : store.l10n(.settingsHostRemove))
                .confirmationDialog(store.l10n(.settingsHostRemoveConfirm),
                                    isPresented: $confirmingRemoval) {
                    Button(store.l10n(.settingsHostRemove), role: .destructive, action: removeSelected)
                }

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func rowView(for row: MachineRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name.isEmpty ? store.l10n(.settingsHostNameField) : row.name)
                    .lineLimit(1)
                Text(row.address.isEmpty ? "—" : row.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            sourceBadge(for: row.source)
        }
        .padding(.vertical, 2)
    }

    /// Mirrors RouterMenu's provider badge in `DevicesSettingsTab`: a small
    /// capsule label marking where the device came from.
    private func sourceBadge(for source: HostSource) -> some View {
        Text(source == .tailscale
             ? store.l10n(.settingsHostBadgeTailscale)
             : store.l10n(.settingsHostBadgeManual))
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    @ViewBuilder
    private var detail: some View {
        if let row = selectedRow {
            // `.id` re-creates the form's identity when the selection moves
            // to another machine, so a stale focus state from the previous
            // one cannot bleed into this one.
            Form {
                Section {
                    identitySection(for: row)
                } header: {
                    Text(store.l10n(.settingsHostDetailSection))
                }

                // Per-device settings only make sense once the host is
                // actually addressable — a draft manual row (no address yet)
                // has no `Host.id` to key these overrides by, so it only
                // gets the name/address fields above until it graduates into
                // a real entry on the next refresh.
                if case let .entry(entry) = row.kind {
                    Section {
                        TextField(
                            store.l10n(.settingsHostDisplayNameField),
                            text: displayNameBinding(for: entry.host.id),
                            prompt: Text(entry.host.name)
                        )
                        Toggle(store.l10n(.settingsHostShowInMenu),
                               isOn: shownInMenuBinding(for: entry.host.id))
                    } header: {
                        Text(store.l10n(.settingsHostAppearanceSection))
                    }

                    Section {
                        // Empty means "use the global default SSH user" —
                        // see `AppSettings.sshUsername(for:)`. The
                        // placeholder makes that fallback visible instead of
                        // leaving the field looking simply blank/unset.
                        TextField(
                            store.l10n(.settingsHostSSHUserField),
                            text: sshUsernameBinding(for: entry.host.id),
                            prompt: Text(store.settings.defaultSSHUsername)
                        )
                        TextField(
                            store.l10n(.settingsHostPortField),
                            text: screenSharingPortBinding(for: entry.host.id),
                            prompt: Text(String(RemoteMacCore.screenSharingPort))
                        )
                    } header: {
                        Text(store.l10n(.settingsHostConnectionSection))
                    }
                }
            }
            .formStyle(.grouped)
            .id(row.id)
        } else {
            VStack {
                Spacer()
                Text(store.l10n(.settingsHostsEmpty))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func identitySection(for row: MachineRow) -> some View {
        switch row.kind {
        case let .draft(index):
            TextField(store.l10n(.settingsHostNameField),
                      text: $store.settings.manualHosts[index].name)
            TextField(store.l10n(.settingsHostAddressField),
                      text: $store.settings.manualHosts[index].address)
        case let .entry(entry) where entry.host.source == .manual:
            manualFields(matching: entry.host.ipv4)
        case let .entry(entry):
            LabeledContent(store.l10n(.settingsHostNameField), value: entry.host.displayName)
            LabeledContent(store.l10n(.settingsHostAddressField), value: entry.host.ipv4)
        }
    }

    /// A manual entry that has graduated into `store.entries` is still bound
    /// to its `ManualHost` in `settings.manualHosts` (by address, its
    /// identity) rather than to the resolved `Host`, so editing name/address
    /// here writes straight back to the source of truth instead of a
    /// read-only snapshot.
    @ViewBuilder
    private func manualFields(matching address: String) -> some View {
        if let index = store.settings.manualHosts.firstIndex(where: { $0.address == address }) {
            TextField(store.l10n(.settingsHostNameField),
                      text: $store.settings.manualHosts[index].name)
            TextField(store.l10n(.settingsHostAddressField),
                      text: $store.settings.manualHosts[index].address)
        }
    }

    /// Empty text means "use the global default" — see
    /// `AppSettings.sshUsername(for:)` — so writing an empty string removes
    /// the per-host key entirely rather than persisting "".
    private func sshUsernameBinding(for hostID: String) -> Binding<String> {
        Binding(
            get: { store.settings.sshUsernames[hostID] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    store.settings.sshUsernames.removeValue(forKey: hostID)
                } else {
                    store.settings.sshUsernames[hostID] = newValue
                }
            }
        )
    }

    /// Same empty-means-"use the default name" convention as the SSH user
    /// field.
    private func displayNameBinding(for hostID: String) -> Binding<String> {
        Binding(
            get: { store.settings.displayNameOverrides[hostID] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    store.settings.displayNameOverrides.removeValue(forKey: hostID)
                } else {
                    store.settings.displayNameOverrides[hostID] = newValue
                }
            }
        )
    }

    /// Text-based (rather than a `Stepper`/numeric field) so the field can
    /// sit empty as "use the default port" the same way the SSH user and
    /// display name fields do. Only digits parse to a valid `UInt16`; any
    /// other input (including a value that overflows `UInt16`) is treated as
    /// "not a valid override" and is simply not written — the field keeps
    /// showing what the user typed until they correct it, but no invalid
    /// state reaches `AppSettings`.
    private func screenSharingPortBinding(for hostID: String) -> Binding<String> {
        Binding(
            get: {
                store.settings.screenSharingPorts[hostID].map(String.init) ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    store.settings.screenSharingPorts.removeValue(forKey: hostID)
                } else if let port = UInt16(trimmed) {
                    store.settings.screenSharingPorts[hostID] = port
                }
            }
        )
    }

    private func shownInMenuBinding(for hostID: String) -> Binding<Bool> {
        Binding(
            get: { !store.settings.hiddenHostIDs.contains(hostID) },
            set: { shown in
                if shown {
                    store.settings.hiddenHostIDs.removeAll { $0 == hostID }
                } else if !store.settings.hiddenHostIDs.contains(hostID) {
                    store.settings.hiddenHostIDs.append(hostID)
                }
            }
        )
    }

    private func selectFirstIfNeeded() {
        guard selection == nil || !rows.contains(where: { $0.id == selection }) else { return }
        selection = rows.first?.id
    }

    private func removeSelected() {
        guard let row = selectedRow else { return }
        switch row.kind {
        case let .draft(index):
            store.settings.manualHosts.remove(at: index)
        case let .entry(entry) where entry.host.source == .manual:
            guard let index = store.settings.manualHosts.firstIndex(where: { $0.address == entry.host.ipv4 }) else { return }
            store.settings.manualHosts.remove(at: index)
        case .entry:
            return
        }
        selection = nil
    }
}
