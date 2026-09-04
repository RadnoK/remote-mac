import RemoteMacCore
import SwiftUI

/// Sparkle update preferences and a manual check.
///
/// Ported from RouterMenu's `UpdatesSettingsTab`, adapted to this app's
/// `store.l10n(...)` call convention instead of an injected `l10n` value.
struct UpdatesSettingsTab: View {
    @Bindable var store: HostStore
    @Bindable var updater: UpdaterController

    var body: some View {
        Form {
            Section {
                LabeledContent(store.l10n(.settingsVersion), value: AppInfo.version)
                LabeledContent(store.l10n(.settingsBuild), value: AppInfo.build)
            }

            Section {
                Toggle(store.l10n(.settingsAutoCheck), isOn: $updater.automaticallyChecksForUpdates)
                if updater.automaticallyChecksForUpdates {
                    Picker(store.l10n(.settingsFrequency), selection: $updater.updateCheckInterval) {
                        Text(store.l10n(.settingsFrequencyDaily)).tag(TimeInterval(86_400))
                        Text(store.l10n(.settingsFrequencyWeekly)).tag(TimeInterval(604_800))
                    }
                    Toggle(store.l10n(.settingsAutoDownload),
                           isOn: $updater.automaticallyDownloadsUpdates)
                }
            }

            Section {
                HStack {
                    Text(Self.lastCheckLabel(updater.lastUpdateCheckDate, l10n: store.l10n))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(store.l10n(.settingsCheckNow)) { updater.checkForUpdates() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!updater.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped)
    }

    static func lastCheckLabel(_ date: Date?, l10n: L10n) -> String {
        guard let date else { return l10n(.settingsNeverChecked) }
        let f = RelativeDateTimeFormatter()
        f.locale = l10n.locale
        return l10n(.settingsLastChecked, f.localizedString(for: date, relativeTo: Date()))
    }
}
