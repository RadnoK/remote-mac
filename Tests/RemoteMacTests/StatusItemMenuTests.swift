import AppKit
import Foundation
import Testing
@testable import RemoteMac
@testable import RemoteMacCore

/// The right-click menu on the menu bar icon. `MenuBarExtra` owns the left
/// click (it opens the popover), so the secondary menu is built by hand and
/// its contents are worth pinning down.
@MainActor
struct StatusItemMenuTests {
    @Test func theMenuOffersSettingsAndQuit() {
        let l10n = L10n(language: .en, bundles: [])
        let menu = StatusItemMenu.make(l10n: l10n, onRefresh: {}, onOpenSettings: {}, onCheckForUpdates: {})
        let titles = menu.items.map(\.title)
        #expect(titles.contains(l10n(.menuSettings)), "got \(titles)")
        #expect(titles.contains(l10n(.menuQuit)), "got \(titles)")
    }

    /// Cmd-Q is what a user reaches for; the menu should say so rather than
    /// leaving the shortcut undiscoverable.
    @Test func quitCarriesTheStandardShortcut() {
        let menu = StatusItemMenu.make(l10n: L10n(language: .en, bundles: []),
                                       onRefresh: {}, onOpenSettings: {}, onCheckForUpdates: {})
        let quit = menu.items.first { $0.action == #selector(NSApplication.terminate(_:)) }
        #expect(quit?.keyEquivalent == "q")
        #expect(quit?.keyEquivalentModifierMask == .command)
    }

    /// Cmd-, mirrors the standard "Settings…" shortcut.
    @Test func settingsCarriesTheStandardShortcut() {
        let menu = StatusItemMenu.make(l10n: L10n(language: .en, bundles: []),
                                       onRefresh: {}, onOpenSettings: {}, onCheckForUpdates: {})
        let settings = menu.items.first { $0.title == "menu.settings" }
        #expect(settings?.keyEquivalent == ",")
    }

    /// A menu item with no target falls back to the responder chain, which is
    /// what actually lets `terminate(_:)` reach NSApp.
    @Test func quitIsWiredToTerminate() {
        let menu = StatusItemMenu.make(l10n: L10n(language: .en, bundles: []),
                                       onRefresh: {}, onOpenSettings: {}, onCheckForUpdates: {})
        let quit = menu.items.first { $0.title == "menu.quit" }
        #expect(quit?.action == #selector(NSApplication.terminate(_:)))
    }

    /// Refresh, Settings, and Check for Updates each fire their own closure
    /// rather than sharing one action — clicking one must not trigger another.
    @Test func eachActionFiresItsOwnClosure() {
        var refreshed = false
        var openedSettings = false
        var checkedForUpdates = false
        let menu = StatusItemMenu.make(
            l10n: L10n(language: .en, bundles: []),
            onRefresh: { refreshed = true },
            onOpenSettings: { openedSettings = true },
            onCheckForUpdates: { checkedForUpdates = true }
        )

        func fire(_ title: String) {
            guard let item = menu.items.first(where: { $0.title == title }),
                  let target = item.target, let action = item.action else { return }
            _ = target.perform(action, with: item)
        }

        fire("menu.refresh")
        #expect(refreshed)
        #expect(!openedSettings)
        #expect(!checkedForUpdates)

        fire("menu.settings")
        #expect(openedSettings)

        fire("menu.check_for_updates")
        #expect(checkedForUpdates)
    }

    /// The menu is rebuilt per click so it picks up a language change without
    /// the app being restarted.
    @Test func theMenuIsLocalizedAtBuildTime() throws {
        let bundle = try Self.resourcesBundle()
        let pl = StatusItemMenu.make(l10n: L10n(language: .pl, bundles: [bundle]),
                                     onRefresh: {}, onOpenSettings: {}, onCheckForUpdates: {})
        let quit = pl.items.first { $0.action == #selector(NSApplication.terminate(_:)) }
        #expect(quit?.title == "Zakończ")
    }

    /// The repository's `Resources/` directory as a `Bundle`, mirroring
    /// `RemoteMacCoreTests`'s `LocalizationTestSupport` helper — duplicated
    /// here rather than shared, because this test target does not depend on
    /// that one.
    private static func resourcesBundle() throws -> Bundle {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RemoteMacTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Resources")
        return try #require(Bundle(url: url), "no bundle at \(url.path)")
    }
}
