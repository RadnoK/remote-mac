import Foundation

public struct TailscaleClient: Sendable {
    private let runner: CommandRunning
    private let executablePath: String?
    private let timeout: Duration

    public init(
        runner: CommandRunning = SubprocessRunner(),
        executablePath: String? = TailscaleClient.resolvedExecutablePath,
        timeout: Duration = .seconds(5)
    ) {
        self.runner = runner
        self.executablePath = executablePath
        self.timeout = timeout
    }

    /// Candidate locations, most likely first. The App Store build ships the
    /// CLI inside the bundle and installs no symlink, so the bundle path is
    /// the one that actually exists on the target machine.
    private static let candidatePaths = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/bin/tailscale",
    ]

    public static var resolvedExecutablePath: String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func fetchMacs() async throws -> [Host] {
        guard let executablePath else { throw CommandError.notFound }

        // Merge rather than replace: assigning a fresh dictionary is `env -i`
        // plus one variable, which is fragile.
        var environment = ProcessInfo.processInfo.environment
        environment["TAILSCALE_BE_CLI"] = "1"

        let data = try await runner.run(
            executable: executablePath,
            arguments: ["status", "--json"],
            environment: environment,
            timeout: timeout
        )
        return try parseTailscaleStatus(data)
    }
}
