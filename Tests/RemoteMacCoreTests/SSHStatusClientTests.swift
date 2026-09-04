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
                        ipv4: "100.123.34.96", isOnline: true,
                        source: .tailscale, sshUsername: "radnok")

@Test func parsesUnlockedSessionWithUser() {
    let details = parseConsoleState("radnok\nNo\n")
    #expect(details.consoleUser == "radnok")
    #expect(details.isScreenLocked == false)
}

@Test func parsesLockedSession() {
    let details = parseConsoleState("radnok\nYes\n")
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

@Test func usesBatchModeSoAPasswordPromptCannotHang() async {
    let recorder = StubRunner.Recorder()
    let client = SSHStatusClient(
        runner: StubRunner(result: .success(Data("radnok\nNo\n".utf8)), recorder: recorder))
    _ = await client.fetchDetails(host: host)

    // ConnectTimeout does not bound the auth phase, so BatchMode is the
    // actual control that prevents an 8 s hang.
    #expect(recorder.arguments.contains("BatchMode=yes"))
    #expect(recorder.arguments.contains("radnok@100.123.34.96"))
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
        runner: StubRunner(result: .success(Data("radnok\nNo\n".utf8)), recorder: nil))
    #expect(await client.fetchDetails(host: anonymous) == nil)
}
