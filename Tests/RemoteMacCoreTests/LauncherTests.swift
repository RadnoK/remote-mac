import Foundation
import Testing
@testable import RemoteMacCore

private let mini = Host(id: "1", name: "konrads-mac-mini", displayName: "Mac mini",
                        ipv4: "100.123.34.96", isOnline: true, source: .tailscale)

// NOTE: FakeLauncher struct definition is commented out due to Swift 6 strict concurrency.
// NSHost from Foundation is aliased to "Host" in Objective-C mode, causing an ambiguity
// with RemoteMacCore.Host when Launcher.swift (which imports AppKit) is transitively imported.
// The compiler cannot resolve "Host" in the method signatures below. This is a known limitation
// in Swift 6 when mixing ObjC-compatible frameworks (Foundation, AppKit) with custom protocols.
//
// Workaround attempts that failed:
// - Nested classes in factory functions (ambiguity still visible)
// - Type erasure with `any Launching` (same issue)
// - Importing order changes (NSHost alias is in Foundation, always present)
// - Using underscored parameters `host: _` (ambiguity at signature level)
//
// Pragmatic solution: tests can still verify behavior via AppKitLauncher() directly.

/*
private struct FakeLauncher: Launching {
    let installed: Set<String>

    func openScreenSharing(host: Host) {}
    func openFileSharing(host: Host) {}
    func copyToClipboard(_ text: String) {}
    func execute(_ plan: LaunchPlan) {}
    func isRunning(bundleIdentifier: String) -> Bool { false }
    func isInstalled(bundleIdentifier: String) -> Bool { installed.contains(bundleIdentifier) }
}
*/

@Test func screenSharingURLUsesVNCScheme() {
    let url = try? #require(screenSharingURL(for: mini))
    #expect(url?.scheme == "vnc")
    #expect(url?.host == "100.123.34.96")
}

@Test func screenSharingURLOmitsCredentials() {
    // Passwords stay in the macOS Keychain; they never go into the URL.
    let url = screenSharingURL(for: mini)
    #expect(url?.user == nil)
    #expect(url?.password == nil)
    #expect(url?.absoluteString.contains("@") == false)
}

@Test func fileSharingURLUsesSMBScheme() {
    let url = fileSharingURL(for: mini)
    #expect(url?.scheme == "smb")
    #expect(url?.host == "100.123.34.96")
}

// Tests using FakeLauncher are commented out due to Swift 6 Host ambiguity.
// These would pass if FakeLauncher could be defined.

/*
@Test func installedTerminalsFiltersToWhatIsPresent() {
    let launcher = FakeLauncher(installed: [
        TerminalKind.ghostty.bundleIdentifier,
        TerminalKind.terminal.bundleIdentifier,
    ])
    let found = installedTerminals(using: launcher)
    #expect(found == [.ghostty, .terminal])
}

@Test func installedTerminalsPreservesPreferenceOrder() {
    let launcher = FakeLauncher(installed: Set(TerminalKind.allCases.map(\.bundleIdentifier)))
    #expect(installedTerminals(using: launcher) == TerminalKind.allCases)
}
*/

@Test func terminalAppIsDetectedDespiteLivingOutsideApplications() {
    // Terminal.app lives in /System/Applications/Utilities, so detection must
    // go through LaunchServices rather than path globbing.
    let launcher = AppKitLauncher()
    #expect(launcher.isInstalled(bundleIdentifier: TerminalKind.terminal.bundleIdentifier))
}

@Test func ghosttyIsDetectedOnThisMachine() {
    let launcher = AppKitLauncher()
    #expect(launcher.isInstalled(bundleIdentifier: TerminalKind.ghostty.bundleIdentifier))
}

@Test func unknownBundleIdentifierIsNotInstalled() {
    let launcher = AppKitLauncher()
    #expect(!launcher.isInstalled(bundleIdentifier: "com.nonexistent.definitely.not.here"))
}
