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
/// query typed with a plain quote matches "Konrad's Mac mini".
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
