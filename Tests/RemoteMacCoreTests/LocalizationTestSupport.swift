import Foundation
import Testing
@testable import RemoteMacCore

/// The repository's `Resources/` directory as a `Bundle`, so lookups resolve
/// the same `en.lproj` / `pl.lproj` that `Scripts/build-app.sh` copies into
/// `Contents/Resources` of the assembled `.app`. `RemoteMacCore` declares no
/// SwiftPM resources (see `L10n.defaultBundles`'s doc comment), so tests that
/// need real translated strings must build this bundle explicitly rather
/// than relying on `Bundle.module`.
func resourcesBundle() throws -> Bundle {
    let url = repoRoot().appendingPathComponent("Resources")
    return try #require(Bundle(url: url), "no bundle at \(url.path)")
}

/// Reads the shipped `.strings` file straight from the repository, so a test
/// verifies the file that actually gets bundled rather than a copy.
func loadStrings(code: String) throws -> [String: String] {
    let url = repoRoot()
        .appendingPathComponent("Resources/\(code).lproj/Localizable.strings")
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try #require(plist as? [String: String])
}

/// Same `#filePath` walk both helpers above depend on.
func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // RemoteMacCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
}
