import Foundation
import Testing
@testable import RemoteMacCore

private struct StubRunner: CommandRunning {
    let result: Result<Data, CommandError>
    let recorder: Recorder?

    final class Recorder: @unchecked Sendable {
        var environment: [String: String] = [:]
        var executable = ""
        var arguments: [String] = []
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> Data {
        recorder?.executable = executable
        recorder?.arguments = arguments
        recorder?.environment = environment
        return try result.get()
    }
}

private let macOnlyJSON = """
{"BackendState":"Running",
 "Self":{"PublicKey":"nodekey:aaa","HostName":"Mini","DNSName":"mini.ts.net.",
         "OS":"macOS","TailscaleIPs":["100.1.1.1"],"Online":true},
 "Peer":{}}
"""

@Test func passesBeCLIEnvironmentVariableSetToOne() async throws {
    let recorder = StubRunner.Recorder()
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data(macOnlyJSON.utf8)), recorder: recorder),
        executablePath: "/fake/Tailscale"
    )
    _ = try await client.fetchMacs()
    // The variable is value-sensitive: "0" fails exactly like an unset value.
    #expect(recorder.environment["TAILSCALE_BE_CLI"] == "1")
}

@Test func inheritsAmbientEnvironmentRatherThanReplacingIt() async throws {
    let recorder = StubRunner.Recorder()
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data(macOnlyJSON.utf8)), recorder: recorder),
        executablePath: "/fake/Tailscale"
    )
    _ = try await client.fetchMacs()
    // Replacing the environment wholesale is `env -i` plus one variable.
    #expect(recorder.environment.count > 1)
    #expect(recorder.environment["PATH"] != nil)
}

@Test func requestsStatusAsJSON() async throws {
    let recorder = StubRunner.Recorder()
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data(macOnlyJSON.utf8)), recorder: recorder),
        executablePath: "/fake/Tailscale"
    )
    _ = try await client.fetchMacs()
    #expect(recorder.arguments == ["status", "--json"])
    #expect(recorder.executable == "/fake/Tailscale")
}

@Test func returnsParsedHosts() async throws {
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data(macOnlyJSON.utf8)), recorder: nil),
        executablePath: "/fake/Tailscale"
    )
    let hosts = try await client.fetchMacs()
    #expect(hosts.map(\.name) == ["mini"])
}

@Test func timeoutSurfacesAsCommandErrorNotEmptyList() async {
    let client = TailscaleClient(
        runner: StubRunner(result: .failure(.timedOut), recorder: nil),
        executablePath: "/fake/Tailscale"
    )
    await #expect(throws: CommandError.timedOut) {
        _ = try await client.fetchMacs()
    }
}

@Test func guiFailureOutputSurfacesAsParseError() async {
    let text = "The Tailscale GUI failed to start: (Tailscale.CLIError error 3.)"
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data(text.utf8)), recorder: nil),
        executablePath: "/fake/Tailscale"
    )
    await #expect(throws: TailscaleParseError.guiLaunchFailure) {
        _ = try await client.fetchMacs()
    }
}

@Test func missingExecutableThrowsNotFound() async {
    let client = TailscaleClient(
        runner: StubRunner(result: .success(Data()), recorder: nil),
        executablePath: nil
    )
    await #expect(throws: CommandError.notFound) {
        _ = try await client.fetchMacs()
    }
}

@Test func resolvesRealTailscalePathOnThisMachine() {
    // The App Store build ships the CLI inside the bundle; there is no
    // /usr/local/bin/tailscale on this machine.
    let path = TailscaleClient.resolvedExecutablePath
    if let path {
        #expect(FileManager.default.isExecutableFile(atPath: path))
    }
}
