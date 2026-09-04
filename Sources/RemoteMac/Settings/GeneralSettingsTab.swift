import RemoteMacCore
import SwiftUI

/// Terminal, SSH username, launch-at-login and interface language — the
/// settings a user is most likely to open the window for.
struct GeneralSettingsTab: View {
    @Bindable var store: HostStore
    @State private var loginState = LoginItem.current

    var body: some View {
        Form {
            Section {
                Picker(store.l10n(.settingsTerminalField), selection: $store.settings.terminal) {
                    ForEach(store.availableTerminals(), id: \.self) { terminal in
                        Text(terminal.displayName).tag(terminal)
                    }
                }

                if store.settings.terminal == .warp {
                    Text(store.l10n(.settingsWarpClipboardHint))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if store.settings.terminal.requiresAppleEvents {
                    Text(store.l10n(.settingsTerminalAutomationHint))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                TextField(store.l10n(.settingsSSHUsernameField), text: $store.settings.defaultSSHUsername)
                Text(store.l10n(.settingsSSHUsernameFieldHelp))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(store.l10n(.settingsGeneralSection))
            }

            Section {
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
                .help(store.l10n(.settingsLaunchAtLoginHelp))

                if loginState == .requiresApproval {
                    Button(store.l10n(.settingsOpenSystemSettings)) { LoginItem.openSystemSettings() }
                }
                if loginState == .unavailable {
                    Text(loginState.label(store.l10n))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = store.settingsError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker(store.l10n(.settingsLanguage), selection: $store.settings.language) {
                    Text(store.l10n(.settingsLanguageSystem)).tag(AppLanguage.system)
                    Text(store.l10n(.settingsLanguagePolish)).tag(AppLanguage.pl)
                    Text(store.l10n(.settingsLanguageEnglish)).tag(AppLanguage.en)
                }
            } header: {
                Text(store.l10n(.settingsAppearanceSection))
            }
        }
        .formStyle(.grouped)
        .task {
            // The user may have removed the app from Login Items while this
            // window was closed.
            loginState = LoginItem.current
        }
    }
}
