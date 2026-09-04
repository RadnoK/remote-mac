import RemoteMacCore
import SwiftUI

@main
struct RemoteMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = HostStore()

    var body: some Scene {
        MenuBarExtra("RemoteMac", systemImage: "display.2") {
            MenuView(store: store)
                .task {
                    // `startPolling()` only refreshes on its very first call
                    // (it no-ops while already polling), so without an
                    // explicit refresh here, every menu open after the first
                    // would show state up to 30s stale. The generation
                    // counter in `HostStore.refresh()` makes this safe to
                    // overlap with an in-flight poll tick.
                    await store.refresh()
                    store.startPolling()
                }
        }
        // `.window` is required: `.menu` renders an NSMenu, which cannot host
        // coloured status indicators or custom rows.
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }

        // The title is a literal, not `store.l10n(...)`: reading observable
        // state while building the scene graph makes the graph itself depend
        // on that state, and SwiftUI then rebuilds the scenes on every store
        // change. That left the `Settings` scene unopenable — its menu item
        // existed and fired, but no window appeared. Scene structure has to
        // stay static; the window's own content is localized normally.
        Window("Quick Connect", id: "quick-switcher") {
            QuickSwitcher(store: store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
