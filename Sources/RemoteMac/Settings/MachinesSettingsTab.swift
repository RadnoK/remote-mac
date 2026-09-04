import RemoteMacCore
import SwiftUI

/// Manual-machine manager, modeled on RouterMenu's `DevicesSettingsTab`: a
/// bordered, inset list on the left with an add/remove strip attached to its
/// bottom edge, and the selected machine's editable fields filling the right
/// pane.
///
/// Selection is tracked by array index, not by `ManualHost` identity: the
/// address IS the host's identity everywhere else in the app (`mergeHosts`
/// uses it as `Host.id`), but the detail pane lets the user edit that same
/// address field live. An identity derived from it would change on every
/// keystroke and knock the list selection loose mid-edit.
struct MachinesSettingsTab: View {
    @Bindable var store: HostStore

    @State private var selection: Int?
    @State private var confirmingRemoval = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            machineBox
                .frame(width: 220)

            detail
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(12)
        .onAppear { selectFirstIfNeeded() }
    }

    private var machineBox: some View {
        VStack(spacing: 0) {
            if store.settings.manualHosts.isEmpty {
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
                    ForEach(Array(store.settings.manualHosts.enumerated()), id: \.offset) { index, host in
                        row(for: host).tag(index)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Divider()

            // The classic add/remove strip: bare glyphs split by a hairline.
            HStack(spacing: 0) {
                Button {
                    store.settings.manualHosts.append(
                        ManualHost(name: store.l10n(.settingsHostNameField), address: ""))
                    selection = store.settings.manualHosts.count - 1
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
                .disabled(selection == nil)
                .help(store.l10n(.settingsHostRemove))
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

    private func row(for host: ManualHost) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(host.name.isEmpty ? store.l10n(.settingsHostNameField) : host.name)
                .lineLimit(1)
            Text(host.address.isEmpty ? "—" : host.address)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var detail: some View {
        if let index = selection, store.settings.manualHosts.indices.contains(index) {
            // `.id` re-creates the form's identity when the selection moves
            // to another row index, so a stale focus state from the
            // previous machine cannot bleed into this one.
            Form {
                Section {
                    TextField(store.l10n(.settingsHostNameField),
                              text: $store.settings.manualHosts[index].name)
                    TextField(store.l10n(.settingsHostAddressField),
                              text: $store.settings.manualHosts[index].address)
                } header: {
                    Text(store.l10n(.settingsHostDetailSection))
                }
            }
            .formStyle(.grouped)
            .id(index)
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

    private func selectFirstIfNeeded() {
        guard selection == nil, !store.settings.manualHosts.isEmpty else { return }
        selection = 0
    }

    private func removeSelected() {
        guard let selection, store.settings.manualHosts.indices.contains(selection) else { return }
        store.settings.manualHosts.remove(at: selection)
        self.selection = store.settings.manualHosts.isEmpty
            ? nil
            : min(selection, store.settings.manualHosts.count - 1)
    }
}
