import Foundation
import Network

/// Whether `endpoint` is an address on the local network rather than one
/// reached through the internet or Tailscale's CGNAT range. Tailscale's
/// `CurAddr` is an "ip:port" string for a direct path, so a private address
/// there means the peer is on the same LAN; manual hosts pass a bare address.
///
/// Accepts IPv4 or IPv6, with or without a port ("10.0.0.5:41641",
/// "[fd7a::1]:41641", "fe80::1"). Anything that is not a literal address,
/// hostnames included, is `false`.
public func isPrivateEndpoint(_ endpoint: String) -> Bool {
    let address = stripPort(endpoint)

    if isDottedQuad(address), let v4 = IPv4Address(address) {
        return isPrivate(v4)
    }
    if let v6 = IPv6Address(address) {
        // An IPv4-mapped address is judged by the IPv4 range it wraps.
        if let v4 = v6.asIPv4 { return isPrivate(v4) }
        return isPrivate(v6)
    }
    return false
}

private func stripPort(_ endpoint: String) -> String {
    if endpoint.hasPrefix("[") {
        let inner = endpoint.dropFirst()
        return String(inner.prefix { $0 != "]" })
    }
    // A single colon separates host and port; more than one means a bare IPv6.
    let parts = endpoint.split(separator: ":", omittingEmptySubsequences: false)
    return parts.count == 2 ? String(parts[0]) : endpoint
}

/// `IPv4Address` also parses short forms such as "192.168.1", which are not
/// something Tailscale or a user would give us for a host; require four parts.
private func isDottedQuad(_ text: String) -> Bool {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
}

/// 10/8, 172.16/12, 192.168/16 and link-local 169.254/16. Deliberately not
/// 100.64/10: that is Tailscale's own range, i.e. the opposite of "same LAN".
private func isPrivate(_ address: IPv4Address) -> Bool {
    let b = [UInt8](address.rawValue)
    switch (b[0], b[1]) {
    case (10, _), (192, 168), (169, 254): return true
    case (172, 16...31): return true
    default: return false
    }
}

/// Unique-local fc00::/7 and link-local fe80::/10.
private func isPrivate(_ address: IPv6Address) -> Bool {
    let b = [UInt8](address.rawValue)
    return (b[0] & 0xFE) == 0xFC || (b[0] == 0xFE && (b[1] & 0xC0) == 0x80)
}
