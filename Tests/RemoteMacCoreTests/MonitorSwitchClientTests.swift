import Foundation
import Testing
@testable import RemoteMacCore

private final class RecordingRunner: CommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    var calls: [Call] { lock.withLock { recorded } }
    let result: Result<String, CommandError>

    init(result: Result<String, CommandError>) { self.result = result }

    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        lock.withLock { recorded.append(Call(executable: executable, arguments: arguments)) }
        return Data(try result.get().utf8)
    }
}

private func mac(isLocal: Bool, user: String? = "alex") -> RemoteMacCore.Host {
    Host(id: "nodekey:aaa", name: "mini", displayName: "Mac mini", ipv4: "100.64.10.1",
         isOnline: true, source: .tailscale, sshUsername: user, isLocal: isLocal)
}

@Test func commandSetsTheRequestedInput() {
    #expect(monitorSwitchCommand(input: 15).contains("m1ddc set input 15"))
}

@Test func commandFindsHomebrewOutsideALoginPATH() {
    // A non-interactive SSH session does not load Homebrew's shellenv.
    #expect(monitorSwitchCommand(input: 15).contains("/opt/homebrew/bin"))
}

@Test(arguments: [
    ("ok\n", MonitorSwitchOutcome.switched),
    ("missing\n", .toolMissing),
    ("failed\n", .failed),
    ("", .failed),
    ("garbage\n", .failed),
])
func parsesOutcome(output: String, expected: MonitorSwitchOutcome) {
    #expect(parseMonitorSwitchOutput(output) == expected)
}

@Test func outcomeReadsTheLastLineSoALoginBannerCannotMaskIt() {
    #expect(parseMonitorSwitchOutput("Welcome to the Mac mini\nok\n") == .switched)
}

@Test func localMacRunsTheCommandInAShell() async {
    let runner = RecordingRunner(result: .success("ok\n"))
    let outcome = await MonitorSwitchClient(runner: runner).switchInput(to: 17, via: mac(isLocal: true))

    #expect(outcome == .switched)
    #expect(runner.calls == [.init(executable: "/bin/sh",
                                   arguments: ["-c", monitorSwitchCommand(input: 17)])])
}

@Test func remoteMacRunsTheCommandOverNonInteractiveSSH() async {
    let runner = RecordingRunner(result: .success("ok\n"))
    let outcome = await MonitorSwitchClient(runner: runner).switchInput(to: 17, via: mac(isLocal: false))

    #expect(outcome == .switched)
    let call = runner.calls.first
    #expect(call?.executable == "/usr/bin/ssh")
    #expect(call?.arguments.contains("BatchMode=yes") == true)
    #expect(call?.arguments.suffix(2) == ["alex@100.64.10.1", monitorSwitchCommand(input: 17)])
}

@Test func remoteMacWithoutSSHUserFailsWithoutRunningAnything() async {
    let runner = RecordingRunner(result: .success("ok\n"))
    let outcome = await MonitorSwitchClient(runner: runner)
        .switchInput(to: 17, via: mac(isLocal: false, user: nil))

    #expect(outcome == .failed)
    #expect(runner.calls.isEmpty)
}

@Test func runnerErrorIsAFailure() async {
    let runner = RecordingRunner(result: .failure(.timedOut))
    let outcome = await MonitorSwitchClient(runner: runner).switchInput(to: 15, via: mac(isLocal: false))
    #expect(outcome == .failed)
}
