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

    // Attempt to decode the payload first. Only if decoding fails should we
    // fall back to checking if the CLI tried to launch the GUI (which emits
    // plain text, not JSON, and exits 0).
    let payload: StatusPayload
    if let decoded = try? JSONDecoder().decode(StatusPayload.self, from: data) {
        payload = decoded
    } else {
        // The CLI writes this error to stdout AND exits 0, so the output stream is
        // the only place it can be detected.
        if let text = String(data: data, encoding: .utf8),
           text.contains("The Tailscale GUI failed to start") {
            throw TailscaleParseError.guiLaunchFailure
        }
        throw TailscaleParseError.malformed
    }

    // BackendState must be present and "Running". Absent key means unparseable state.
    guard let state = payload.BackendState else { throw TailscaleParseError.malformed }
    guard state == "Running" else { throw TailscaleParseError.notRunning(state) }

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
/// ("studio-mac-mini.tailnet-1234.ts.net."). The first segment is the
/// DNS-safe short name; `HostName` is not usable here because it may contain
/// a typographic apostrophe and is "localhost" on iOS devices.
private func shortName(fromDNSName dnsName: String?) -> String? {
    guard let first = dnsName?.split(separator: ".").first, !first.isEmpty else {
        return nil
    }
    return String(first)
}
