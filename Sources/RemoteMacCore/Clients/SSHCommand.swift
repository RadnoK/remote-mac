import Foundation

public enum LaunchPlan: Sendable, Equatable {
    /// `open [-n] -a <bundleID> --args <arguments>`
    case openWithArguments(bundleID: String, arguments: [String], newInstance: Bool)
    /// Requires an AppleEvents TCC grant.
    case appleScript(source: String, bundleID: String)
    /// Warp deliberately refuses to submit input, so the command goes to the
    /// clipboard and the user pastes it.
    case openAndCopyToClipboard(bundleID: String, clipboard: String)
}

public func sshCommandLine(user: String, host: String) -> String {
    "ssh \(user)@\(host)"
}

public func launchPlan(
    for terminal: TerminalKind,
    user: String,
    host: String,
    isRunning: Bool
) -> LaunchPlan {
    let destination = "\(user)@\(host)"

    switch terminal {
    case .ghostty:
        // `-e` takes an argv array and never goes through a shell, so the
        // destination needs no quoting.
        return .openWithArguments(
            bundleID: terminal.bundleIdentifier,
            arguments: ["-e", "ssh", destination],
            newInstance: !isRunning
        )

    case .iterm:
        // iTerm2 runs the string via `/usr/bin/login -fpq $USER $SHELL -c`,
        // so it must be shell-escaped. Only the `--command=X` form works;
        // `--command X` silently does nothing.
        let escaped = shellEscape("ssh \(destination)")
        return .openWithArguments(
            bundleID: terminal.bundleIdentifier,
            arguments: ["--command=\(escaped)"],
            newInstance: !isRunning
        )

    case .termius:
        return .openWithArguments(
            bundleID: terminal.bundleIdentifier,
            arguments: [destination],
            newInstance: !isRunning
        )

    case .terminal:
        // The do script argument is a shell command line. First shell-escape it
        // (wrapping in single quotes protects against newlines and all shell
        // metacharacters), then AppleScript-escape the result (protecting quotes
        // and backslashes for the AppleScript string literal).
        let shellSafe = shellEscape(sshCommandLine(user: user, host: host))
        let scriptSafe = appleScriptEscape(shellSafe)
        let script = """
        tell application "Terminal"
            activate
            do script "\(scriptSafe)"
        end tell
        """
        return .appleScript(source: script, bundleID: terminal.bundleIdentifier)

    case .warp:
        return .openAndCopyToClipboard(
            bundleID: terminal.bundleIdentifier,
            clipboard: sshCommandLine(user: user, host: host)
        )
    }
}

/// Wraps a string in single quotes for POSIX shells, escaping embedded quotes.
private func shellEscape(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}

/// Escapes backslashes, double quotes, and newlines for embedding in an
/// AppleScript string literal. Newlines cannot appear raw in an AppleScript
/// string literal; they must be escaped as backslash-n.
private func appleScriptEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
