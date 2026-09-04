import AppKit
import RemoteMacCore

/// The menu bar app must NOT quit when the Settings window closes.
///
/// By default, SwiftUI's `Window`/`Settings` scenes return `true` from
/// `applicationShouldTerminateAfterLastWindowClosed` and end the process once
/// there are no open windows. RemoteMac is `LSUIElement` and lives entirely
/// in the menu bar — it has no "last window" in the sense that rule assumes,
/// so without overriding this, closing Settings (or the quick switcher) kills
/// the whole app and the menu bar icon vanishes with it.
///
/// Also attaches the right-click menu to the menu bar icon and owns the
/// Sparkle updater. Ported from RouterMenu's `AppDelegate`, which documents
/// the same failure modes; adapted because `HostStore` here is owned by the
/// `App` struct's `@State` rather than by the delegate, so it is injected
/// after `RemoteMacApp.init` creates this delegate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owns Sparkle's controller for the app's lifetime. Unlike `AppSettings`,
    /// Sparkle keeps its own preferences in UserDefaults, so there is nothing
    /// here to inject from outside.
    let updater = UpdaterController()

    /// Set by `RemoteMacApp.init` immediately after this delegate is created
    /// — `@NSApplicationDelegateAdaptor` builds the delegate before the
    /// scene body (and therefore before `@State private var store` is
    /// available to read), so the reference has to arrive after the fact
    /// rather than through `init`.
    var store: HostStore?

    /// Retains the right-click monitor on the menu bar icon; releasing it
    /// would remove the event monitor.
    private var statusItemObserver: RightClickMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        attachStatusItemMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Gives the menu bar icon a right-click menu.
    ///
    /// `MenuBarExtra` keeps its `NSStatusItem` private and creates it lazily,
    /// so there is nothing to attach to at launch. The item shows up as a
    /// status-bar window, which is what this looks for — retrying briefly
    /// rather than assuming a fixed delay.
    private func attachStatusItemMenu() {
        Task { @MainActor [weak self] in
            for _ in 0..<20 {
                if let self, self.installMenuOnStatusItem() { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Walks the app's windows for the one hosting the status item's button.
    /// Returns whether the menu found a home.
    @discardableResult
    private func installMenuOnStatusItem() -> Bool {
        for window in NSApp.windows {
            guard let button = Self.statusButton(in: window.contentView) else { continue }
            // NOT `button.menu = …`: AppKit pops an assigned menu on EVERY
            // click, which swallows the primary one and leaves the popover
            // unopenable. Instead the right click is intercepted here and the
            // menu popped by hand, leaving MenuBarExtra's own left-click
            // handling untouched.
            let monitor = RightClickMonitor(button: button) { [weak self] in
                guard let self, let store = self.store else { return }
                let menu = StatusItemMenu.make(
                    l10n: store.l10n,
                    onRefresh: { Task { await store.refresh() } },
                    onOpenSettings: { SettingsWindowOpener.open() },
                    onCheckForUpdates: { self.updater.checkForUpdates() }
                )
                menu.popUp(positioning: nil,
                           at: NSPoint(x: 0, y: button.bounds.height + 4),
                           in: button)
            }
            statusItemObserver = monitor
            return true
        }
        return false
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }
}
