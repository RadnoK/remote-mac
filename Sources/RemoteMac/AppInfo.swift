import Foundation

/// The app's identity as shown in Settings → About and Settings → Updates:
/// version/build from the bundle, and the maker's contact points. Mirrors
/// RouterMenu's `AppInfo`, the same developer's other menu bar app.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static let websiteLabel = "8lines.io"
    static let websiteURL = URL(string: "https://8lines.io")!
    static let contactURL = URL(string: "mailto:konrad@8lines.io")!
}
