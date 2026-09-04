import AppKit
import RemoteMacCore
import SwiftUI

/// Version and contact info, following RouterMenu's About section pattern.
struct AboutSettingsTab: View {
    let l10n: L10n

    var body: some View {
        Form {
            Section {
                LabeledContent(l10n(.settingsVersion), value: AppInfo.version)
                LabeledContent(l10n(.settingsAboutWebsite)) {
                    Link(AppInfo.websiteLabel, destination: AppInfo.websiteURL)
                }
                LabeledContent(l10n(.settingsAboutContact)) {
                    Button(l10n(.settingsAboutSendEmail)) {
                        NSWorkspace.shared.open(AppInfo.contactURL)
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text(l10n(.settingsAboutSection))
            }
        }
        .formStyle(.grouped)
    }
}
