import RemoteMacCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: HostStore
    @State private var loginState = LoginItem.current
    @State private var newHostName = ""
    @State private var newHostAddress = ""

    var body: some View {
        TabView {
            general.tabItem { Label("Ogólne", systemImage: "gearshape") }
            hosts.tabItem { Label("Maszyny", systemImage: "display.2") }
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

            Picker("Terminal:", selection: $store.settings.terminal) {
                ForEach(store.availableTerminals(), id: \.self) { terminal in
                    Text(terminal.displayName).tag(terminal)
                }
            }

            if store.settings.terminal == .warp {
                Text("Warp nie pozwala uruchomić komendy automatycznie. "
                     + "Komenda trafi do schowka — wklej ją przez ⌘V.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.settings.terminal.requiresAppleEvents {
                Text("Terminal wymaga zgody na automatyzację. "
                     + "macOS zapyta o nią przy pierwszym użyciu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Użytkownik SSH:", text: $store.settings.defaultSSHUsername)

            Divider()

            Toggle("Uruchamiaj przy logowaniu", isOn: Binding(
                get: { loginState == .enabled },
                set: { enabled in
                    try? LoginItem.setEnabled(enabled)
                    loginState = LoginItem.current
                }
            ))
            .disabled(loginState == .unavailable)

            if loginState == .requiresApproval {
                Button("Otwórz Ustawienia systemowe") { LoginItem.openSystemSettings() }
            }
            if loginState == .unavailable {
                Text(loginState.label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hosts: some View {
        VStack(alignment: .leading) {
            Text("Ręcznie dodane maszyny")
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
                TextField("Nazwa", text: $newHostName)
                TextField("Adres IP", text: $newHostAddress)
                Button("Dodaj") {
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
