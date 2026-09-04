import AppKit

/// Opens the app's `Settings` scene from code.
///
/// SwiftUI wires the Settings scene to the "Settings…" item in the app menu
/// and exposes no API to open it. `NSApplication` does not implement
/// `showSettingsWindow:` or `showPreferencesWindow:` either, so the only
/// reliable route is to trigger that menu item the way a click would.
///
/// Ported from RouterMenu, which hit the same problem: `openSettings()` from
/// `\.openSettings` (what RemoteMac used before) opens the window, but
/// leaves an `LSUIElement` app un-activated — the window can land behind the
/// frontmost app. This route activates the app first, which is the one thing
/// `openSettings()` does not do for us.
enum SettingsWindowOpener {
    /// Menu items SwiftUI may use for the Settings scene, across macOS versions.
    /// Matched by action name so a localized title cannot break the lookup.
    static let actionNames = ["showSettingsWindow:", "showPreferencesWindow:", "menuAction:"]

    @MainActor
    static func open() {
        // An LSUIElement app is not activated by a menu bar click, so without
        // this the window opens behind the frontmost app.
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Ask AppKit directly first. Driving the "Settings…" menu item found
        // the item but opened nothing in this app, so the menu route below is
        // only a fallback. Views should prefer SwiftUI's `openSettings()`
        // environment action — this type exists for callers like AppDelegate
        // that have no SwiftUI environment to read.
        for name in ["showSettingsWindow:", "showPreferencesWindow:"] {
            let selector = NSSelectorFromString(name)
            if NSApplication.shared.sendAction(selector, to: nil, from: nil) { return }
        }

        if performSettingsItem() { return }

        // SwiftUI populates `mainMenu` lazily, and for an LSUIElement app it
        // may not exist yet at the moment the panel's button fires — reading
        // it immediately after `activate` can find only the system-owned
        // Apple menu. Retry on the next runloop turns rather than failing
        // silently, which is what left the Settings window unopenable.
        var attemptsLeft = 10
        func retry() {
            guard attemptsLeft > 0 else {
                NSLog("RemoteMac: could not locate the Settings menu item")
                return
            }
            attemptsLeft -= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated {
                    if !performSettingsItem() { retry() }
                }
            }
        }
        retry()
    }

    /// Walks every top-level menu, not just the first: for an LSUIElement app
    /// the app menu is not reliably at index 0 — the Apple menu can occupy it.
    @MainActor
    private static func performSettingsItem() -> Bool {
        guard let mainMenu = NSApplication.shared.mainMenu else { return false }
        for top in 0..<mainMenu.numberOfItems {
            guard let submenu = mainMenu.item(at: top)?.submenu,
                  let index = settingsItemIndex(in: submenu) else { continue }
            submenu.performActionForItem(at: index)
            return true
        }
        return false
    }

    /// The Settings item sits in the app menu, between About and Services.
    /// Prefer an exact action match; fall back to the standard Command-,
    /// shortcut, which SwiftUI assigns to that item.
    @MainActor
    static func settingsItemIndex(in submenu: NSMenu) -> Int? {
        for i in 0..<submenu.numberOfItems {
            guard let item = submenu.item(at: i) else { continue }
            if let action = item.action, actionNames.contains(NSStringFromSelector(action)),
               item.keyEquivalent == "," {
                return i
            }
        }
        for i in 0..<submenu.numberOfItems {
            guard let item = submenu.item(at: i) else { continue }
            if item.keyEquivalent == "," && item.keyEquivalentModifierMask == .command {
                return i
            }
        }
        return nil
    }
}
