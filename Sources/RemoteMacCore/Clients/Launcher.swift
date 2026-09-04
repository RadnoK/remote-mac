import AppKit
import Foundation

public protocol Launching: Sendable {
    func openScreenSharing(host: Host)
    func openFileSharing(host: Host)
    func copyToClipboard(_ text: String)
    func execute(_ plan: LaunchPlan)
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

    public func execute(_ plan: LaunchPlan) {
        switch plan {
        case let .openWithArguments(bundleID, arguments, newInstance):
            guard let appURL = applicationURL(bundleIdentifier: bundleID) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = arguments
            // `open -na` spawns a second instance every launch, so only ask
            // for a new one when the app is not already running.
            configuration.createsNewApplicationInstance = newInstance
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

        case let .appleScript(source, _):
            guard let script = NSAppleScript(source: source) else { return }
            var error: NSDictionary?
            script.executeAndReturnError(&error)

        case let .openAndCopyToClipboard(bundleID, clipboard):
            copyToClipboard(clipboard)
            guard let appURL = applicationURL(bundleIdentifier: bundleID) else { return }
            NSWorkspace.shared.openApplication(
                at: appURL, configuration: NSWorkspace.OpenConfiguration())
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
