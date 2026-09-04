import Foundation

/// Builds a `ManualHost` from raw user input, trimming whitespace from both
/// fields first. Without trimming, a manual host entered with surrounding
/// whitespace would not dedup against its Tailscale twin in `mergeHosts`
/// (which compares addresses by exact string equality) and would appear
/// twice in the list. Returns `nil` when either field is empty after
/// trimming, so a whitespace-only entry is rejected rather than silently
/// added.
public func sanitizedManualHost(name: String, address: String) -> ManualHost? {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty, !trimmedAddress.isEmpty else { return nil }
    return ManualHost(name: trimmedName, address: trimmedAddress)
}
