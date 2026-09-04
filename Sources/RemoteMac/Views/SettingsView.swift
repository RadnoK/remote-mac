import RemoteMacCore
import SwiftUI

/// Tabbed settings window.
///
/// Inside a `Settings` scene, `TabView` renders macOS's native preference
/// toolbar — an icon above each label, with the window title tracking the
/// selected tab. The same `TabView` in a plain `Window` scene falls back to
/// a content-style strip that drops the icons, which is why this must stay
/// inside the app's `Settings { }` scene. Each tab owns its own `Form`; this
/// type only composes them. Ported from RouterMenu's `SettingsView`.
struct SettingsView: View {
    @Bindable var store: HostStore
    @Bindable var updater: UpdaterController

    var body: some View {
        TabView {
            ForEach(SettingsTab.allCases) { tab in
                content(for: tab)
                    .tabItem { Label(store.l10n(tab.titleKey), systemImage: tab.symbolName) }
                    .tag(tab)
            }
        }
        // One fixed size for every tab, on the TabView rather than inside a
        // tab: the window opens at the FIRST tab's natural height, so a
        // short tab would open the window small and it would only grow
        // after visiting Machines. The Machines pane fills this instead.
        .frame(width: 680, height: 480)
    }

    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsTab(store: store)
        case .machines:
            MachinesSettingsTab(store: store)
        case .about:
            AboutSettingsTab(l10n: store.l10n)
        case .updates:
            UpdatesSettingsTab(store: store, updater: updater)
        }
    }
}
