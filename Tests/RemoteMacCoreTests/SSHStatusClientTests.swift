import Foundation
import Testing
@testable import RemoteMacCore

private struct StubRunner: CommandRunning {
    let result: Result<Data, CommandError>
    let recorder: Recorder?

    final class Recorder: @unchecked Sendable {
        var arguments: [String] = []
    }

    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        recorder?.arguments = arguments
        return try result.get()
    }
}

private let host = Host(id: "1", name: "mini", displayName: "Mac mini",
                        ipv4: "100.64.10.1", isOnline: true,
                        source: .tailscale, sshUsername: "alex")

@Test func parsesUnlockedSessionWithUser() {
    let details = parseConsoleState("alex\nNo\n")
    #expect(details.consoleUser == "alex")
    #expect(details.isScreenLocked == false)
}

@Test func parsesLockedSession() {
    let details = parseConsoleState("alex\nYes\n")
    #expect(details.isScreenLocked == true)
}

@Test func handlesLoginWindowAsNoUser() {
    let details = parseConsoleState("root\nYes\n")
    #expect(details.consoleUser == nil)
}

@Test func toleratesUnexpectedOutput() {
    let details = parseConsoleState("")
    #expect(details.consoleUser == nil)
    #expect(details.isScreenLocked == nil)
}

/// Reading from the START (the original approach) would misattribute a
/// prepended MOTD/banner line as the console user, and the real console user
/// as the lock state — silently wrong rather than nil. Reading from the END
/// is robust to any number of prepended lines, because the two commands run
/// by `consoleStateCommand` always write the final two lines.
@Test func toleratesPrependedBannerLines() {
    let withBanner = parseConsoleState(
        "Last login: Tue Jan 1 00:00:00 on ttys000\nWelcome to macOS\nalex\nNo\n")
    let withoutBanner = parseConsoleState("alex\nNo\n")
    #expect(withBanner == withoutBanner)
    #expect(withBanner.consoleUser == "alex")
    #expect(withBanner.isScreenLocked == false)
}

@Test func singleLineOutputYieldsNilLockState() {
    let details = parseConsoleState("alex\n")
    #expect(details.consoleUser == nil)
    #expect(details.isScreenLocked == nil)
}

@Test func usesBatchModeSoAPasswordPromptCannotHang() async {
    let recorder = StubRunner.Recorder()
    let client = SSHStatusClient(
        runner: StubRunner(result: .success(Data("alex\nNo\n".utf8)), recorder: recorder))
    _ = await client.fetchDetails(host: host)

    // ConnectTimeout does not bound the auth phase, so BatchMode is the
    // actual control that prevents an 8 s hang.
    #expect(recorder.arguments.contains("BatchMode=yes"))
    #expect(recorder.arguments.contains("alex@100.64.10.1"))
}

@Test func missingKeysReturnNilRatherThanThrowing() async {
    let client = SSHStatusClient(
        runner: StubRunner(result: .failure(.timedOut), recorder: nil))
    #expect(await client.fetchDetails(host: host) == nil)
}

@Test func hostWithoutUsernameIsSkipped() async {
    let anonymous = Host(id: "2", name: "x", displayName: "x", ipv4: "10.0.0.1",
                         isOnline: true, source: .manual, sshUsername: nil)
    let client = SSHStatusClient(
        runner: StubRunner(result: .success(Data("alex\nNo\n".utf8)), recorder: nil))
    #expect(await client.fetchDetails(host: anonymous) == nil)
}
