import AppKit
import RemoteMacCore
import SwiftUI

/// The menu bar panel. Visual language ported from RouterMenu's
/// `PopoverView`: a header, content grouped in a pane card, an icon-only
/// borderless footer, and the translucent `.menu` material via
/// `PopoverPanelSizer`.
struct MenuView: View {
    let store: HostStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let error = store.tailscaleError {
                banner(error)
            }

            if let error = store.launchError {
                dismissibleBanner(error)
            }

            content

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 320)
        .background(PopoverPanelSizer(stateKey: Self.stateKey(for: store)))
    }

    /// One key per content case the panel actually renders differently —
    /// deliberately blind to entry count/details so a poll tick's data
    /// churn never re-triggers a re-fit while the menu is open; only the
    /// loading → loaded and empty → populated transitions do.
    static func stateKey(for store: HostStore) -> String {
        if store.isLoading { return "loading" }
        return store.entries.isEmpty ? "empty" : "populated"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.l10n(.menuHeaderTitle))
                .font(.headline)
            Text(Self.summary(for: store))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// "3 machines · 2 available" while data has loaded; a quieter label
    /// while the first probe pass is still in flight or nothing has ever
    /// been discovered.
    static func summary(for store: HostStore) -> String {
        if store.isLoading { return store.l10n(.menuLoading) }
        if store.entries.isEmpty { return store.l10n(.menuNoHosts) }
        let available = store.entries.filter { $0.status.isConnectable }.count
        return store.l10n(.menuHeaderSummary, store.entries.count, available)
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(store.l10n(.menuLoading))
                Spacer()
            }
            .padding(.vertical, 14)
        } else if store.entries.isEmpty {
            Text(store.l10n(.menuNoHosts))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
        } else {
            pane(store.l10n(.menuSectionMachines)) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.entries) { entry in
                        HostRow(entry: entry, store: store)
                    }
                }
            }
        }
    }

    /// RouterMenu's pane idiom: an uppercased caption title over content,
    /// boxed in a subtle rounded card so the machine list reads as one
    /// grouped unit instead of loose rows floating in the panel.
    private func pane<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func banner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func dismissibleBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            banner(message)
            Spacer(minLength: 4)
            Button {
                store.clearLaunchError()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await store.refresh() }
            } label: {
                Label(store.l10n(.menuRefresh), systemImage: "arrow.clockwise")
            }
            .help(store.l10n(.menuRefresh))

            Button {
                NSApp.activate()
                openWindow(id: "quick-switcher")
            } label: {
                Label(store.l10n(.menuQuickConnect), systemImage: "magnifyingglass")
            }
            .help(store.l10n(.menuQuickConnect))

            Spacer()

            Button {
                // `openSettings()` is SwiftUI's supported route and is what
                // actually opens the window here. Driving the "Settings…"
                // menu item via `performActionForItem` (the RouterMenu
                // approach) found the item but opened nothing in this app.
                // Activation still has to happen explicitly: an LSUIElement
                // app is not frontmost when its panel is showing, so without
                // it the window opens behind whatever app is.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label(store.l10n(.menuSettings), systemImage: "gearshape")
            }
            .help(store.l10n(.menuSettings))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(store.l10n(.menuQuit), systemImage: "power")
            }
            .help(store.l10n(.menuQuit))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}
