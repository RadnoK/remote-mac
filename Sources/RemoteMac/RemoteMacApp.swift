import RemoteMacCore
import SwiftUI

@main
struct RemoteMacApp: App {
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

        Window("Szybkie połączenie", id: "quick-switcher") {
            QuickSwitcher(store: store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
