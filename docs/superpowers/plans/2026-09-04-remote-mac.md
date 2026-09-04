# RemoteMac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menu bar app that lists remote Macs by name from Tailscale and launches macOS Screen Sharing or an SSH session in the user's terminal of choice.

**Architecture:** SwiftPM executable assembled into a `.app` bundle by a shell script and signed with Developer ID. `MenuBarExtra` scene with `.window` style. Pure-logic parsing and command building are separated from I/O behind protocols so every unit is testable without network, subprocesses, or a running Tailscale daemon.

**Tech Stack:** Swift 6.3.3, swift-tools 6.2, `.swiftLanguageMode(.v6)`, SwiftUI `MenuBarExtra`, Network.framework (`NWConnection`), `swift-subprocess` 1.0.0, swift-testing (`Testing.framework`, in toolchain).

**Spec:** `docs/superpowers/specs/2026-09-04-remote-mac-design.md`

## Global Constraints

- Bundle identifier is exactly `io.eightlines.remotemac`. Never change it — TCC and Keychain permission stability depends on it.
- Signing identity is resolved by SHA-1, never by name. Two certs share the name `Developer ID Application: Apprife Konrad Alfaro (7S3F9767BM)`, so `codesign --sign "<name>"` fails with `ambiguous`. Valid SHA-1: `425A48BCECBD18E1281D14C9A0E6D6937547B090`.
- Never pass `--deep` to `codesign` — deprecated for signing since macOS 13.
- The app must NOT be sandboxed. No `com.apple.security.app-sandbox` entitlement, ever. Tailscale is itself sandboxed and hangs forever in `_libsecinit_appsandbox` when spawned from a sandboxed parent.
- Package platform floor: `.macOS(.v15)`. `LSMinimumSystemVersion` is `15.0`. The SDK is 26.5, so any API newer than macOS 15 needs `if #available`.
- Swift language mode is `.v6` (strict concurrency) on every target.
- Tailscale CLI path: `/Applications/Tailscale.app/Contents/MacOS/Tailscale`. `/usr/local/bin/tailscale` does not exist on this machine.
- Every Tailscale invocation sets `TAILSCALE_BE_CLI=1` (value-sensitive; `0` fails) merged into `ProcessInfo.processInfo.environment`, never replacing it.
- Every subprocess and every network probe has a hard external timeout. Tailscale exits 0 on failure and can hang indefinitely; `NWConnection` emits no state at all for unreachable hosts.
- Default SSH username is `radnok`, overridable per host.
- No passwords, keys, or secrets in `settings.json`.
- User-facing strings are Polish.

---

### Task 1: Package skeleton and build script

**Files:**
- Create: `Package.swift`
- Create: `Sources/RemoteMac/main.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`
- Test: `Tests/RemoteMacCoreTests/PackageSmokeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: two targets — library `RemoteMacCore` (all logic, testable) and executable `RemoteMac` (SwiftUI app, depends on `RemoteMacCore`). Test target `RemoteMacCoreTests` imports `RemoteMacCore`.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/PackageSmokeTests.swift`:

```swift
import Testing
@testable import RemoteMacCore

@Test func packageExposesVersion() {
    #expect(RemoteMacCore.version == "1.0")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test 2>&1 | tail -20`
Expected: FAIL — no `Package.swift` exists yet, so the build errors out.

- [ ] **Step 3: Write minimal implementation**

Create `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RemoteMac",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "RemoteMacCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "RemoteMac",
            dependencies: ["RemoteMacCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RemoteMacCoreTests",
            dependencies: ["RemoteMacCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

Create `Sources/RemoteMacCore/Version.swift`:

```swift
public enum RemoteMacCore {
    public static let version = "1.0"
}
```

Create `Sources/RemoteMac/main.swift`:

```swift
import RemoteMacCore

print("RemoteMac \(RemoteMacCore.version)")
```

Create `Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>RemoteMac</string>
    <key>CFBundleDisplayName</key>
    <string>RemoteMac</string>
    <key>CFBundleExecutable</key>
    <string>RemoteMac</string>
    <key>CFBundleIdentifier</key>
    <string>io.eightlines.remotemac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>RemoteMac otwiera sesje SSH w wybranym przez Ciebie terminalu.</string>
</dict>
</plist>
```

Create `Scripts/build-app.sh` (make it executable with `chmod +x`):

```bash
#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$HOME/Applications/RemoteMac.app}"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/RemoteMac" "$APP/Contents/MacOS/RemoteMac"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

CERT_SHA=$(security find-identity -v -p codesigning \
  | awk '/Developer ID Application.*7S3F9767BM/{print $2; exit}')

if [ -z "$CERT_SHA" ]; then
  echo "BŁĄD: nie znaleziono certyfikatu Developer ID (Team 7S3F9767BM)." >&2
  exit 1
fi

codesign --force --options runtime \
  --sign "$CERT_SHA" \
  --identifier io.eightlines.remotemac \
  "$APP"

codesign --verify --strict "$APP"
echo "Zbudowano i podpisano: $APP"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test 2>&1 | tail -20`
Expected: PASS — 1 test passing.

Then verify the build script produces a signed bundle:

Run: `chmod +x Scripts/build-app.sh && ./Scripts/build-app.sh /tmp/RemoteMacTest.app && codesign -dv /tmp/RemoteMacTest.app 2>&1 | grep -E 'Identifier|TeamIdentifier'`
Expected: `Identifier=io.eightlines.remotemac` and `TeamIdentifier=7S3F9767BM`.

Clean up: `rm -rf /tmp/RemoteMacTest.app`

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Resources Scripts Tests
git commit -m "feat: package skeleton with signed .app build script"
```

---

### Task 2: Host model and Tailscale JSON parsing

**Files:**
- Create: `Sources/RemoteMacCore/Model/Host.swift`
- Create: `Sources/RemoteMacCore/Clients/TailscaleStatus.swift`
- Test: `Tests/RemoteMacCoreTests/TailscaleStatusTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct Host: Sendable, Identifiable, Hashable` with `id: String`, `name: String`, `displayName: String`, `ipv4: String`, `isOnline: Bool`, `source: HostSource`, `sshUsername: String?`
  - `public enum HostSource: String, Sendable, Codable { case tailscale, manual }`
  - `public enum TailscaleParseError: Error, Equatable { case guiLaunchFailure, notRunning(String), malformed }`
  - `public func parseTailscaleStatus(_ data: Data) throws -> [Host]` — returns Macs only (`Self` + peers), sorted by `displayName`.

The parser must handle every trap documented in the spec. Real field shapes:
`Peer` is a dictionary keyed by `nodekey:<hex>`, `Self` is a sibling object not
contained in `Peer`, `DNSName` has a trailing dot, `Tags` is absent (not null)
for user devices, `LastSeen` is Go zero time when online, and `HostName` may
contain U+2019.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/TailscaleStatusTests.swift`:

```swift
import Foundation
import Testing
@testable import RemoteMacCore

/// Shaped after real output from `Tailscale status --json` on the target machine.
private let realisticJSON = """
{
  "Version": "1.102.3-t9329c3677-ga522f65e9",
  "BackendState": "Running",
  "TailscaleIPs": ["100.92.218.58"],
  "Self": {
    "ID": "self1",
    "PublicKey": "nodekey:aaa",
    "HostName": "Konrad's MacBook",
    "DNSName": "konrad-macbook-pro.tail1ee4df.ts.net.",
    "OS": "macOS",
    "TailscaleIPs": ["100.92.218.58", "fd7a:115c:a1e0::1"],
    "Online": true,
    "LastSeen": "0001-01-01T00:00:00Z"
  },
  "Peer": {
    "nodekey:bbb": {
      "ID": "peer1",
      "PublicKey": "nodekey:bbb",
      "HostName": "Konrad\\u2019s Mac mini",
      "DNSName": "konrads-mac-mini.tail1ee4df.ts.net.",
      "OS": "macOS",
      "TailscaleIPs": ["100.123.34.96", "fd7a:115c:a1e0::2"],
      "Online": true,
      "LastSeen": "0001-01-01T00:00:00Z"
    },
    "nodekey:ccc": {
      "ID": "peer2",
      "PublicKey": "nodekey:ccc",
      "HostName": "8lines-dev",
      "DNSName": "8lines-dev.tail1ee4df.ts.net.",
      "OS": "linux",
      "TailscaleIPs": ["100.84.209.51"],
      "Online": true,
      "LastSeen": "0001-01-01T00:00:00Z",
      "Tags": ["tag:server"]
    },
    "nodekey:ddd": {
      "ID": "peer3",
      "PublicKey": "nodekey:ddd",
      "HostName": "localhost",
      "DNSName": "konrad-iphone.tail1ee4df.ts.net.",
      "OS": "iOS",
      "TailscaleIPs": ["100.110.204.67"],
      "Online": true,
      "LastSeen": "0001-01-01T00:00:00Z"
    },
    "nodekey:eee": {
      "ID": "peer4",
      "PublicKey": "nodekey:eee",
      "HostName": "Konrad\\u2019s MacBook Pro",
      "DNSName": "konrads-macbook-pro.tail1ee4df.ts.net.",
      "OS": "macOS",
      "TailscaleIPs": ["100.108.216.101"],
      "Online": false,
      "LastSeen": "2026-01-21T21:02:00.1Z"
    }
  }
}
"""

@Test func parsesOnlyMacsIncludingSelf() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    // 3 Macs: Self + mini + MacBook Pro. Linux and iOS excluded.
    #expect(hosts.count == 3)
    #expect(hosts.allSatisfy { !$0.name.isEmpty })
}

@Test func usesDNSNameFirstSegmentAsName() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    let names = Set(hosts.map(\.name))
    #expect(names == ["konrad-macbook-pro", "konrads-mac-mini", "konrads-macbook-pro"])
}

@Test func stripsTrailingDotAndNeverKeepsFQDN() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    #expect(hosts.allSatisfy { !$0.name.hasSuffix(".") })
    #expect(hosts.allSatisfy { !$0.name.contains("ts.net") })
}

@Test func preservesCurlyApostropheInDisplayName() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    let mini = try #require(hosts.first { $0.name == "konrads-mac-mini" })
    #expect(mini.displayName == "Konrad\u{2019}s Mac mini")
}

@Test func picksIPv4FromTailscaleIPs() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    let mini = try #require(hosts.first { $0.name == "konrads-mac-mini" })
    #expect(mini.ipv4 == "100.123.34.96")
    #expect(hosts.allSatisfy { !$0.ipv4.contains(":") })
}

@Test func readsOnlineFlag() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    let mbp = try #require(hosts.first { $0.name == "konrads-macbook-pro" })
    #expect(mbp.isOnline == false)
    let mini = try #require(hosts.first { $0.name == "konrads-mac-mini" })
    #expect(mini.isOnline == true)
}

@Test func selfIsIncludedEvenThoughAbsentFromPeerDictionary() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    #expect(hosts.contains { $0.name == "konrad-macbook-pro" })
}

@Test func toleratesMissingTagsKey() throws {
    // User-owned devices omit "Tags" entirely rather than sending null.
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    #expect(hosts.count == 3)
}

@Test func detectsGUILaunchFailureDespiteExitCodeZero() {
    let msg = "The Tailscale GUI failed to start: The operation couldn't be completed. (Tailscale.CLIError error 3.)"
    #expect(throws: TailscaleParseError.guiLaunchFailure) {
        try parseTailscaleStatus(Data(msg.utf8))
    }
}

@Test func emptyOutputIsMalformedNotEmptyList() {
    // A hung CLI returns zero bytes; that is "unknown", never "no hosts".
    #expect(throws: TailscaleParseError.malformed) {
        try parseTailscaleStatus(Data())
    }
}

@Test func reportsBackendStateWhenNotRunning() {
    let json = #"{"BackendState":"Stopped","Self":null,"Peer":null}"#
    #expect(throws: TailscaleParseError.notRunning("Stopped")) {
        try parseTailscaleStatus(Data(json.utf8))
    }
}

@Test func hostsAreSortedByDisplayName() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    #expect(hosts.map(\.displayName) == hosts.map(\.displayName).sorted())
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TailscaleStatusTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'parseTailscaleStatus' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Model/Host.swift`:

```swift
import Foundation

public enum HostSource: String, Sendable, Codable, Hashable {
    case tailscale
    case manual
}

public struct Host: Sendable, Identifiable, Hashable, Codable {
    /// Stable identity. For Tailscale hosts this is the node's public key;
    /// for manual hosts it is the user-supplied address.
    public let id: String
    /// DNS-safe short name, suitable for SSH. Never contains a trailing dot.
    public let name: String
    /// Human-facing label. May contain a typographic apostrophe (U+2019).
    public let displayName: String
    public let ipv4: String
    public let isOnline: Bool
    public let source: HostSource
    public var sshUsername: String?

    public init(
        id: String,
        name: String,
        displayName: String,
        ipv4: String,
        isOnline: Bool,
        source: HostSource,
        sshUsername: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.ipv4 = ipv4
        self.isOnline = isOnline
        self.source = source
        self.sshUsername = sshUsername
    }
}
```

Create `Sources/RemoteMacCore/Clients/TailscaleStatus.swift`:

```swift
import Foundation

public enum TailscaleParseError: Error, Equatable {
    /// The CLI tried to launch the GUI. Happens when TAILSCALE_BE_CLI is unset
    /// or set to a non-truthy value. Note the CLI still exits 0 in this case.
    case guiLaunchFailure
    /// The daemon is reachable but not serving, e.g. "Stopped" or "NeedsLogin".
    case notRunning(String)
    /// Empty or undecodable output. Treat as unknown state, never as "no hosts".
    case malformed
}

/// Mirrors the subset of `tailscale status --json` this app needs.
private struct StatusPayload: Decodable {
    let BackendState: String?
    let `Self`: Node?
    let Peer: [String: Node]?
}

private struct Node: Decodable {
    let PublicKey: String?
    let HostName: String?
    let DNSName: String?
    let OS: String?
    let TailscaleIPs: [String]?
    let Online: Bool?
    // `Tags` is intentionally omitted: the key is absent for user-owned
    // devices (not null), and we never read it.
}

/// The exact OS value Tailscale reports for Macs. Not "darwin", not "macos".
private let macOSIdentifier = "macOS"

public func parseTailscaleStatus(_ data: Data) throws -> [Host] {
    guard !data.isEmpty else { throw TailscaleParseError.malformed }

    // The CLI writes this error to stdout AND exits 0, so the output stream is
    // the only place it can be detected.
    if let text = String(data: data, encoding: .utf8),
       text.contains("The Tailscale GUI failed to start") {
        throw TailscaleParseError.guiLaunchFailure
    }

    guard let payload = try? JSONDecoder().decode(StatusPayload.self, from: data) else {
        throw TailscaleParseError.malformed
    }

    if let state = payload.BackendState, state != "Running" {
        throw TailscaleParseError.notRunning(state)
    }

    let nodes = [payload.`Self`].compactMap(\.self) + (payload.Peer?.values.map(\.self) ?? [])

    return nodes
        .filter { $0.OS == macOSIdentifier }
        .compactMap(makeHost)
        .sorted { $0.displayName < $1.displayName }
}

private func makeHost(_ node: Node) -> Host? {
    guard let ipv4 = node.TailscaleIPs?.first(where: { !$0.contains(":") }) else {
        return nil
    }
    guard let name = shortName(fromDNSName: node.DNSName) else { return nil }

    return Host(
        id: node.PublicKey ?? name,
        name: name,
        displayName: node.HostName.flatMap { $0 == "localhost" ? nil : $0 } ?? name,
        ipv4: ipv4,
        isOnline: node.Online ?? false,
        source: .tailscale
    )
}

/// `DNSName` arrives as an FQDN with a trailing dot
/// ("konrads-mac-mini.tail1ee4df.ts.net."). The first segment is the
/// DNS-safe short name; `HostName` is not usable here because it may contain
/// a typographic apostrophe and is "localhost" on iOS devices.
private func shortName(fromDNSName dnsName: String?) -> String? {
    guard let first = dnsName?.split(separator: ".").first, !first.isEmpty else {
        return nil
    }
    return String(first)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TailscaleStatusTests 2>&1 | tail -20`
Expected: PASS — 12 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Model/Host.swift Sources/RemoteMacCore/Clients/TailscaleStatus.swift Tests/RemoteMacCoreTests/TailscaleStatusTests.swift
git commit -m "feat: parse Tailscale status JSON into Mac hosts"
```

---

### Task 3: Terminal command building

**Files:**
- Create: `Sources/RemoteMacCore/Clients/TerminalKind.swift`
- Create: `Sources/RemoteMacCore/Clients/SSHCommand.swift`
- Test: `Tests/RemoteMacCoreTests/SSHCommandTests.swift`

**Interfaces:**
- Consumes: `Host` from Task 2.
- Produces:
  - `public enum TerminalKind: String, Sendable, Codable, CaseIterable` with cases `ghostty, iterm, terminal, warp, termius`, and `public var bundleIdentifier: String`, `public var displayName: String`
  - `public enum LaunchPlan: Sendable, Equatable` with cases `openWithArguments(bundleID: String, arguments: [String], newInstance: Bool)`, `appleScript(source: String, bundleID: String)`, `openAndCopyToClipboard(bundleID: String, clipboard: String)`
  - `public func sshCommandLine(user: String, host: String) -> String`
  - `public func launchPlan(for terminal: TerminalKind, user: String, host: String, isRunning: Bool) -> LaunchPlan`

Quoting differs per backend and this is a security boundary, not a cosmetic
detail: Ghostty's `-e` takes an argv array with no shell, while iTerm2 routes
the string through `/usr/bin/login … $SHELL -c`, making shell metacharacters in
a hostname an injection vector there.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/SSHCommandTests.swift`:

```swift
import Testing
@testable import RemoteMacCore

@Test func ghosttyPassesArgvWithoutShell() {
    let plan = launchPlan(for: .ghostty, user: "radnok", host: "100.123.34.96", isRunning: false)
    #expect(plan == .openWithArguments(
        bundleID: "com.mitchellh.ghostty",
        arguments: ["-e", "ssh", "radnok@100.123.34.96"],
        newInstance: true
    ))
}

@Test func itermUsesEqualsFormOnly() {
    // The space-separated form silently does nothing; only --command=X works.
    let plan = launchPlan(for: .iterm, user: "radnok", host: "100.123.34.96", isRunning: false)
    guard case let .openWithArguments(bundleID, arguments, _) = plan else {
        Issue.record("expected openWithArguments, got \(plan)")
        return
    }
    #expect(bundleID == "com.googlecode.iterm2")
    #expect(arguments.count == 1)
    #expect(arguments[0].hasPrefix("--command="))
    #expect(!arguments.contains("--command"))
}

@Test func itermSkipsNewInstanceWhenAlreadyRunning() {
    // `open -na iTerm` spawns a second iTerm process every time.
    let cold = launchPlan(for: .iterm, user: "radnok", host: "h", isRunning: false)
    let warm = launchPlan(for: .iterm, user: "radnok", host: "h", isRunning: true)
    guard case let .openWithArguments(_, _, coldNew) = cold,
          case let .openWithArguments(_, _, warmNew) = warm else {
        Issue.record("expected openWithArguments")
        return
    }
    #expect(coldNew == true)
    #expect(warmNew == false)
}

@Test func itermEscapesShellMetacharacters() {
    // iTerm re-parses the string via `login … $SHELL -c`, so metacharacters
    // in a hostname would otherwise execute.
    let plan = launchPlan(for: .iterm, user: "radnok", host: "h; touch /tmp/pwned", isRunning: false)
    guard case let .openWithArguments(_, arguments, _) = plan else {
        Issue.record("expected openWithArguments")
        return
    }
    let arg = arguments[0]
    #expect(!arg.contains("; touch"))
    #expect(arg.contains("\\;") || arg.contains("'"))
}

@Test func ghosttyDoesNotEscapeBecauseArgvNeedsNoQuoting() {
    // Ghostty takes an argv array directly, so the raw value is correct there.
    let plan = launchPlan(for: .ghostty, user: "radnok", host: "h;x", isRunning: false)
    guard case let .openWithArguments(_, arguments, _) = plan else {
        Issue.record("expected openWithArguments")
        return
    }
    // The raw value survives untouched because argv needs no quoting.
    #expect(arguments == ["-e", "ssh", "radnok@h;x"])
}

@Test func terminalUsesAppleScript() {
    let plan = launchPlan(for: .terminal, user: "radnok", host: "100.123.34.96", isRunning: false)
    guard case let .appleScript(source, bundleID) = plan else {
        Issue.record("expected appleScript, got \(plan)")
        return
    }
    #expect(bundleID == "com.apple.Terminal")
    #expect(source.contains("do script"))
    #expect(source.contains("ssh radnok@100.123.34.96"))
}

@Test func warpOpensAndCopiesBecauseItRefusesToSubmitInput() {
    // Warp Control deliberately provides no action that submits input.
    let plan = launchPlan(for: .warp, user: "radnok", host: "100.123.34.96", isRunning: false)
    #expect(plan == .openAndCopyToClipboard(
        bundleID: "dev.warp.Warp-Stable",
        clipboard: "ssh radnok@100.123.34.96"
    ))
}

@Test func sshCommandLineJoinsUserAndHost() {
    #expect(sshCommandLine(user: "radnok", host: "100.123.34.96") == "ssh radnok@100.123.34.96")
}

@Test func everyTerminalHasDistinctBundleIdentifier() {
    let ids = TerminalKind.allCases.map(\.bundleIdentifier)
    #expect(Set(ids).count == ids.count)
    #expect(!ids.contains(where: \.isEmpty))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SSHCommandTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'launchPlan' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Clients/TerminalKind.swift`:

```swift
import Foundation

public enum TerminalKind: String, Sendable, Codable, CaseIterable, Hashable {
    case ghostty
    case iterm
    case terminal
    case warp
    case termius

    public var bundleIdentifier: String {
        switch self {
        case .ghostty:  "com.mitchellh.ghostty"
        case .iterm:    "com.googlecode.iterm2"
        case .terminal: "com.apple.Terminal"
        case .warp:     "dev.warp.Warp-Stable"
        case .termius:  "com.termius.mac"
        }
    }

    public var displayName: String {
        switch self {
        case .ghostty:  "Ghostty"
        case .iterm:    "iTerm2"
        case .terminal: "Terminal"
        case .warp:     "Warp"
        case .termius:  "Termius"
        }
    }

    /// True when driving this terminal requires an AppleEvents (Automation)
    /// TCC grant. Only Terminal.app does.
    public var requiresAppleEvents: Bool {
        self == .terminal
    }
}
```

Create `Sources/RemoteMacCore/Clients/SSHCommand.swift`:

```swift
import Foundation

public enum LaunchPlan: Sendable, Equatable {
    /// `open [-n] -a <bundleID> --args <arguments>`
    case openWithArguments(bundleID: String, arguments: [String], newInstance: Bool)
    /// Requires an AppleEvents TCC grant.
    case appleScript(source: String, bundleID: String)
    /// Warp deliberately refuses to submit input, so the command goes to the
    /// clipboard and the user pastes it.
    case openAndCopyToClipboard(bundleID: String, clipboard: String)
}

public func sshCommandLine(user: String, host: String) -> String {
    "ssh \(user)@\(host)"
}

public func launchPlan(
    for terminal: TerminalKind,
    user: String,
    host: String,
    isRunning: Bool
) -> LaunchPlan {
    let destination = "\(user)@\(host)"

    switch terminal {
    case .ghostty:
        // `-e` takes an argv array and never goes through a shell, so the
        // destination needs no quoting.
        return .openWithArguments(
            bundleID: terminal.bundleIdentifier,
            arguments: ["-e", "ssh", destination],
            newInstance: !isRunning
        )

    case .iterm:
        // iTerm2 runs the string via `/usr/bin/login -fpq $USER $SHELL -c`,
        // so it must be shell-escaped. Only the `--command=X` form works;
        // `--command X` silently does nothing.
        let escaped = shellEscape("ssh \(destination)")
        return .openWithArguments(
            bundleID: terminal.bundleIdentifier,
            arguments: ["--command=\(escaped)"],
            newInstance: !isRunning
        )

    case .termius:
        return .openWithArguments(
            bundleID: terminal.bundleIdentifier,
            arguments: [destination],
            newInstance: !isRunning
        )

    case .terminal:
        let script = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscape(sshCommandLine(user: user, host: host)))"
        end tell
        """
        return .appleScript(source: script, bundleID: terminal.bundleIdentifier)

    case .warp:
        return .openAndCopyToClipboard(
            bundleID: terminal.bundleIdentifier,
            clipboard: sshCommandLine(user: user, host: host)
        )
    }
}

/// Wraps a string in single quotes for POSIX shells, escaping embedded quotes.
private func shellEscape(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}

/// Escapes backslashes and double quotes for embedding in an AppleScript
/// string literal.
private func appleScriptEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SSHCommandTests 2>&1 | tail -20`
Expected: PASS — 9 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Clients/TerminalKind.swift Sources/RemoteMacCore/Clients/SSHCommand.swift Tests/RemoteMacCoreTests/SSHCommandTests.swift
git commit -m "feat: build per-terminal SSH launch plans with correct escaping"
```

---

### Task 4: Host status state machine

**Files:**
- Create: `Sources/RemoteMacCore/Model/HostStatus.swift`
- Test: `Tests/RemoteMacCoreTests/HostStatusTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public enum ProbeOutcome: Sendable, Equatable { case listening, refused, timedOut, dnsFailure }`
  - `public enum HostStatus: Sendable, Equatable { case unknown, offline, online, screenSharingOff, notFound }`
  - `public var HostStatus.label: String` (Polish)
  - `public var HostStatus.isConnectable: Bool`
  - `public func resolveStatus(tailscaleOnline: Bool?, probe: ProbeOutcome?) -> HostStatus`

The distinction that matters: a hung Tailscale CLI (nil online flag) must
produce `.unknown`, never `.offline`. A menu bar app that reports a healthy
machine as disconnected is worse than one that admits it does not know.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/HostStatusTests.swift`:

```swift
import Testing
@testable import RemoteMacCore

@Test func listeningPortMeansOnline() {
    #expect(resolveStatus(tailscaleOnline: true, probe: .listening) == .online)
}

@Test func refusedPortMeansScreenSharingOff() {
    #expect(resolveStatus(tailscaleOnline: true, probe: .refused) == .screenSharingOff)
}

@Test func dnsFailureIsDistinctFromClosedPort() {
    // The user's remedy differs, so these must not collapse into one state.
    #expect(resolveStatus(tailscaleOnline: true, probe: .dnsFailure) == .notFound)
}

@Test func timeoutOnOnlineHostMeansOffline() {
    // Unreachable hosts emit no NWConnection state at all; the external
    // timeout is what surfaces a sleeping Mac.
    #expect(resolveStatus(tailscaleOnline: true, probe: .timedOut) == .offline)
}

@Test func unknownTailscaleStateIsNeverReportedAsOffline() {
    // A hung CLI returns no data while the daemon is perfectly healthy.
    #expect(resolveStatus(tailscaleOnline: nil, probe: nil) == .unknown)
}

@Test func probeStillWinsWhenTailscaleStateIsUnknown() {
    #expect(resolveStatus(tailscaleOnline: nil, probe: .listening) == .online)
}

@Test func tailscaleOfflineShortCircuitsWithoutProbe() {
    #expect(resolveStatus(tailscaleOnline: false, probe: nil) == .offline)
}

@Test func pendingProbeOnOnlineHostIsUnknown() {
    #expect(resolveStatus(tailscaleOnline: true, probe: nil) == .unknown)
}

@Test func onlyOnlineIsConnectable() {
    #expect(HostStatus.online.isConnectable)
    #expect(!HostStatus.offline.isConnectable)
    #expect(!HostStatus.unknown.isConnectable)
    #expect(!HostStatus.screenSharingOff.isConnectable)
    #expect(!HostStatus.notFound.isConnectable)
}

@Test func everyStatusHasNonEmptyPolishLabel() {
    let all: [HostStatus] = [.unknown, .offline, .online, .screenSharingOff, .notFound]
    #expect(all.allSatisfy { !$0.label.isEmpty })
    // Open port proves the service listens, not that login will succeed.
    #expect(HostStatus.online.label.contains("nasłuchuje"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HostStatusTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'resolveStatus' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Model/HostStatus.swift`:

```swift
import Foundation

public enum ProbeOutcome: Sendable, Equatable {
    /// TCP connect succeeded — Screen Sharing is serving.
    case listening
    /// Connection refused. NWConnection surfaces this as `.waiting`, not
    /// `.failed`, so it must be handled there or every closed port stalls.
    case refused
    /// No state emitted before the external deadline. This is what a sleeping
    /// or unreachable Mac looks like.
    case timedOut
    /// Name resolution failed (NWError -65554).
    case dnsFailure
}

public enum HostStatus: Sendable, Equatable {
    case unknown
    case offline
    case online
    case screenSharingOff
    case notFound

    public var label: String {
        switch self {
        case .unknown:          "Nieznany"
        case .offline:          "Offline"
        case .online:           "Screen Sharing nasłuchuje"
        case .screenSharingOff: "Screen Sharing wyłączony"
        case .notFound:         "Nie znaleziono hosta"
        }
    }

    /// An open port proves the service listens; it does not prove that
    /// authentication will succeed. The label is worded accordingly.
    public var isConnectable: Bool {
        self == .online
    }
}

public func resolveStatus(tailscaleOnline: Bool?, probe: ProbeOutcome?) -> HostStatus {
    switch probe {
    case .listening:   return .online
    case .refused:     return .screenSharingOff
    case .dnsFailure:  return .notFound
    case .timedOut:    return .offline
    case nil:
        switch tailscaleOnline {
        case false: return .offline
        // Both `true` (probe still pending) and `nil` (hung CLI) are unknown:
        // we have no evidence about the service yet.
        default:    return .unknown
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HostStatusTests 2>&1 | tail -20`
Expected: PASS — 10 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Model/HostStatus.swift Tests/RemoteMacCoreTests/HostStatusTests.swift
git commit -m "feat: host status state machine distinguishing unknown from offline"
```

---

### Task 5: Settings persistence

**Files:**
- Create: `Sources/RemoteMacCore/Model/AppSettings.swift`
- Create: `Sources/RemoteMacCore/Store/SettingsStore.swift`
- Test: `Tests/RemoteMacCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `TerminalKind` (Task 3), `Host`/`HostSource` (Task 2).
- Produces:
  - `public struct ManualHost: Sendable, Codable, Hashable` with `name: String`, `address: String`
  - `public struct AppSettings: Sendable, Codable, Equatable` with `terminal: TerminalKind`, `defaultSSHUsername: String`, `sshUsernames: [String: String]`, `manualHosts: [ManualHost]`, `hiddenHostIDs: [String]`, and `public static let `default`: AppSettings`
  - `public func sshUsername(for host: Host) -> String` on `AppSettings`
  - `public struct SettingsStore: Sendable` with `init(fileURL: URL)`, `func load() -> AppSettings`, `func save(_ settings: AppSettings) throws`, `static var defaultFileURL: URL`

JSON rather than `UserDefaults` because the file is meant to be hand-editable,
and `cfprefsd` overwrites external edits.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/SettingsStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import RemoteMacCore

private func makeTempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("remotemac-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("settings.json")
}

@Test func defaultsUseGhosttyAndLocalUsername() {
    let settings = AppSettings.default
    #expect(settings.terminal == .ghostty)
    #expect(settings.defaultSSHUsername == NSUserName())
}

@Test func loadReturnsDefaultsWhenFileMissing() {
    let store = SettingsStore(fileURL: makeTempURL())
    #expect(store.load() == AppSettings.default)
}

@Test func roundTripsThroughDisk() throws {
    let url = makeTempURL()
    let store = SettingsStore(fileURL: url)
    var settings = AppSettings.default
    settings.terminal = .iterm
    settings.defaultSSHUsername = "radnok"
    settings.manualHosts = [ManualHost(name: "biuro", address: "192.168.1.50")]
    settings.hiddenHostIDs = ["nodekey:aaa"]

    try store.save(settings)
    #expect(store.load() == settings)

    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func savedJSONIsHumanEditable() throws {
    let url = makeTempURL()
    let store = SettingsStore(fileURL: url)
    try store.save(AppSettings.default)

    let text = try String(contentsOf: url, encoding: .utf8)
    // Pretty-printed and key-sorted so hand edits and diffs stay sane.
    #expect(text.contains("\n"))
    #expect(text.contains("  "))
    let keys = ["defaultSSHUsername", "manualHosts", "terminal"]
    let positions = keys.compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
    #expect(positions.count == keys.count)
    #expect(positions == positions.sorted())

    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func saveCreatesMissingDirectories() throws {
    let url = makeTempURL()
    let store = SettingsStore(fileURL: url)
    try store.save(AppSettings.default)
    #expect(FileManager.default.fileExists(atPath: url.path))

    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func corruptFileFallsBackToDefaultsInsteadOfCrashing() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ this is not json".utf8).write(to: url)

    let store = SettingsStore(fileURL: url)
    #expect(store.load() == AppSettings.default)

    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func perHostUsernameOverridesDefault() {
    var settings = AppSettings.default
    settings.defaultSSHUsername = "radnok"
    settings.sshUsernames = ["nodekey:bbb": "admin"]

    let overridden = Host(id: "nodekey:bbb", name: "mini", displayName: "mini",
                          ipv4: "100.123.34.96", isOnline: true, source: .tailscale)
    let plain = Host(id: "nodekey:ccc", name: "mbp", displayName: "mbp",
                     ipv4: "100.108.216.101", isOnline: true, source: .tailscale)

    #expect(settings.sshUsername(for: overridden) == "admin")
    #expect(settings.sshUsername(for: plain) == "radnok")
}

@Test func defaultPathLivesUnderApplicationSupport() {
    let path = SettingsStore.defaultFileURL.path
    #expect(path.contains("Application Support/io.eightlines.remotemac"))
    #expect(path.hasSuffix("settings.json"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsStoreTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'AppSettings' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Model/AppSettings.swift`:

```swift
import Foundation

public struct ManualHost: Sendable, Codable, Hashable {
    public var name: String
    public var address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

public struct AppSettings: Sendable, Codable, Equatable {
    public var terminal: TerminalKind
    public var defaultSSHUsername: String
    /// Host id → username. Overrides `defaultSSHUsername`.
    public var sshUsernames: [String: String]
    public var manualHosts: [ManualHost]
    public var hiddenHostIDs: [String]

    public init(
        terminal: TerminalKind = .ghostty,
        defaultSSHUsername: String = NSUserName(),
        sshUsernames: [String: String] = [:],
        manualHosts: [ManualHost] = [],
        hiddenHostIDs: [String] = []
    ) {
        self.terminal = terminal
        self.defaultSSHUsername = defaultSSHUsername
        self.sshUsernames = sshUsernames
        self.manualHosts = manualHosts
        self.hiddenHostIDs = hiddenHostIDs
    }

    public static let `default` = AppSettings()

    public func sshUsername(for host: Host) -> String {
        sshUsernames[host.id] ?? defaultSSHUsername
    }
}
```

Create `Sources/RemoteMacCore/Store/SettingsStore.swift`:

```swift
import Foundation

/// Persists settings as pretty-printed, key-sorted JSON so the file stays
/// hand-editable. `UserDefaults` is unsuitable here: it is a binary plist
/// behind `cfprefsd`, which overwrites external edits.
public struct SettingsStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL = SettingsStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("io.eightlines.remotemac", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// Never throws: a missing or corrupt file falls back to defaults so the
    /// menu bar always comes up.
    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Atomic so a crash mid-write cannot truncate the file.
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsStoreTests 2>&1 | tail -20`
Expected: PASS — 8 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Model/AppSettings.swift Sources/RemoteMacCore/Store/SettingsStore.swift Tests/RemoteMacCoreTests/SettingsStoreTests.swift
git commit -m "feat: hand-editable JSON settings store"
```

---

### Task 6: Host merging and deduplication

**Files:**
- Create: `Sources/RemoteMacCore/Store/HostMerging.swift`
- Test: `Tests/RemoteMacCoreTests/HostMergingTests.swift`

**Interfaces:**
- Consumes: `Host`, `HostSource` (Task 2), `AppSettings`, `ManualHost` (Task 5).
- Produces: `public func mergeHosts(tailscale: [Host], settings: AppSettings) -> [Host]`

Manual hosts that duplicate a Tailscale IP are dropped in favour of the
Tailscale entry, which carries a live online flag.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/HostMergingTests.swift`:

```swift
import Testing
@testable import RemoteMacCore

private func tailscaleHost(_ name: String, _ ip: String, id: String? = nil) -> Host {
    Host(id: id ?? "nodekey:\(name)", name: name, displayName: name,
         ipv4: ip, isOnline: true, source: .tailscale)
}

@Test func manualHostsAppearAlongsideTailscaleHosts() {
    var settings = AppSettings.default
    settings.manualHosts = [ManualHost(name: "biuro", address: "192.168.1.50")]

    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.123.34.96")], settings: settings)
    #expect(merged.count == 2)
    #expect(merged.contains { $0.name == "biuro" && $0.source == .manual })
}

@Test func manualHostDuplicatingTailscaleIPIsDropped() {
    var settings = AppSettings.default
    settings.manualHosts = [ManualHost(name: "mini-recznie", address: "100.123.34.96")]

    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.123.34.96")], settings: settings)
    #expect(merged.count == 1)
    #expect(merged[0].source == .tailscale)
}

@Test func hiddenHostsAreExcluded() {
    var settings = AppSettings.default
    settings.hiddenHostIDs = ["nodekey:mini"]

    let merged = mergeHosts(
        tailscale: [tailscaleHost("mini", "100.123.34.96"), tailscaleHost("mbp", "100.108.216.101")],
        settings: settings
    )
    #expect(merged.map(\.name) == ["mbp"])
}

@Test func manualHostsCarryOfflineUntilProbed() {
    // Manual hosts have no Tailscale online flag, so they start unknown.
    var settings = AppSettings.default
    settings.manualHosts = [ManualHost(name: "biuro", address: "192.168.1.50")]

    let merged = mergeHosts(tailscale: [], settings: settings)
    #expect(merged[0].isOnline == false)
}

@Test func usernamesAreResolvedPerHost() {
    var settings = AppSettings.default
    settings.defaultSSHUsername = "radnok"
    settings.sshUsernames = ["nodekey:mini": "admin"]

    let merged = mergeHosts(
        tailscale: [tailscaleHost("mini", "100.123.34.96"), tailscaleHost("mbp", "100.108.216.101")],
        settings: settings
    )
    let mini = merged.first { $0.name == "mini" }
    let mbp = merged.first { $0.name == "mbp" }
    #expect(mini?.sshUsername == "admin")
    #expect(mbp?.sshUsername == "radnok")
}

@Test func resultIsSortedByDisplayName() {
    var settings = AppSettings.default
    settings.manualHosts = [ManualHost(name: "aaa", address: "10.0.0.1")]

    let merged = mergeHosts(tailscale: [tailscaleHost("zzz", "100.0.0.1")], settings: settings)
    #expect(merged.map(\.displayName) == ["aaa", "zzz"])
}

@Test func emptyInputsProduceEmptyList() {
    #expect(mergeHosts(tailscale: [], settings: .default).isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HostMergingTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'mergeHosts' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Store/HostMerging.swift`:

```swift
import Foundation

/// Combines auto-discovered Tailscale hosts with the user's manual entries,
/// applies hidden-host filtering, and resolves the SSH username for each.
/// A manual host whose address duplicates a Tailscale IP is dropped, because
/// the Tailscale entry carries a live online flag the manual one lacks.
public func mergeHosts(tailscale: [Host], settings: AppSettings) -> [Host] {
    let hidden = Set(settings.hiddenHostIDs)
    let tailscaleIPs = Set(tailscale.map(\.ipv4))

    let manual = settings.manualHosts
        .filter { !tailscaleIPs.contains($0.address) }
        .map { entry in
            Host(
                id: entry.address,
                name: entry.name,
                displayName: entry.name,
                ipv4: entry.address,
                isOnline: false,
                source: .manual
            )
        }

    return (tailscale + manual)
        .filter { !hidden.contains($0.id) }
        .map { host in
            var resolved = host
            resolved.sshUsername = settings.sshUsername(for: host)
            return resolved
        }
        .sorted { $0.displayName < $1.displayName }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HostMergingTests 2>&1 | tail -20`
Expected: PASS — 7 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Store/HostMerging.swift Tests/RemoteMacCoreTests/HostMergingTests.swift
git commit -m "feat: merge Tailscale and manual hosts with dedup and hiding"
```

---

### Task 7: Fuzzy search for the quick switcher

**Files:**
- Create: `Sources/RemoteMacCore/Store/HostSearch.swift`
- Test: `Tests/RemoteMacCoreTests/HostSearchTests.swift`

**Interfaces:**
- Consumes: `Host` (Task 2).
- Produces: `public func searchHosts(_ hosts: [Host], query: String) -> [Host]`

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/HostSearchTests.swift`:

```swift
import Testing
@testable import RemoteMacCore

private let hosts = [
    Host(id: "1", name: "konrads-mac-mini", displayName: "Konrad\u{2019}s Mac mini",
         ipv4: "100.123.34.96", isOnline: true, source: .tailscale),
    Host(id: "2", name: "konrads-macbook-pro", displayName: "Konrad\u{2019}s MacBook Pro",
         ipv4: "100.108.216.101", isOnline: true, source: .tailscale),
    Host(id: "3", name: "biuro", displayName: "biuro",
         ipv4: "192.168.1.50", isOnline: false, source: .manual),
]

@Test func emptyQueryReturnsEverythingUnchanged() {
    #expect(searchHosts(hosts, query: "") == hosts)
}

@Test func matchesSubsequenceNotJustPrefix() {
    let results = searchHosts(hosts, query: "mini")
    #expect(results.first?.name == "konrads-mac-mini")
}

@Test func matchesNonContiguousCharacters() {
    // "kmp" should reach "konrads-macbook-pro".
    let results = searchHosts(hosts, query: "kmp")
    #expect(results.contains { $0.name == "konrads-macbook-pro" })
}

@Test func isCaseInsensitive() {
    #expect(searchHosts(hosts, query: "MINI").first?.name == "konrads-mac-mini")
}

@Test func matchesAgainstIPAddress() {
    let results = searchHosts(hosts, query: "192.168")
    #expect(results.first?.name == "biuro")
}

@Test func ignoresTypographicApostropheInDisplayName() {
    // The user types a straight quote; the display name has U+2019.
    let results = searchHosts(hosts, query: "konrad's mac mini")
    #expect(results.first?.name == "konrads-mac-mini")
}

@Test func nonMatchingQueryReturnsNothing() {
    #expect(searchHosts(hosts, query: "zzzzz").isEmpty)
}

@Test func shorterMatchesRankHigher() {
    // "mac" appears in both Macs; the tighter match should come first.
    let results = searchHosts(hosts, query: "mac")
    #expect(results.count == 2)
    #expect(results[0].name == "konrads-mac-mini")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HostSearchTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'searchHosts' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Store/HostSearch.swift`:

```swift
import Foundation

/// Subsequence match over name, display name and IP. Returns hosts ranked by
/// how tightly the query matched — a smaller span between the first and last
/// matched character ranks higher.
public func searchHosts(_ hosts: [Host], query: String) -> [Host] {
    let needle = normalize(query)
    guard !needle.isEmpty else { return hosts }

    return hosts
        .compactMap { host -> (host: Host, score: Int)? in
            let candidates = [host.name, host.displayName, host.ipv4].map(normalize)
            guard let best = candidates.compactMap({ matchSpan(needle: needle, haystack: $0) }).min() else {
                return nil
            }
            return (host, best)
        }
        .sorted { ($0.score, $0.host.displayName) < ($1.score, $1.host.displayName) }
        .map(\.host)
}

/// Lowercases and folds the typographic apostrophe to a straight one, so a
/// query typed with a plain quote matches "Konrad’s Mac mini".
private func normalize(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\u{2019}", with: "'")
        .lowercased()
}

/// Returns the number of characters spanned while matching `needle` as a
/// subsequence of `haystack`, or nil when it does not match. Spaces in the
/// needle are ignored so "konrad's mac mini" matches "konrads-mac-mini".
private func matchSpan(needle: String, haystack: String) -> Int? {
    let target = Array(haystack)
    var index = 0
    var first: Int?
    var last = 0

    for character in needle where character != " " {
        var found = false
        while index < target.count {
            let current = target[index]
            index += 1
            if current == character {
                if first == nil { first = index - 1 }
                last = index - 1
                found = true
                break
            }
        }
        if !found { return nil }
    }

    guard let start = first else { return 0 }
    return last - start
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HostSearchTests 2>&1 | tail -20`
Expected: PASS — 8 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Store/HostSearch.swift Tests/RemoteMacCoreTests/HostSearchTests.swift
git commit -m "feat: fuzzy host search for quick switcher"
```

---

### Task 8: Tailscale client with hard timeout

**Files:**
- Create: `Sources/RemoteMacCore/Clients/CommandRunner.swift`
- Create: `Sources/RemoteMacCore/Clients/TailscaleClient.swift`
- Modify: `Package.swift` (add `swift-subprocess` dependency)
- Test: `Tests/RemoteMacCoreTests/TailscaleClientTests.swift`

**Interfaces:**
- Consumes: `parseTailscaleStatus`, `TailscaleParseError` (Task 2), `Host` (Task 2).
- Produces:
  - `public protocol CommandRunning: Sendable { func run(executable: String, arguments: [String], environment: [String: String], timeout: Duration) async throws -> Data }`
  - `public struct SubprocessRunner: CommandRunning, Sendable`
  - `public enum CommandError: Error, Equatable { case timedOut, notFound }`
  - `public struct TailscaleClient: Sendable` with `init(runner: CommandRunning, executablePath: String?)`, `func fetchMacs() async throws -> [Host]`, `static var resolvedExecutablePath: String?`

`swift-subprocess` rather than Foundation `Process` because the naive
`waitUntilExit()` + `readDataToEndOfFile()` pattern deadlocks past the ~64 KB
pipe buffer.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/TailscaleClientTests.swift`:

```swift
import Foundation
import Testing
@testable import RemoteMacCore

private struct StubRunner: CommandRunning {
    let result: Result<Data, CommandError>
    let recorder: Recorder?

    final class Recorder: @unchecked Sendable {
        var environment: [String: String] = [:]
        var executable = ""
        var arguments: [String] = []
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> Data {
        recorder?.executable = executable
        recorder?.arguments = arguments
        recorder?.environment = environment
        return try result.get()
    }
}

private let macOnlyJSON = """
{"BackendState":"Running",
 "Self":{"PublicKey":"nodekey:aaa","HostName":"Mini","DNSName":"mini.ts.net.",
         "OS":"macOS","TailscaleIPs":["100.1.1.1"],"Online":true},
 "Peer":{}}
"""

@Test func passesBeCLIEnvironmentVariableSetToOne() async throws {
    let recorder = StubRunner.Recorder()
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data(macOnlyJSON.utf8)), recorder: recorder),
        executablePath: "/fake/Tailscale"
    )
    _ = try await client.fetchMacs()
    // The variable is value-sensitive: "0" fails exactly like an unset value.
    #expect(recorder.environment["TAILSCALE_BE_CLI"] == "1")
}

@Test func inheritsAmbientEnvironmentRatherThanReplacingIt() async throws {
    let recorder = StubRunner.Recorder()
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data(macOnlyJSON.utf8)), recorder: recorder),
        executablePath: "/fake/Tailscale"
    )
    _ = try await client.fetchMacs()
    // Replacing the environment wholesale is `env -i` plus one variable.
    #expect(recorder.environment.count > 1)
    #expect(recorder.environment["PATH"] != nil)
}

@Test func requestsStatusAsJSON() async throws {
    let recorder = StubRunner.Recorder()
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data(macOnlyJSON.utf8)), recorder: recorder),
        executablePath: "/fake/Tailscale"
    )
    _ = try await client.fetchMacs()
    #expect(recorder.arguments == ["status", "--json"])
    #expect(recorder.executable == "/fake/Tailscale")
}

@Test func returnsParsedHosts() async throws {
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data(macOnlyJSON.utf8)), recorder: nil),
        executablePath: "/fake/Tailscale"
    )
    let hosts = try await client.fetchMacs()
    #expect(hosts.map(\.name) == ["mini"])
}

@Test func timeoutSurfacesAsCommandErrorNotEmptyList() async {
    let client = TailscaleClient(
        runner: StubRunner(result: .failure(.timedOut), recorder: nil),
        executablePath: "/fake/Tailscale"
    )
    await #expect(throws: CommandError.timedOut) {
        _ = try await client.fetchMacs()
    }
}

@Test func guiFailureOutputSurfacesAsParseError() async {
    let text = "The Tailscale GUI failed to start: (Tailscale.CLIError error 3.)"
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data(text.utf8)), recorder: nil),
        executablePath: "/fake/Tailscale"
    )
    await #expect(throws: TailscaleParseError.guiLaunchFailure) {
        _ = try await client.fetchMacs()
    }
}

@Test func missingExecutableThrowsNotFound() async {
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data()), recorder: nil),
        executablePath: nil
    )
    await #expect(throws: CommandError.notFound) {
        _ = try await client.fetchMacs()
    }
}

@Test func resolvesRealTailscalePathOnThisMachine() {
    // The App Store build ships the CLI inside the bundle; there is no
    // /usr/local/bin/tailscale on this machine.
    let path = TailscaleClient.resolvedExecutablePath
    if let path {
        #expect(FileManager.default.isExecutableFile(atPath: path))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TailscaleClientTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'TailscaleClient' in scope`.

- [ ] **Step 3: Write minimal implementation**

Modify `Package.swift` — add the dependency and wire it into `RemoteMacCore`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RemoteMac",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "RemoteMacCore",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "RemoteMac",
            dependencies: ["RemoteMacCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RemoteMacCoreTests",
            dependencies: ["RemoteMacCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

Create `Sources/RemoteMacCore/Clients/CommandRunner.swift`:

```swift
import Foundation
import Subprocess

public enum CommandError: Error, Equatable {
    case timedOut
    case notFound
}

public protocol CommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> Data
}

/// Runs subprocesses via `swift-subprocess`, which drains pipes concurrently.
/// Foundation's `Process` with `waitUntilExit()` + `readDataToEndOfFile()`
/// deadlocks once output exceeds the ~64 KB pipe buffer.
public struct SubprocessRunner: CommandRunning, Sendable {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CommandError.notFound
        }

        // The external deadline is mandatory: the Tailscale CLI can hang
        // indefinitely while the daemon stays healthy.
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                let result = try await Subprocess.run(
                    .path(FilePath(executable)),
                    arguments: Arguments(arguments),
                    environment: .custom(Environment(environment)),
                    output: .data(limit: 4 * 1024 * 1024),
                    error: .discarded
                )
                return result.standardOutput
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CommandError.timedOut
            }

            guard let first = try await group.next() else {
                throw CommandError.timedOut
            }
            group.cancelAll()
            return first
        }
    }
}
```

Note: if the `Subprocess.run` signature in the resolved 1.0.0 release differs
from the call above, adjust the call to match the package's API while keeping
the timeout race and the `CommandRunning` signature unchanged — those are what
the tests and callers depend on.

Create `Sources/RemoteMacCore/Clients/TailscaleClient.swift`:

```swift
import Foundation

public struct TailscaleClient: Sendable {
    private let runner: CommandRunning
    private let executablePath: String?
    private let timeout: Duration

    public init(
        runner: CommandRunning = SubprocessRunner(),
        executablePath: String? = TailscaleClient.resolvedExecutablePath,
        timeout: Duration = .seconds(5)
    ) {
        self.runner = runner
        self.executablePath = executablePath
        self.timeout = timeout
    }

    /// Candidate locations, most likely first. The App Store build ships the
    /// CLI inside the bundle and installs no symlink, so the bundle path is
    /// the one that actually exists on the target machine.
    private static let candidatePaths = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/bin/tailscale",
    ]

    public static var resolvedExecutablePath: String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func fetchMacs() async throws -> [Host] {
        guard let executablePath else { throw CommandError.notFound }

        // Merge rather than replace: assigning a fresh dictionary is `env -i`
        // plus one variable, which is fragile.
        var environment = ProcessInfo.processInfo.environment
        environment["TAILSCALE_BE_CLI"] = "1"

        let data = try await runner.run(
            executable: executablePath,
            arguments: ["status", "--json"],
            environment: environment,
            timeout: timeout
        )
        return try parseTailscaleStatus(data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TailscaleClientTests 2>&1 | tail -30`
Expected: PASS — 8 tests passing.

Then confirm it works against the real daemon:

Run: `swift run RemoteMac 2>&1 | head -20` — after Task 9 wires a debug print, or verify manually with a scratch snippet. If `swift-subprocess`'s API differs from the snippet, fix the call site now.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved Sources/RemoteMacCore/Clients/CommandRunner.swift Sources/RemoteMacCore/Clients/TailscaleClient.swift Tests/RemoteMacCoreTests/TailscaleClientTests.swift
git commit -m "feat: Tailscale client with mandatory timeout and BE_CLI env"
```

---

### Task 9: TCP probe for Screen Sharing

**Files:**
- Create: `Sources/RemoteMacCore/Clients/PortProbe.swift`
- Test: `Tests/RemoteMacCoreTests/PortProbeTests.swift`

**Interfaces:**
- Consumes: `ProbeOutcome` (Task 4).
- Produces:
  - `public protocol PortProbing: Sendable { func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome }`
  - `public struct NetworkPortProbe: PortProbing, Sendable`
  - `public let screenSharingPort: UInt16 = 5900`

Two traps, both mandatory: `NWConnection` reports connection-refused as
`.waiting` rather than `.failed`, and an unreachable host emits no state at
all after `.preparing`, so the external timeout carries that entire case.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/PortProbeTests.swift`:

```swift
import Foundation
import Testing
@testable import RemoteMacCore

@Test func screenSharingPortIs5900() {
    #expect(screenSharingPort == 5900)
}

@Test func refusedPortReturnsQuicklyNotAfterFullTimeout() async {
    // NWConnection surfaces "connection refused" as .waiting. Without
    // handling that state this stalls for the whole timeout.
    let probe = NetworkPortProbe()
    let clock = ContinuousClock()
    let start = clock.now
    // Port 1 on localhost is closed but reachable, so it is refused immediately.
    let outcome = await probe.probe(host: "127.0.0.1", port: 1, timeout: .seconds(3))
    let elapsed = clock.now - start

    #expect(outcome == .refused)
    #expect(elapsed < .seconds(1))
}

@Test func unroutableAddressTimesOutAndDoesNotHangForever() async {
    // Unreachable hosts emit no state after .preparing, so only the external
    // deadline ends this.
    let probe = NetworkPortProbe()
    let clock = ContinuousClock()
    let start = clock.now
    let outcome = await probe.probe(host: "192.0.2.1", port: 5900, timeout: .milliseconds(600))
    let elapsed = clock.now - start

    #expect(outcome == .timedOut)
    #expect(elapsed < .seconds(3))
}

@Test func unresolvableNameIsDNSFailureNotRefused() async {
    // The user's remedy differs between "port shut" and "name does not resolve".
    let probe = NetworkPortProbe()
    let outcome = await probe.probe(
        host: "nonexistent-host-\(UUID().uuidString).invalid",
        port: 5900,
        timeout: .seconds(3)
    )
    #expect(outcome == .dnsFailure)
}

@Test func listeningPortIsDetected() async throws {
    // Bind an ephemeral listener and confirm the probe sees it.
    let listener = try NWListener(using: .tcp, on: .any)
    listener.newConnectionHandler = { $0.cancel() }
    listener.start(queue: .global())
    defer { listener.cancel() }

    var port: UInt16?
    for _ in 0..<50 {
        if let value = listener.port?.rawValue { port = value; break }
        try await Task.sleep(for: .milliseconds(20))
    }
    let boundPort = try #require(port)

    let outcome = await NetworkPortProbe().probe(
        host: "127.0.0.1", port: boundPort, timeout: .seconds(3))
    #expect(outcome == .listening)
}
```

Add `import Network` at the top of the test file alongside the other imports.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PortProbeTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'NetworkPortProbe' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Clients/PortProbe.swift`:

```swift
import Foundation
import Network

public let screenSharingPort: UInt16 = 5900

public protocol PortProbing: Sendable {
    func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome
}

/// TCP reachability check via Network.framework.
///
/// Two behaviours drive this implementation:
/// 1. A refused connection arrives as `.waiting`, never `.failed`. Without
///    treating `.waiting` as closed, every shut port stalls for the full
///    timeout (2 s instead of 8 ms).
/// 2. An unreachable host emits no state at all after `.preparing`. Handling
///    `.waiting` does not cover it; only the external deadline does.
public struct NetworkPortProbe: PortProbing, Sendable {
    public init() {}

    public func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return .timedOut }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp
        )

        let outcome = await withTaskGroup(of: ProbeOutcome?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let resumed = OSAllocatedUnfairLock(initialState: false)

                    @Sendable func finish(_ result: ProbeOutcome) {
                        let alreadyResumed = resumed.withLock { state -> Bool in
                            if state { return true }
                            state = true
                            return false
                        }
                        guard !alreadyResumed else { return }
                        continuation.resume(returning: result)
                    }

                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            finish(.listening)
                        case let .waiting(error):
                            finish(classify(error))
                        case let .failed(error):
                            finish(classify(error))
                        case .cancelled:
                            finish(.timedOut)
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global())
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .timedOut
        }

        connection.cancel()
        return outcome
    }
}

/// Distinguishes a shut port from a name that does not resolve, because the
/// user's remedy differs.
private func classify(_ error: NWError) -> ProbeOutcome {
    switch error {
    case let .posix(code) where code == .ECONNREFUSED:
        return .refused
    case let .dns(code) where code == kDNSServiceErr_NoSuchRecord:
        return .dnsFailure
    default:
        return .refused
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PortProbeTests 2>&1 | tail -20`
Expected: PASS — 5 tests passing.

Verify against the real Macs:

Run: `nc -z -G 2 100.123.34.96 5900 && echo "mini: otwarty"`
Expected: `mini: otwarty` — sanity check that the probe target is real.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Clients/PortProbe.swift Tests/RemoteMacCoreTests/PortProbeTests.swift
git commit -m "feat: TCP probe handling .waiting refusals and unreachable hosts"
```

---

### Task 10: Launcher for Screen Sharing, terminals and Finder

**Files:**
- Create: `Sources/RemoteMacCore/Clients/Launcher.swift`
- Test: `Tests/RemoteMacCoreTests/LauncherTests.swift`

**Interfaces:**
- Consumes: `Host` (Task 2), `TerminalKind`, `LaunchPlan`, `launchPlan` (Task 3).
- Produces:
  - `public protocol Launching: Sendable { func openScreenSharing(host: Host) ; func openFileSharing(host: Host) ; func copyToClipboard(_ text: String) ; func execute(_ plan: LaunchPlan) ; func isRunning(bundleIdentifier: String) -> Bool ; func isInstalled(bundleIdentifier: String) -> Bool }`
  - `public struct AppKitLauncher: Launching, Sendable`
  - `public func screenSharingURL(for host: Host) -> URL?`
  - `public func fileSharingURL(for host: Host) -> URL?`
  - `public func installedTerminals(using launcher: Launching) -> [TerminalKind]`

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/LauncherTests.swift`:

```swift
import Foundation
import Testing
@testable import RemoteMacCore

private let mini = Host(id: "1", name: "konrads-mac-mini", displayName: "Mac mini",
                        ipv4: "100.123.34.96", isOnline: true, source: .tailscale)

private struct FakeLauncher: Launching {
    let installed: Set<String>

    func openScreenSharing(host: Host) {}
    func openFileSharing(host: Host) {}
    func copyToClipboard(_ text: String) {}
    func execute(_ plan: LaunchPlan) {}
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LauncherTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'screenSharingURL' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Clients/Launcher.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LauncherTests 2>&1 | tail -20`
Expected: PASS — 8 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Clients/Launcher.swift Tests/RemoteMacCoreTests/LauncherTests.swift
git commit -m "feat: launcher for Screen Sharing, terminals and file sharing"
```

---

### Task 11: Host store tying it together

**Files:**
- Create: `Sources/RemoteMacCore/Store/HostStore.swift`
- Test: `Tests/RemoteMacCoreTests/HostStoreTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–10.
- Produces:
  - `public struct HostEntry: Sendable, Identifiable, Equatable` with `host: Host`, `status: HostStatus`, `id: String`
  - `@MainActor @Observable public final class HostStore` with `init(tailscale: TailscaleClient, probe: PortProbing, settingsStore: SettingsStore, launcher: Launching)`, `var entries: [HostEntry]`, `var settings: AppSettings`, `var tailscaleError: String?`, `func refresh() async`, `func connect(to:)`, `func openSSH(to:)`, `func openFiles(for:)`, `func copyAddress(of:)`

Every host probes independently so one sleeping Mac cannot block the menu.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/HostStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import RemoteMacCore

private struct StubRunner: CommandRunning {
    let json: String
    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        Data(json.utf8)
    }
}

private struct FailingRunner: CommandRunning {
    let error: CommandError
    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        throw error
    }
}

private struct StubProbe: PortProbing {
    let outcomes: [String: ProbeOutcome]
    func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome {
        outcomes[host] ?? .timedOut
    }
}

private struct SlowProbe: PortProbing {
    let outcomes: [String: ProbeOutcome]
    func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome {
        if outcomes[host] == nil { try? await Task.sleep(for: .milliseconds(400)) }
        return outcomes[host] ?? .timedOut
    }
}

private struct NoopLauncher: Launching {
    func openScreenSharing(host: Host) {}
    func openFileSharing(host: Host) {}
    func copyToClipboard(_ text: String) {}
    func execute(_ plan: LaunchPlan) {}
    func isRunning(bundleIdentifier: String) -> Bool { false }
    func isInstalled(bundleIdentifier: String) -> Bool { true }
}

private let twoMacsJSON = """
{"BackendState":"Running",
 "Self":{"PublicKey":"nodekey:aaa","HostName":"Mini","DNSName":"mini.ts.net.",
         "OS":"macOS","TailscaleIPs":["100.123.34.96"],"Online":true},
 "Peer":{"nodekey:bbb":{"PublicKey":"nodekey:bbb","HostName":"MBP",
         "DNSName":"mbp.ts.net.","OS":"macOS","TailscaleIPs":["100.108.216.101"],
         "Online":true}}}
"""

private func makeStore(
    runner: CommandRunning,
    probe: PortProbing
) -> HostStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("remotemac-store-\(UUID().uuidString)")
        .appendingPathComponent("settings.json")
    return HostStore(
        tailscale: TailscaleClient(runner: runner, executablePath: "/fake/Tailscale"),
        probe: probe,
        settingsStore: SettingsStore(fileURL: url),
        launcher: NoopLauncher()
    )
}

@MainActor
@Test func refreshPopulatesEntriesWithResolvedStatus() async {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [
            "100.123.34.96": .listening,
            "100.108.216.101": .refused,
        ])
    )
    await store.refresh()

    #expect(store.entries.count == 2)
    let mini = store.entries.first { $0.host.name == "mini" }
    let mbp = store.entries.first { $0.host.name == "mbp" }
    #expect(mini?.status == .online)
    #expect(mbp?.status == .screenSharingOff)
    #expect(store.tailscaleError == nil)
}

@MainActor
@Test func tailscaleFailureSurfacesMessageAndKeepsManualHosts() async {
    let store = makeStore(
        runner: FailingRunner(error: .timedOut),
        probe: StubProbe(outcomes: ["192.168.1.50": .listening])
    )
    store.settings.manualHosts = [ManualHost(name: "biuro", address: "192.168.1.50")]
    await store.refresh()

    #expect(store.tailscaleError != nil)
    #expect(store.entries.map(\.host.name) == ["biuro"])
    #expect(store.entries[0].status == .online)
}

@MainActor
@Test func hungTailscaleShowsUnknownNotOffline() async {
    let store = makeStore(
        runner: FailingRunner(error: .timedOut),
        probe: StubProbe(outcomes: [:])
    )
    await store.refresh()
    #expect(store.tailscaleError != nil)
    // No hosts is a distinct condition from "all hosts offline".
    #expect(store.entries.isEmpty)
}

@MainActor
@Test func oneSlowHostDoesNotBlockTheOthers() async {
    // Probes run concurrently, so total time tracks the slowest single probe,
    // not their sum.
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: SlowProbe(outcomes: ["100.123.34.96": .listening])
    )
    let clock = ContinuousClock()
    let start = clock.now
    await store.refresh()
    let elapsed = clock.now - start

    #expect(store.entries.count == 2)
    #expect(elapsed < .milliseconds(900))
}

@MainActor
@Test func hiddenHostsDoNotAppear() async {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:])
    )
    store.settings.hiddenHostIDs = ["nodekey:aaa"]
    await store.refresh()
    #expect(store.entries.map(\.host.name) == ["mbp"])
}

@MainActor
@Test func entriesAreSortedByDisplayName() async {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:])
    )
    await store.refresh()
    #expect(store.entries.map(\.host.displayName) == store.entries.map(\.host.displayName).sorted())
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HostStoreTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'HostStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Store/HostStore.swift`:

```swift
import Foundation
import Observation

public struct HostEntry: Sendable, Identifiable, Equatable {
    public let host: Host
    public let status: HostStatus
    public var id: String { host.id }

    public init(host: Host, status: HostStatus) {
        self.host = host
        self.status = status
    }
}

@MainActor
@Observable
public final class HostStore {
    public private(set) var entries: [HostEntry] = []
    public private(set) var tailscaleError: String?
    public var settings: AppSettings {
        didSet { try? settingsStore.save(settings) }
    }

    private let tailscale: TailscaleClient
    private let probe: PortProbing
    private let settingsStore: SettingsStore
    private let launcher: Launching

    public init(
        tailscale: TailscaleClient = TailscaleClient(),
        probe: PortProbing = NetworkPortProbe(),
        settingsStore: SettingsStore = SettingsStore(),
        launcher: Launching = AppKitLauncher()
    ) {
        self.tailscale = tailscale
        self.probe = probe
        self.settingsStore = settingsStore
        self.launcher = launcher
        self.settings = settingsStore.load()
    }

    public func refresh() async {
        var discovered: [Host] = []
        do {
            discovered = try await tailscale.fetchMacs()
            tailscaleError = nil
        } catch {
            tailscaleError = message(for: error)
        }

        let hosts = mergeHosts(tailscale: discovered, settings: settings)

        // Each host probes independently so a single sleeping Mac cannot
        // block the menu.
        let probe = self.probe
        let statuses = await withTaskGroup(of: (String, ProbeOutcome).self) { group in
            for host in hosts {
                group.addTask {
                    let outcome = await probe.probe(
                        host: host.ipv4, port: screenSharingPort, timeout: .seconds(2))
                    return (host.id, outcome)
                }
            }
            var results: [String: ProbeOutcome] = [:]
            for await (id, outcome) in group { results[id] = outcome }
            return results
        }

        entries = hosts.map { host in
            HostEntry(
                host: host,
                status: resolveStatus(
                    tailscaleOnline: host.source == .tailscale ? host.isOnline : nil,
                    probe: statuses[host.id]
                )
            )
        }
    }

    public func connect(to host: Host) {
        launcher.openScreenSharing(host: host)
    }

    public func openSSH(to host: Host) {
        let terminal = settings.terminal
        let plan = launchPlan(
            for: terminal,
            user: settings.sshUsername(for: host),
            host: host.ipv4,
            isRunning: launcher.isRunning(bundleIdentifier: terminal.bundleIdentifier)
        )
        launcher.execute(plan)
    }

    public func openFiles(for host: Host) {
        launcher.openFileSharing(host: host)
    }

    public func copyAddress(of host: Host) {
        launcher.copyToClipboard(host.ipv4)
    }

    public func availableTerminals() -> [TerminalKind] {
        installedTerminals(using: launcher)
    }

    private func message(for error: Error) -> String {
        switch error {
        case CommandError.notFound:
            "Nie znaleziono Tailscale."
        case CommandError.timedOut:
            "Tailscale nie odpowiada."
        case TailscaleParseError.guiLaunchFailure:
            "Tailscale nie odpowiada (tryb CLI niedostępny)."
        case let TailscaleParseError.notRunning(state):
            "Tailscale rozłączony (\(state))."
        default:
            "Nie udało się odczytać listy maszyn."
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HostStoreTests 2>&1 | tail -20`
Expected: PASS — 6 tests passing.

Then run the whole suite: `swift test 2>&1 | tail -10`
Expected: all tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Store/HostStore.swift Tests/RemoteMacCoreTests/HostStoreTests.swift
git commit -m "feat: host store with concurrent probing and error surfacing"
```

---

### Task 12: Menu bar UI

**Files:**
- Delete: `Sources/RemoteMac/main.swift`
- Create: `Sources/RemoteMac/RemoteMacApp.swift`
- Create: `Sources/RemoteMac/Views/MenuView.swift`
- Create: `Sources/RemoteMac/Views/HostRow.swift`
- Create: `Sources/RemoteMac/Views/StatusDot.swift`

**Interfaces:**
- Consumes: `HostStore`, `HostEntry`, `HostStatus` (Task 11).
- Produces: the running app. No new public API.

`main.swift` is replaced by an `@main` struct — SwiftPM treats a file named
`main.swift` as top-level code, which conflicts with `@main`.

`.menuBarExtraStyle(.window)` is required: `.menu` renders an `NSMenu`, which
cannot host coloured status indicators or custom rows.

- [ ] **Step 1: Write the failing check**

There is no unit test for SwiftUI layout here; the check is that the app builds
and launches as a menu bar item with no Dock icon.

Run: `swift build 2>&1 | tail -5`
Expected: currently succeeds with the placeholder `main.swift`, which prints to
stdout instead of showing a menu. That is the gap this task closes.

- [ ] **Step 2: Confirm the current binary is not a menu bar app**

Run: `swift run RemoteMac 2>&1 | head -3`
Expected: prints `RemoteMac 1.0` and exits — no menu bar item.

- [ ] **Step 3: Write the implementation**

Delete the placeholder: `rm Sources/RemoteMac/main.swift`

Create `Sources/RemoteMac/RemoteMacApp.swift`:

```swift
import RemoteMacCore
import SwiftUI

@main
struct RemoteMacApp: App {
    @State private var store = HostStore()

    var body: some Scene {
        MenuBarExtra("RemoteMac", systemImage: "display.2") {
            MenuView(store: store)
        }
        // `.window` is required: `.menu` renders an NSMenu, which cannot host
        // coloured status indicators or custom rows.
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
```

Create `Sources/RemoteMac/Views/StatusDot.swift`:

```swift
import RemoteMacCore
import SwiftUI

struct StatusDot: View {
    let status: HostStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(status.label)
    }

    private var color: Color {
        switch status {
        case .online:           .green
        case .screenSharingOff: .orange
        case .offline:          .secondary
        case .notFound:         .red
        case .unknown:          .secondary.opacity(0.5)
        }
    }
}
```

Create `Sources/RemoteMac/Views/HostRow.swift`:

```swift
import RemoteMacCore
import SwiftUI

struct HostRow: View {
    let entry: HostEntry
    let store: HostStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: entry.status)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.host.displayName)
                    .lineLimit(1)
                Text(entry.host.ipv4)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isHovered {
                Button {
                    store.openSSH(to: entry.host)
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help("Otwórz SSH")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(isHovered ? Color.secondary.opacity(0.15) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .onTapGesture { store.connect(to: entry.host) }
        .contextMenu {
            Button("Połącz (Screen Sharing)") { store.connect(to: entry.host) }
            Button("Otwórz SSH") { store.openSSH(to: entry.host) }
            Button("Otwórz pliki (SMB)") { store.openFiles(for: entry.host) }
            Divider()
            Button("Kopiuj adres IP") { store.copyAddress(of: entry.host) }
        }
    }
}
```

Create `Sources/RemoteMac/Views/MenuView.swift`:

```swift
import RemoteMacCore
import SwiftUI

struct MenuView: View {
    let store: HostStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let error = store.tailscaleError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }

            if store.entries.isEmpty {
                Text("Brak maszyn")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.entries) { entry in
                    HostRow(entry: entry, store: store)
                }
            }

            Divider().padding(.vertical, 4)

            Button("Odśwież") {
                Task { await store.refresh() }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)

            Button("Ustawienia…") { openSettings() }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)

            Button("Zakończ") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .frame(width: 280)
        .task { await store.refresh() }
    }
}
```

Note: `SettingsView` is created in Task 13. Until then, add a temporary stub in
`Sources/RemoteMac/Views/SettingsView.swift` so the app compiles:

```swift
import RemoteMacCore
import SwiftUI

struct SettingsView: View {
    let store: HostStore
    var body: some View { Text("Ustawienia").padding() }
}
```

- [ ] **Step 4: Verify it builds and runs as a menu bar app**

Run: `swift build 2>&1 | tail -5`
Expected: build succeeds.

Run: `./Scripts/build-app.sh && open ~/Applications/RemoteMac.app && sleep 3 && lsappinfo info -only ApplicationType "$(lsappinfo find bundleid=io.eightlines.remotemac | head -1)"`
Expected: `"ApplicationType"="UIElement"` — no Dock icon, menu bar only.

Confirm the menu lists both Macs by name with status dots, then quit the app
from its own menu.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMac
git commit -m "feat: menu bar UI listing Macs with status and actions"
```

---

### Task 13: Settings window and launch at login

**Files:**
- Modify: `Sources/RemoteMac/Views/SettingsView.swift` (replace the Task 12 stub)
- Create: `Sources/RemoteMacCore/Store/LoginItem.swift`
- Test: `Tests/RemoteMacCoreTests/LoginItemTests.swift`

**Interfaces:**
- Consumes: `HostStore`, `AppSettings`, `TerminalKind` (Tasks 3, 5, 11).
- Produces:
  - `public enum LoginItemState: Sendable, Equatable { case enabled, disabled, requiresApproval, unavailable }`
  - `public struct LoginItem: Sendable` with `static var current: LoginItemState`, `static func setEnabled(_:) throws`, `static func openSystemSettings()`

`SMAppService` requires a signed app; unsigned builds fail with
`kSMErrorInvalidSignature`. `.requiresApproval` must be handled — the user can
revoke consent in System Settings.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/LoginItemTests.swift`:

```swift
import Testing
@testable import RemoteMacCore

@Test func currentStateIsReadableWithoutCrashing() {
    // Under `swift test` there is no .app bundle, so this reports
    // .unavailable rather than trapping.
    let state = LoginItem.current
    #expect(LoginItemState.allValues.contains(state))
}

@Test func requiresApprovalIsDistinctFromDisabled() {
    // The user can revoke consent in System Settings; that is a different
    // condition from never having enabled it, and needs a different prompt.
    #expect(LoginItemState.requiresApproval != .disabled)
}

@Test func everyStateHasNonEmptyPolishLabel() {
    #expect(LoginItemState.allValues.allSatisfy { !$0.label.isEmpty })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LoginItemTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'LoginItem' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Store/LoginItem.swift`:

```swift
import Foundation
import ServiceManagement

public enum LoginItemState: Sendable, Equatable {
    case enabled
    case disabled
    /// The user revoked consent in System Settings. Distinct from `.disabled`,
    /// because the remedy is a trip to System Settings rather than a toggle.
    case requiresApproval
    /// Not running from a signed .app bundle, e.g. under `swift test`.
    case unavailable

    public static let allValues: [LoginItemState] =
        [.enabled, .disabled, .requiresApproval, .unavailable]

    public var label: String {
        switch self {
        case .enabled:          "Włączone"
        case .disabled:         "Wyłączone"
        case .requiresApproval: "Wymaga zgody w Ustawieniach systemowych"
        case .unavailable:      "Niedostępne (aplikacja nie jest podpisana)"
        }
    }
}

/// Wraps `SMAppService.mainApp`. Registration requires a code-signed bundle —
/// unsigned builds fail with `kSMErrorInvalidSignature`.
public enum LoginItem {
    public static var current: LoginItemState {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled:          return .enabled
        case .notRegistered:    return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound:         return .unavailable
        @unknown default:       return .unavailable
        }
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
```

Replace `Sources/RemoteMac/Views/SettingsView.swift`:

```swift
import RemoteMacCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: HostStore
    @State private var loginState = LoginItem.current
    @State private var newHostName = ""
    @State private var newHostAddress = ""

    var body: some View {
        TabView {
            general.tabItem { Label("Ogólne", systemImage: "gearshape") }
            hosts.tabItem { Label("Maszyny", systemImage: "display.2") }
        }
        .frame(width: 460, height: 340)
    }

    private var general: some View {
        Form {
            Picker("Terminal:", selection: $store.settings.terminal) {
                ForEach(store.availableTerminals(), id: \.self) { terminal in
                    Text(terminal.displayName).tag(terminal)
                }
            }

            if store.settings.terminal == .warp {
                Text("Warp nie pozwala uruchomić komendy automatycznie. "
                     + "Komenda trafi do schowka — wklej ją przez ⌘V.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.settings.terminal.requiresAppleEvents {
                Text("Terminal wymaga zgody na automatyzację. "
                     + "macOS zapyta o nią przy pierwszym użyciu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Użytkownik SSH:", text: $store.settings.defaultSSHUsername)

            Divider()

            Toggle("Uruchamiaj przy logowaniu", isOn: Binding(
                get: { loginState == .enabled },
                set: { enabled in
                    try? LoginItem.setEnabled(enabled)
                    loginState = LoginItem.current
                }
            ))
            .disabled(loginState == .unavailable)

            if loginState == .requiresApproval {
                Button("Otwórz Ustawienia systemowe") { LoginItem.openSystemSettings() }
            }
            if loginState == .unavailable {
                Text(loginState.label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hosts: some View {
        VStack(alignment: .leading) {
            Text("Ręcznie dodane maszyny")
                .font(.headline)

            List {
                ForEach(store.settings.manualHosts, id: \.self) { host in
                    HStack {
                        Text(host.name)
                        Spacer()
                        Text(host.address).foregroundStyle(.secondary)
                        Button {
                            store.settings.manualHosts.removeAll { $0 == host }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                TextField("Nazwa", text: $newHostName)
                TextField("Adres IP", text: $newHostAddress)
                Button("Dodaj") {
                    guard !newHostName.isEmpty, !newHostAddress.isEmpty else { return }
                    store.settings.manualHosts.append(
                        ManualHost(name: newHostName, address: newHostAddress))
                    newHostName = ""
                    newHostAddress = ""
                    Task { await store.refresh() }
                }
            }
        }
        .padding()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LoginItemTests 2>&1 | tail -20`
Expected: PASS — 3 tests passing.

Run: `swift build 2>&1 | tail -5`
Expected: build succeeds.

Run: `./Scripts/build-app.sh && open ~/Applications/RemoteMac.app`
Then open Settings from the menu, switch the terminal to iTerm2, and confirm
the choice survives a quit and relaunch. Verify the file:
`cat ~/Library/Application\ Support/io.eightlines.remotemac/settings.json`
Expected: pretty-printed JSON with `"terminal" : "iterm"`.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMac/Views/SettingsView.swift Sources/RemoteMacCore/Store/LoginItem.swift Tests/RemoteMacCoreTests/LoginItemTests.swift
git commit -m "feat: settings window with terminal choice and launch at login"
```

---

### Task 14: Quick switcher window

**Files:**
- Create: `Sources/RemoteMac/Views/QuickSwitcher.swift`
- Modify: `Sources/RemoteMac/RemoteMacApp.swift` (add the window scene)
- Modify: `Sources/RemoteMac/Views/MenuView.swift` (add the opening button)

**Interfaces:**
- Consumes: `searchHosts` (Task 7), `HostStore` (Task 11).
- Produces: no new public API.

- [ ] **Step 1: Verify the search backing already works**

Run: `swift test --filter HostSearchTests 2>&1 | tail -5`
Expected: PASS — the ranking logic this UI depends on is already covered.

- [ ] **Step 2: Confirm no switcher exists yet**

Run: `grep -r "QuickSwitcher" Sources/ | wc -l`
Expected: `0`.

- [ ] **Step 3: Write the implementation**

Create `Sources/RemoteMac/Views/QuickSwitcher.swift`:

```swift
import RemoteMacCore
import SwiftUI

struct QuickSwitcher: View {
    let store: HostStore
    @State private var query = ""
    @State private var selection = 0
    @Environment(\.dismiss) private var dismiss

    private var results: [HostEntry] {
        let hosts = searchHosts(store.entries.map(\.host), query: query)
        return hosts.compactMap { host in
            store.entries.first { $0.host.id == host.id }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Szukaj maszyny…", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(12)
                .onChange(of: query) { selection = 0 }
                .onSubmit { activate() }

            Divider()

            List(Array(results.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 8) {
                    StatusDot(status: entry.status)
                    Text(entry.host.displayName)
                    Spacer()
                    Text(entry.host.ipv4).foregroundStyle(.secondary).font(.caption)
                }
                .padding(.vertical, 2)
                .listRowBackground(
                    index == selection ? Color.accentColor.opacity(0.2) : Color.clear
                )
                .onTapGesture {
                    selection = index
                    activate()
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 420, height: 300)
        .onKeyPress(.upArrow) {
            selection = max(0, selection - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selection = min(max(0, results.count - 1), selection + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    /// Enter connects via Screen Sharing; ⌘-Enter opens SSH instead.
    private func activate() {
        guard results.indices.contains(selection) else { return }
        let host = results[selection].host
        if NSEvent.modifierFlags.contains(.command) {
            store.openSSH(to: host)
        } else {
            store.connect(to: host)
        }
        dismiss()
    }
}
```

Modify `Sources/RemoteMac/RemoteMacApp.swift` — add the window scene after
`Settings`:

```swift
        Window("Szybkie połączenie", id: "quick-switcher") {
            QuickSwitcher(store: store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
```

Modify `Sources/RemoteMac/Views/MenuView.swift` — add the environment action
next to `openSettings`:

```swift
    @Environment(\.openWindow) private var openWindow
```

and a button directly above the "Odśwież" button:

```swift
            Button("Szybkie połączenie…") { openWindow(id: "quick-switcher") }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
```

- [ ] **Step 4: Verify it builds and works**

Run: `swift build 2>&1 | tail -5`
Expected: build succeeds.

Run: `./Scripts/build-app.sh && open ~/Applications/RemoteMac.app`
Open "Szybkie połączenie…", type `mini`, confirm the Mac mini is selected, and
press Enter to launch Screen Sharing. Press Escape to dismiss without acting.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMac
git commit -m "feat: Spotlight-style quick switcher"
```

---

### Task 15: Background refresh and README

**Files:**
- Modify: `Sources/RemoteMacCore/Store/HostStore.swift` (add polling control)
- Modify: `Sources/RemoteMac/RemoteMacApp.swift` (start polling at launch)
- Create: `README.md`
- Test: `Tests/RemoteMacCoreTests/HostStoreTests.swift` (append)

**Interfaces:**
- Consumes: `HostStore` (Task 11).
- Produces: `public func startPolling(interval: Duration)` and `public func stopPolling()` on `HostStore`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/RemoteMacCoreTests/HostStoreTests.swift`:

```swift
@MainActor
@Test func pollingRefreshesRepeatedly() async throws {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: ["100.123.34.96": .listening])
    )
    store.startPolling(interval: .milliseconds(120))
    defer { store.stopPolling() }

    try await Task.sleep(for: .milliseconds(400))
    #expect(store.entries.count == 2)
}

@MainActor
@Test func stopPollingHaltsFurtherRefreshes() async throws {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:])
    )
    store.startPolling(interval: .milliseconds(100))
    try await Task.sleep(for: .milliseconds(250))
    store.stopPolling()

    #expect(!store.isPolling)
}

@MainActor
@Test func startPollingTwiceDoesNotStackTasks() async throws {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:])
    )
    store.startPolling(interval: .milliseconds(100))
    store.startPolling(interval: .milliseconds(100))
    defer { store.stopPolling() }

    #expect(store.isPolling)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HostStoreTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'HostStore' has no member 'startPolling'`.

- [ ] **Step 3: Write minimal implementation**

Modify `Sources/RemoteMacCore/Store/HostStore.swift` — add the property next to
the other stored properties:

```swift
    private var pollingTask: Task<Void, Never>?

    public var isPolling: Bool { pollingTask != nil }
```

and these methods inside the class:

```swift
    /// Refreshes in the background while the menu is closed. Starting twice is
    /// a no-op rather than stacking tasks.
    public func startPolling(interval: Duration = .seconds(30)) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
```

Modify `Sources/RemoteMac/RemoteMacApp.swift` — replace the `MenuBarExtra`
scene body so polling starts once at launch:

```swift
        MenuBarExtra("RemoteMac", systemImage: "display.2") {
            MenuView(store: store)
                .task { store.startPolling() }
        }
        .menuBarExtraStyle(.window)
```

and remove the now-redundant `.task { await store.refresh() }` from
`MenuView.swift`, since `startPolling` refreshes immediately on its first
iteration.

Create `README.md`:

```markdown
# RemoteMac

Aplikacja w pasku menu macOS do szybkiego łączenia się ze zdalnymi Makami przez
wbudowany Screen Sharing. Zastępuje ręczne wpisywanie adresów IP w Finderze
(⌘K), pokazując maszyny po nazwie.

## Co robi

- wyświetla Maki z Tailscale automatycznie, po nazwie
- pokazuje, czy maszyna jest dostępna i czy Screen Sharing nasłuchuje
- łączy przez Screen Sharing jednym kliknięciem
- otwiera SSH w wybranym terminalu (Ghostty, iTerm2, Terminal, Warp, Termius)
- otwiera pliki przez SMB, kopiuje adres IP
- szybkie wyszukiwanie w stylu Spotlight

## Wymagania

- macOS 15 lub nowszy
- Tailscale (dowolna wersja — App Store lub standalone)
- Screen Sharing włączony na maszynach docelowych
  (Ustawienia systemowe → Ogólne → Udostępnianie → Zarządzanie zdalne)

## Budowanie

```bash
./Scripts/build-app.sh
open ~/Applications/RemoteMac.app
```

Aplikacja jest podpisywana certyfikatem Developer ID. Bez podpisu uprawnienia
systemowe resetowałyby się przy każdym przebudowaniu, a start przy logowaniu nie
działałby wcale.

## Testy

```bash
swift test
```

## Konfiguracja

Ustawienia trzymane są w czytelnym pliku JSON, który można edytować ręcznie:

```
~/Library/Application Support/io.eightlines.remotemac/settings.json
```

Hasła nie są tam przechowywane — Screen Sharing zapamiętuje je w Keychainie
macOS.

## Uwagi

- **Warp** celowo nie pozwala uruchomić komendy automatycznie. Aplikacja otwiera
  Warp i kopiuje komendę do schowka.
- **Terminal.app** wymaga zgody na automatyzację przy pierwszym użyciu.
  Ghostty i iTerm2 nie wymagają żadnych uprawnień.
- Otwarty port 5900 oznacza, że Screen Sharing nasłuchuje — nie gwarantuje, że
  logowanie się powiedzie.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test 2>&1 | tail -10`
Expected: PASS — the whole suite, including the three new polling tests.

Run: `./Scripts/build-app.sh && open ~/Applications/RemoteMac.app`
Leave the app running, put one Mac to sleep, and confirm its dot turns grey
within roughly 30 seconds without opening the menu.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Store/HostStore.swift Sources/RemoteMac/RemoteMacApp.swift Sources/RemoteMac/Views/MenuView.swift Tests/RemoteMacCoreTests/HostStoreTests.swift README.md
git commit -m "feat: background refresh and README"
```

---

### Task 16: Optional SSH status enrichment

**Files:**
- Create: `Sources/RemoteMacCore/Clients/SSHStatusClient.swift`
- Modify: `Sources/RemoteMacCore/Store/HostStore.swift` (attach details to entries)
- Modify: `Sources/RemoteMac/Views/HostRow.swift` (show the detail line)
- Test: `Tests/RemoteMacCoreTests/SSHStatusClientTests.swift`

**Interfaces:**
- Consumes: `CommandRunning`, `CommandError` (Task 8), `Host` (Task 2), `HostEntry` (Task 11).
- Produces:
  - `public struct HostDetails: Sendable, Equatable { public let consoleUser: String?; public let isScreenLocked: Bool? }`
  - `public struct SSHStatusClient: Sendable` with `init(runner: CommandRunning)`, `func fetchDetails(host: Host) async -> HostDetails?`
  - `public func parseConsoleState(_ output: String) -> HostDetails`
  - `HostEntry` gains `public let details: HostDetails?`

This is strictly additive. SSH keys are not configured between the user's Macs,
so `fetchDetails` returns nil and the UI simply shows nothing extra. It must
never gate or delay the host list.

Two constraints from the spec: `ConnectTimeout` does not bound the auth phase
(a password-prompting host hung 8 s despite `ConnectTimeout=3`), so
`BatchMode=yes` plus an external timeout are both mandatory. And
`CGSSessionScreenIsLocked` returns nothing on macOS 26 — `IOConsoleLocked` is
the key that works.

- [ ] **Step 1: Write the failing test**

Create `Tests/RemoteMacCoreTests/SSHStatusClientTests.swift`:

```swift
import Foundation
import Testing
@testable import RemoteMacCore

private struct StubRunner: CommandRunning {
    let result: Result<Data, CommandError>
    let recorder: Recorder?

    final class Recorder: @unchecked Sendable {
        var arguments: [String] = []
    }

    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        recorder?.arguments = arguments
        return try result.get()
    }
}

private let host = Host(id: "1", name: "mini", displayName: "Mac mini",
                        ipv4: "100.123.34.96", isOnline: true,
                        source: .tailscale, sshUsername: "radnok")

@Test func parsesUnlockedSessionWithUser() {
    let details = parseConsoleState("radnok\nNo\n")
    #expect(details.consoleUser == "radnok")
    #expect(details.isScreenLocked == false)
}

@Test func parsesLockedSession() {
    let details = parseConsoleState("radnok\nYes\n")
    #expect(details.isScreenLocked == true)
}

@Test func handlesLoginWindowAsNoUser() {
    let details = parseConsoleState("root\nYes\n")
    #expect(details.consoleUser == nil)
}

@Test func toleratesUnexpectedOutput() {
    let details = parseConsoleState("")
    #expect(details.consoleUser == nil)
    #expect(details.isScreenLocked == nil)
}

@Test func usesBatchModeSoAPasswordPromptCannotHang() async {
    let recorder = StubRunner.Recorder()
    let client = SSHStatusClient(
        runner: StubRunner(result: .success(Data("radnok\nNo\n".utf8)), recorder: recorder))
    _ = await client.fetchDetails(host: host)

    // ConnectTimeout does not bound the auth phase, so BatchMode is the
    // actual control that prevents an 8 s hang.
    #expect(recorder.arguments.contains("BatchMode=yes"))
    #expect(recorder.arguments.contains("radnok@100.123.34.96"))
}

@Test func missingKeysReturnNilRatherThanThrowing() async {
    let client = SSHStatusClient(
        runner: StubRunner(result: .failure(.timedOut), recorder: nil))
    #expect(await client.fetchDetails(host: host) == nil)
}

@Test func hostWithoutUsernameIsSkipped() async {
    let anonymous = Host(id: "2", name: "x", displayName: "x", ipv4: "10.0.0.1",
                         isOnline: true, source: .manual, sshUsername: nil)
    let client = SSHStatusClient(
        runner: StubRunner(result: .success(Data("radnok\nNo\n".utf8)), recorder: nil))
    #expect(await client.fetchDetails(host: anonymous) == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SSHStatusClientTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'parseConsoleState' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RemoteMacCore/Clients/SSHStatusClient.swift`:

```swift
import Foundation

public struct HostDetails: Sendable, Equatable {
    public let consoleUser: String?
    public let isScreenLocked: Bool?

    public init(consoleUser: String?, isScreenLocked: Bool?) {
        self.consoleUser = consoleUser
        self.isScreenLocked = isScreenLocked
    }
}

/// Reads console user and lock state from a single `ioreg` call.
///
/// `IOConsoleUsers[0]` carries the session user and `IOConsoleLocked` the lock
/// flag. `CGSSessionScreenIsLocked` — the commonly cited key — returns nothing
/// on macOS 26, and `CGSession` no longer exists.
private let consoleStateCommand = """
stat -f%Su /dev/console; \
ioreg -n Root -d1 -k IOConsoleLocked \
  | awk -F'= ' '/IOConsoleLocked/{print $2}' \
  | tr -d ' '
"""

public func parseConsoleState(_ output: String) -> HostDetails {
    let lines = output
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }

    let rawUser = lines.first.flatMap { $0.isEmpty ? nil : $0 }
    // `root` at the console means the login window is showing, not a session.
    let consoleUser = rawUser == "root" ? nil : rawUser

    let lockedValue = lines.count > 1 ? lines[1] : ""
    let isScreenLocked: Bool? = switch lockedValue {
    case "Yes", "true": true
    case "No", "false": false
    default: nil
    }

    return HostDetails(consoleUser: consoleUser, isScreenLocked: isScreenLocked)
}

/// Optional enrichment. Returns nil whenever SSH is not usable — the host list
/// must never depend on it.
public struct SSHStatusClient: Sendable {
    private let runner: CommandRunning
    private let timeout: Duration

    public init(runner: CommandRunning = SubprocessRunner(), timeout: Duration = .seconds(4)) {
        self.runner = runner
        self.timeout = timeout
    }

    public func fetchDetails(host: Host) async -> HostDetails? {
        guard let user = host.sshUsername, !user.isEmpty else { return nil }

        // BatchMode is the real control: ConnectTimeout bounds the connect
        // phase only, so a password prompt would otherwise hang past it.
        let arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=3",
            "-o", "StrictHostKeyChecking=accept-new",
            "\(user)@\(host.ipv4)",
            consoleStateCommand,
        ]

        guard let data = try? await runner.run(
            executable: "/usr/bin/ssh",
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            timeout: timeout
        ), let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return nil
        }

        return parseConsoleState(text)
    }
}
```

Modify `Sources/RemoteMacCore/Store/HostStore.swift` — add `details` to
`HostEntry`:

```swift
public struct HostEntry: Sendable, Identifiable, Equatable {
    public let host: Host
    public let status: HostStatus
    public let details: HostDetails?
    public var id: String { host.id }

    public init(host: Host, status: HostStatus, details: HostDetails? = nil) {
        self.host = host
        self.status = status
        self.details = details
    }
}
```

Add the client as a stored property and init parameter:

```swift
    private let sshStatus: SSHStatusClient
```

```swift
        sshStatus: SSHStatusClient = SSHStatusClient(),
```

```swift
        self.sshStatus = sshStatus
```

Then, at the end of `refresh()`, replace the `entries = hosts.map { … }`
assignment with a version that fetches details only for reachable hosts:

```swift
        entries = hosts.map { host in
            HostEntry(
                host: host,
                status: resolveStatus(
                    tailscaleOnline: host.source == .tailscale ? host.isOnline : nil,
                    probe: statuses[host.id]
                )
            )
        }

        // Enrichment runs after the list is already visible, so a slow or
        // unavailable SSH path never delays the menu.
        let reachable = entries.filter { $0.status.isConnectable }.map(\.host)
        guard !reachable.isEmpty else { return }

        let sshStatus = self.sshStatus
        let details = await withTaskGroup(of: (String, HostDetails?).self) { group in
            for host in reachable {
                group.addTask { (host.id, await sshStatus.fetchDetails(host: host)) }
            }
            var results: [String: HostDetails] = [:]
            for await (id, detail) in group {
                if let detail { results[id] = detail }
            }
            return results
        }

        guard !details.isEmpty else { return }
        entries = entries.map { entry in
            HostEntry(host: entry.host, status: entry.status, details: details[entry.host.id])
        }
```

Modify `Sources/RemoteMac/Views/HostRow.swift` — replace the IP `Text` with a
version that appends the detail when present:

```swift
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
```

and add this computed property to the struct:

```swift
    private var subtitle: String {
        guard let details = entry.details else { return entry.host.ipv4 }
        var parts = [entry.host.ipv4]
        if let user = details.consoleUser { parts.append(user) }
        if details.isScreenLocked == true { parts.append("zablokowany") }
        return parts.joined(separator: " · ")
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SSHStatusClientTests 2>&1 | tail -20`
Expected: PASS — 7 tests passing.

Run: `swift test 2>&1 | tail -10`
Expected: the whole suite passes — `HostEntry`'s new parameter has a default,
so the Task 11 tests still compile.

Run: `./Scripts/build-app.sh && open ~/Applications/RemoteMac.app`
Expected: hosts still list normally. Since SSH keys are not configured, no
extra detail appears — confirming enrichment degrades silently.

- [ ] **Step 5: Commit**

```bash
git add Sources/RemoteMacCore/Clients/SSHStatusClient.swift Sources/RemoteMacCore/Store/HostStore.swift Sources/RemoteMac/Views/HostRow.swift Tests/RemoteMacCoreTests/SSHStatusClientTests.swift
git commit -m "feat: optional SSH status enrichment that degrades silently"
```

---

## Verification checklist

After Task 16, confirm the whole thing works end to end:

- [ ] `swift test` — every test passes
- [ ] `./Scripts/build-app.sh` — builds and signs without errors
- [ ] `codesign -dv ~/Applications/RemoteMac.app 2>&1 | grep TeamIdentifier` — reports `7S3F9767BM`
- [ ] `codesign --verify --strict ~/Applications/RemoteMac.app` — silent (valid)
- [ ] Menu bar shows both Macs by name, no Dock icon
- [ ] Clicking a host opens Screen Sharing
- [ ] SSH opens in the configured terminal without a permission prompt (Ghostty or iTerm2)
- [ ] Switching terminals in Settings persists across a relaunch
- [ ] Quick switcher finds a host by partial name and connects on Enter
- [ ] Quitting Tailscale shows the error banner while manual hosts still work
- [ ] Rebuilding twice does not re-trigger any permission prompt — the whole point of Developer ID signing
