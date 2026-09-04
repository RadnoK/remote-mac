import Foundation

/// Combines auto-discovered Tailscale hosts with the user's manual entries,
/// applies hidden-host filtering, and resolves each host's SSH username,
/// display name override and Screen Sharing port from `AppSettings`. A
/// manual host whose address duplicates a Tailscale IP is dropped, because
/// the Tailscale entry carries a live online flag the manual one lacks.
public func mergeHosts(tailscale: [Host], settings: AppSettings) -> [Host] {
    let hidden = Set(settings.hiddenHostIDs)
    let tailscaleIPs = Set(tailscale.map(\.ipv4))

    let manual = settings.manualHosts
        // A manual entry with no address is a half-finished draft: the
        // settings pane's "+" button creates an empty row for the user to
        // fill in, and that row is persisted as they type. Until it has an
        // address there is nothing to probe or connect to, so showing it in
        // the menu just adds a permanently-red phantom machine. Skip it here
        // rather than in the pane, so a hand-edited settings.json cannot
        // reintroduce it either.
        .filter { !$0.address.trimmingCharacters(in: .whitespaces).isEmpty }
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
            resolved.displayName = settings.displayName(for: host, fallback: host.displayName)
            resolved.screenSharingPort = settings.screenSharingPort(for: host)
            return resolved
        }
        .sorted { $0.displayName < $1.displayName }
}
