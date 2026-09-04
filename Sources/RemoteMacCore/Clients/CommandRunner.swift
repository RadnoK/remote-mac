import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

public enum CommandError: Error, Equatable {
    case timedOut
    case notFound
}

public protocol CommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> Data
}

/// Runs subprocesses via `swift-subprocess`, which drains pipes concurrently.
/// Foundation's `Process` with `waitUntilExit()` + `readDataToEndOfFile()`
/// deadlocks once output exceeds the ~64 KB pipe buffer.
public struct SubprocessRunner: CommandRunning, Sendable {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CommandError.notFound
        }

        // swift-subprocess 1.0.0's `Environment` is keyed by `Environment.Key`,
        // not `String`. `Key` conforms to `RawRepresentable` with a
        // never-failing `init(rawValue:)`, which is the public entry point
        // for building a key from a dynamic (non-literal) string.
        let subprocessEnvironment = Environment.custom(
            Dictionary(
                uniqueKeysWithValues: environment.map { (Environment.Key(rawValue: $0.key)!, $0.value) }
            )
        )

        // The external deadline is mandatory: the Tailscale CLI can hang
        // indefinitely while the daemon stays healthy.
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                let result = try await Subprocess.run(
                    .path(FilePath(executable)),
                    arguments: Arguments(arguments),
                    environment: subprocessEnvironment,
                    output: .data(limit: 4 * 1024 * 1024)
                )
                return result.standardOutput
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CommandError.timedOut
            }

            guard let first = try await group.next() else {
                throw CommandError.timedOut
            }
            group.cancelAll()
            return first
        }
    }
}
