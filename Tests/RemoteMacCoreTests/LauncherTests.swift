import Foundation
import Testing
@testable import RemoteMacCore

private let mini = Host(id: "1", name: "konrads-mac-mini", displayName: "Mac mini",
                        ipv4: "100.123.34.96", isOnline: true, source: .tailscale)

private struct FakeLauncher: Launching {
    let installed: Set<String>

    func openScreenSharing(host: RemoteMacCore.Host) {}
    func openFileSharing(host: RemoteMacCore.Host) {}
    func copyToClipboard(_ text: String) {}
    func execute(_ plan: LaunchPlan) -> Bool { true }
    func isRunning(bundleIdentifier: String) -> Bool { false }
    func isInstalled(bundleIdentifier: String) -> Bool { installed.contains(bundleIdentifier) }
}

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

/// `vnc://host` and `vnc://host:5900` are equivalent, so the default port
/// must stay implicit — otherwise every host's URL would grow a redundant
/// ":5900" the moment per-host ports shipped.
@Test func screenSharingURLOmitsTheDefaultPort() {
    #expect(mini.screenSharingPort == screenSharingPort)
    let url = screenSharingURL(for: mini)
    #expect(url?.absoluteString == "vnc://100.123.34.96")
    #expect(url?.port == nil)
}

/// A per-host override (`AppSettings.screenSharingPorts`, resolved onto
/// `Host` by `mergeHosts`) must actually reach the URL Screen Sharing opens
/// — otherwise the app would probe the custom port but still connect to
/// 5900.
@Test func screenSharingURLIncludesACustomPort() {
    let custom = Host(id: "1", name: "konrads-mac-mini", displayName: "Mac mini",
                      ipv4: "100.123.34.96", isOnline: true, source: .tailscale,
                      screenSharingPort: 5901)
    let url = screenSharingURL(for: custom)
    #expect(url?.port == 5901)
    #expect(url?.absoluteString == "vnc://100.123.34.96:5901")
}

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
