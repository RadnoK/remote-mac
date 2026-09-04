import RemoteMacCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: HostStore
    @State private var loginState = LoginItem.current
    @State private var newHostName = ""
    @State private var newHostAddress = ""

    var body: some View {
        TabView {
            general.tabItem { Label(store.l10n(.settingsTabGeneral), systemImage: "gearshape") }
            hosts.tabItem { Label(store.l10n(.settingsTabHosts), systemImage: "display.2") }
        }
        .frame(width: 460, height: 340)
    }

    private var general: some View {
        Form {
            if let error = store.settingsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Picker(store.l10n(.settingsTerminalField), selection: $store.settings.terminal) {
                ForEach(store.availableTerminals(), id: \.self) { terminal in
                    Text(terminal.displayName).tag(terminal)
                }
            }

            if store.settings.terminal == .warp {
                Text(store.l10n(.settingsWarpClipboardHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.settings.terminal.requiresAppleEvents {
                Text(store.l10n(.settingsTerminalAutomationHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField(store.l10n(.settingsSSHUsernameField), text: $store.settings.defaultSSHUsername)

            Divider()

            Toggle(store.l10n(.settingsLaunchAtLogin), isOn: Binding(
                get: { loginState == .enabled },
                set: { enabled in
                    do {
                        try LoginItem.setEnabled(enabled)
                        store.reportSettingsError(nil)
                    } catch {
                        store.reportSettingsError(store.l10n(.settingsLaunchAtLoginError))
                    }
                    loginState = LoginItem.current
                }
            ))
            .disabled(loginState == .unavailable)

            if loginState == .requiresApproval {
                Button(store.l10n(.settingsOpenSystemSettings)) { LoginItem.openSystemSettings() }
            }
            if loginState == .unavailable {
                Text(loginState.label(store.l10n)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hosts: some View {
        VStack(alignment: .leading) {
            Text(store.l10n(.settingsManualHostsHeader))
                .font(.headline)

            List {
                ForEach(store.settings.manualHosts, id: \.self) { host in
                    HStack {
                        Text(host.name)
                        Spacer()
                        Text(host.address).foregroundStyle(.secondary)
                        Button {
                            store.settings.manualHosts.removeAll { $0 == host }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                TextField(store.l10n(.settingsHostNameField), text: $newHostName)
                TextField(store.l10n(.settingsHostAddressField), text: $newHostAddress)
                Button(store.l10n(.settingsHostAdd)) {
                    guard let host = sanitizedManualHost(name: newHostName, address: newHostAddress)
                    else { return }
                    store.settings.manualHosts.append(host)
                    newHostName = ""
                    newHostAddress = ""
                    Task { await store.refresh() }
                }
            }
        }
        .padding()
    }
}
