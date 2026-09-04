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
