import Foundation

public enum MonitorSwitchOutcome: Sendable, Equatable {
    /// `m1ddc` accepted the command, so this Mac held the monitor.
    case switched
    /// `m1ddc` is not installed on this Mac.
    case toolMissing
    /// Anything else: no monitor reachable over DDC from this Mac (it is not
    /// the active input), SSH failed, or the call timed out.
    case failed
}

/// Shell snippet that switches the monitor to `input` with `m1ddc` and prints
/// a single status word. The exit status is not available to the caller —
/// `CommandRunning` returns stdout only — so the outcome travels as text.
///
/// Homebrew's directories are prepended because a non-interactive SSH session
/// does not load the user's shell profile, so `m1ddc` would not be on PATH.
public func monitorSwitchCommand(input: UInt8) -> String {
    "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; "
        + "command -v m1ddc >/dev/null 2>&1 || { echo missing; exit 0; }; "
        + "m1ddc set input \(input) >/dev/null 2>&1 && echo ok || echo failed"
}

/// Reads the status word from the last non-empty line, so an MOTD or login
/// banner printed first cannot be mistaken for it (see `parseConsoleState`).
public func parseMonitorSwitchOutput(_ output: String) -> MonitorSwitchOutcome {
    let last = output
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .last { !$0.isEmpty }
    switch last {
    case "ok": return .switched
    case "missing": return .toolMissing
    default: return .failed
    }
}

/// Switches the shared monitor's input from one Mac. DDC only reaches the
/// monitor from the input it is currently showing, so a caller sends the
/// same request through every Mac on the monitor and expects one to succeed.
public struct MonitorSwitchClient: Sendable {
    private let runner: CommandRunning
    private let timeout: Duration

    public init(runner: CommandRunning = SubprocessRunner(), timeout: Duration = .seconds(6)) {
        self.runner = runner
        self.timeout = timeout
    }

    public func switchInput(to input: UInt8, via host: Host) async -> MonitorSwitchOutcome {
        let command = monitorSwitchCommand(input: input)
        let executable: String
        let arguments: [String]
        if host.isLocal {
            executable = "/bin/sh"
            arguments = ["-c", command]
        } else {
            guard let user = host.sshUsername, !user.isEmpty else { return .failed }
            // Same options as `SSHStatusClient`: BatchMode keeps a password
            // prompt from hanging the call past ConnectTimeout.
            executable = "/usr/bin/ssh"
            arguments = [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=3",
                "-o", "StrictHostKeyChecking=accept-new",
                "\(user)@\(host.ipv4)",
                command,
            ]
        }

        guard let data = try? await runner.run(
            executable: executable,
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            timeout: timeout
        ) else {
            return .failed
        }
        return parseMonitorSwitchOutput(String(decoding: data, as: UTF8.self))
    }
}
