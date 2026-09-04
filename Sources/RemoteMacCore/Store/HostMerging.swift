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
