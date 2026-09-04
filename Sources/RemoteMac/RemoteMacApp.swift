import RemoteMacCore
import SwiftUI

@main
struct RemoteMacApp: App {
    @State private var store = HostStore()

    var body: some Scene {
        MenuBarExtra("RemoteMac", systemImage: "display.2") {
            MenuView(store: store)
                .task { store.startPolling() }
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
