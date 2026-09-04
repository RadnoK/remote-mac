import AppKit
import RemoteMacCore

/// The right-click menu on the menu bar icon.
///
/// `MenuBarExtra` owns the primary click — it opens the popover — and offers
/// no hook for the secondary one, so the menu is built here and attached to
/// the status item directly. Settings, Refresh and Quit already live in the
/// popover's footer too; the point of repeating them is that a right click
/// is where people look for them, and the popover has to be opened to reach
/// the footer at all.
///
/// Ported from RouterMenu's `StatusItemMenu`.
enum StatusItemMenu {
    @MainActor
    static func make(l10n: L10n,
                     onRefresh: @escaping () -> Void,
                     onOpenSettings: @escaping () -> Void,
                     onCheckForUpdates: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        let target = MenuActionTarget(onRefresh: onRefresh,
                                      onOpenSettings: onOpenSettings,
                                      onCheckForUpdates: onCheckForUpdates)

        let refresh = NSMenuItem(title: l10n(.menuRefresh),
                                 action: #selector(MenuActionTarget.refresh),
                                 keyEquivalent: "")
        refresh.target = target
        // Each targeted item retains the target via `representedObject` —
        // `NSMenuItem.target` is unretained (`weak`-like), so without this
        // the target would be deallocated the instant `make` returns, and
        // every click would silently no-op. The menu keeps its items alive
        // for as long as it is on screen, which is exactly the target's
        // required lifetime.
        refresh.representedObject = target
        menu.addItem(refresh)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: l10n(.menuSettings),
                                  action: #selector(MenuActionTarget.openSettings),
                                  keyEquivalent: ",")
        settings.target = target
        settings.representedObject = target
        menu.addItem(settings)

        let checkForUpdates = NSMenuItem(title: l10n(.menuCheckForUpdates),
                                         action: #selector(MenuActionTarget.checkForUpdates),
                                         keyEquivalent: "")
        checkForUpdates.target = target
        checkForUpdates.representedObject = target
        menu.addItem(checkForUpdates)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: l10n(.menuQuit),
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        // No target: the action travels the responder chain up to NSApp, which
        // is what implements terminate(_:).
        quit.target = nil
        menu.addItem(quit)

        return menu
    }
}

/// Holds the closures the menu's items fire into.
///
/// `NSMenuItem.action` needs an `@objc` selector, which cannot be a Swift
/// closure directly. This target is stashed in each targeted item's
/// `representedObject` so its lifetime matches the menu's — built fresh per
/// right click (so the menu stays localized), and released once the popup
/// closes and its items go with it.
@MainActor
private final class MenuActionTarget: NSObject {
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onCheckForUpdates: () -> Void

    init(onRefresh: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onCheckForUpdates: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.onCheckForUpdates = onCheckForUpdates
    }

    @objc func refresh() { onRefresh() }
    @objc func openSettings() { onOpenSettings() }
    @objc func checkForUpdates() { onCheckForUpdates() }
}

/// Watches one status-bar button for secondary clicks.
///
/// A local event monitor rather than an `NSStatusItem` menu: assigning a menu
/// to the button makes AppKit pop it on the primary click too, which takes the
/// popover away. The monitor sees the right click first, swallows it, and
/// leaves every other event to travel on untouched.
@MainActor
final class RightClickMonitor {
    /// The monitor handle is opaque and non-Sendable, so it lives in a box a
    /// nonisolated `deinit` is allowed to reach.
    private final class Handle: @unchecked Sendable {
        var token: Any?
        deinit { if let token { NSEvent.removeMonitor(token) } }
    }
    private let handle = Handle()

    init(button: NSStatusBarButton, onRightClick: @escaping () -> Void) {
        handle.token = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak button] event in
            // Hit-test the button itself rather than comparing windows: the
            // status item lives in a system-owned window whose identity does
            // not match, and a window-level guard would either never fire or
            // swallow clicks meant for other status items.
            guard let button, let window = button.window,
                  event.window === window else { return event }
            let local = button.convert(event.locationInWindow, from: nil)
            guard button.bounds.contains(local) else { return event }
            onRightClick()
            return nil   // swallowed: AppKit must not also handle it
        }
    }
}
