import AppKit
import Foundation

public protocol Launching: Sendable {
    func openScreenSharing(host: Host)
    func openFileSharing(host: Host)
    func copyToClipboard(_ text: String)
    /// Returns `false` when the plan could not be carried out — e.g. the
    /// target app could not be resolved, or (for `.appleScript`) the script
    /// failed, which is what a denied AppleEvents/Automation TCC grant looks
    /// like for Terminal.app. Callers use this to surface a user-facing error
    /// instead of failing silently.
    func execute(_ plan: LaunchPlan) -> Bool
    func isRunning(bundleIdentifier: String) -> Bool
    func isInstalled(bundleIdentifier: String) -> Bool
}

/// Credentials are deliberately absent: Screen Sharing stores the password in
/// the macOS Keychain, so the app never handles secrets.
public func screenSharingURL(for host: Host) -> URL? {
    URL(string: "vnc://\(host.ipv4)")
}

public func fileSharingURL(for host: Host) -> URL? {
    URL(string: "smb://\(host.ipv4)")
}

public func installedTerminals(using launcher: Launching) -> [TerminalKind] {
    TerminalKind.allCases.filter { launcher.isInstalled(bundleIdentifier: $0.bundleIdentifier) }
}

/// `Sendable` here is compiler-trivial — this type holds no stored
/// properties, so the conformance only certifies that values of this type
/// can cross actor boundaries. It says nothing about whether the AppKit
/// calls inside (`NSWorkspace`, `NSPasteboard`, `NSAppleScript`) are safe to
/// invoke off the main thread; in general they are not. Callers are
/// responsible for only calling into this type from the main actor/thread —
/// see the `launcher` property on `HostStore`, whose `@MainActor` isolation
/// is what actually makes these calls safe, not this conformance.
public struct AppKitLauncher: Launching, Sendable {
    public init() {}

    public func openScreenSharing(host: Host) {
        guard let url = screenSharingURL(for: host) else { return }
        NSWorkspace.shared.open(url)
    }

    public func openFileSharing(host: Host) {
        guard let url = fileSharingURL(for: host) else { return }
        NSWorkspace.shared.open(url)
    }

    public func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @discardableResult
    public func execute(_ plan: LaunchPlan) -> Bool {
        switch plan {
        case let .openWithArguments(bundleID, arguments, newInstance):
            guard let appURL = applicationURL(bundleIdentifier: bundleID) else { return false }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = arguments
            // `open -na` spawns a second instance every launch, so only ask
            // for a new one when the app is not already running.
            configuration.createsNewApplicationInstance = newInstance
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            return true

        case let .appleScript(source, _):
            guard let script = NSAppleScript(source: source) else { return false }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            // A denied AppleEvents (Automation) TCC grant is the common real-
            // world cause here: Terminal.app is the only backend that needs
            // one, and when it is denied, `executeAndReturnError` reports an
            // error rather than throwing — nothing else signals the failure.
            return error == nil

        case let .openAndCopyToClipboard(bundleID, clipboard):
            copyToClipboard(clipboard)
            guard let appURL = applicationURL(bundleIdentifier: bundleID) else { return false }
            NSWorkspace.shared.openApplication(
                at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return true
        }
    }

    public func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Resolved through LaunchServices rather than path globbing: Terminal.app
    /// lives in /System/Applications/Utilities and users may install
    /// elsewhere.
    public func isInstalled(bundleIdentifier: String) -> Bool {
        applicationURL(bundleIdentifier: bundleIdentifier) != nil
    }

    private func applicationURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}
