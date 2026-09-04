import AppKit
import XCTest
@testable import RemoteMac

/// Guards how the panel opens the Settings window.
///
/// `NSApplication` does not implement `showSettingsWindow:` or
/// `showPreferencesWindow:`, so the only reliable route is finding and
/// triggering the app menu's "Settings…" item the way a click would. Ported
/// from RouterMenu's `SettingsWindowTests`, which pins the same facts.
///
/// `XCTestCase`, not swift-testing: this file touches `NSApplication.shared`
/// and `NSMenu`, and running that concurrently with this package's other
/// tests — several of which spawn real subprocesses via `swift-subprocess`
/// (`TailscaleClient`, `SSHStatusClient`, `PortProbeTests`) — reproduced a
/// process hang under swift-testing's default concurrent scheduling in this
/// environment (the main thread parked forever in `CFRunLoopRun` alongside
/// AppKit's `NSEventThread`, even once every individual test had already
/// reported "passed"). RouterMenu's equivalent AppKit-touching tests are
/// also `XCTestCase`, and did not reproduce the hang when checked directly
/// against this same toolchain.
@MainActor
final class SettingsWindowOpenerTests: XCTestCase {
    func testNSApplicationDoesNotImplementSettingsSelectors() {
        // If a future macOS implements these, this fails and the opener can
        // be simplified back to calling them directly.
        XCTAssertFalse(NSApplication.shared.responds(to: Selector(("showSettingsWindow:"))))
        XCTAssertFalse(NSApplication.shared.responds(to: Selector(("showPreferencesWindow:"))))
    }

    func testFindsSettingsItemByActionAndShortcut() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About", action: Selector(("orderFrontStandardAboutPanel:")), keyEquivalent: "")
        let settings = menu.addItem(withTitle: "Settings…", action: Selector(("menuAction:")), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command

        XCTAssertEqual(SettingsWindowOpener.settingsItemIndex(in: menu), 1)
    }

    func testFallsBackToShortcutWhenActionIsUnknown() {
        // SwiftUI's action name has changed across releases; the Command-,
        // shortcut is the stable signal.
        let menu = NSMenu()
        menu.addItem(withTitle: "About", action: nil, keyEquivalent: "")
        let settings = menu.addItem(withTitle: "Ustawienia…", action: Selector(("someFutureAction:")), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command

        XCTAssertEqual(SettingsWindowOpener.settingsItemIndex(in: menu), 1)
    }

    func testReturnsNilWhenThereIsNoSettingsItem() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: nil, keyEquivalent: "q")

        XCTAssertNil(SettingsWindowOpener.settingsItemIndex(in: menu))
    }
}
