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

/// An empty override is stored the same as no override at all — the
/// Devices pane removes the key rather than persisting "", but this is
/// defensive against an empty string surviving anyway (e.g. a hand-edited
/// settings.json).
@Test func emptyPerHostUsernameFallsBackToDefault() {
    var settings = AppSettings.default
    settings.defaultSSHUsername = "radnok"
    settings.sshUsernames = ["nodekey:bbb": ""]

    let host = Host(id: "nodekey:bbb", name: "mini", displayName: "mini",
                    ipv4: "100.123.34.96", isOnline: true, source: .tailscale)
    #expect(settings.sshUsername(for: host) == "radnok")
}

@Test func defaultPathLivesUnderApplicationSupport() {
    let path = SettingsStore.defaultFileURL.path
    #expect(path.contains("Application Support/io.eightlines.remotemac"))
    #expect(path.hasSuffix("settings.json"))
}

/// `displayNameOverrides` and `screenSharingPorts` were added after
/// `AppSettings` shipped, exactly like `language` before them — a
/// settings.json written by an older build (or missing just these two keys)
/// must still decode instead of falling back to `.default` and discarding
/// the user's other saved settings.
@Test func settingsWithoutTheNewPerHostKeysStillDecodes() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let json = """
    {
      "terminal": "ghostty",
      "defaultSSHUsername": "radnok",
      "sshUsernames": {"nodekey:aaa": "admin"},
      "manualHosts": [{"name": "biuro", "address": "192.168.1.50"}],
      "hiddenHostIDs": []
    }
    """
    try Data(json.utf8).write(to: url)

    let store = SettingsStore(fileURL: url)
    let loaded = store.load()
    #expect(loaded.defaultSSHUsername == "radnok")
    #expect(loaded.sshUsernames == ["nodekey:aaa": "admin"])
    #expect(loaded.displayNameOverrides.isEmpty)
    #expect(loaded.screenSharingPorts.isEmpty)

    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func roundTripsNewPerHostKeysThroughDisk() throws {
    let url = makeTempURL()
    let store = SettingsStore(fileURL: url)
    var settings = AppSettings.default
    settings.displayNameOverrides = ["nodekey:aaa": "Office Mac"]
    settings.screenSharingPorts = ["nodekey:aaa": 5901]

    try store.save(settings)
    #expect(store.load() == settings)

    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}
