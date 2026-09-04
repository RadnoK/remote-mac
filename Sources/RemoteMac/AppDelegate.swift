import AppKit

/// The menu bar app must NOT quit when the Settings window closes.
///
/// By default, SwiftUI's `Window`/`Settings` scenes return `true` from
/// `applicationShouldTerminateAfterLastWindowClosed` and end the process once
/// there are no open windows. RemoteMac is `LSUIElement` and lives entirely
/// in the menu bar — it has no "last window" in the sense that rule assumes,
/// so without overriding this, closing Settings (or the quick switcher) kills
/// the whole app and the menu bar icon vanishes with it.
///
/// Ported from RouterMenu's `AppDelegate`, which documents the same failure
/// mode.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
