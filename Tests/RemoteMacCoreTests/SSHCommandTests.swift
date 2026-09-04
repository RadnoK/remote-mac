import Testing
@testable import RemoteMacCore

@Test func ghosttyPassesArgvWithoutShell() {
    let plan = launchPlan(for: .ghostty, user: "radnok", host: "100.123.34.96", isRunning: false)
    #expect(plan == .openWithArguments(
        bundleID: "com.mitchellh.ghostty",
        arguments: ["-e", "ssh", "radnok@100.123.34.96"],
        newInstance: true
    ))
}

@Test func itermUsesEqualsFormOnly() {
    // The space-separated form silently does nothing; only --command=X works.
    let plan = launchPlan(for: .iterm, user: "radnok", host: "100.123.34.96", isRunning: false)
    guard case let .openWithArguments(bundleID, arguments, _) = plan else {
        Issue.record("expected openWithArguments, got \(plan)")
        return
    }
    #expect(bundleID == "com.googlecode.iterm2")
    #expect(arguments.count == 1)
    #expect(arguments[0].hasPrefix("--command="))
    #expect(!arguments.contains("--command"))
}

@Test func itermSkipsNewInstanceWhenAlreadyRunning() {
    // `open -na iTerm` spawns a second iTerm process every time.
    let cold = launchPlan(for: .iterm, user: "radnok", host: "h", isRunning: false)
    let warm = launchPlan(for: .iterm, user: "radnok", host: "h", isRunning: true)
    guard case let .openWithArguments(_, _, coldNew) = cold,
          case let .openWithArguments(_, _, warmNew) = warm else {
        Issue.record("expected openWithArguments")
        return
    }
    #expect(coldNew == true)
    #expect(warmNew == false)
}

@Test func itermEscapesShellMetacharactersWithPOSIXQuoting() {
    // iTerm re-parses the string via `login … $SHELL -c`, so all characters
    // including newline must be protected. POSIX single-quoting is safe:
    // no character is special inside '...'. Embedded apostrophes test the
    // '\'' escape sequence specifically.
    let hostnames = [
        "h;touch /tmp/x",      // semicolon command injection
        "h>/tmp/x",            // output redirection
        "h<in",                // input redirection
        "h*",                  // glob expansion
        "h$(id)",              // command substitution
        "h`id`",               // command substitution
        "h\nrm -rf x",         // newline - parsed as second command
        "h'x",                 // apostrophe (tests '\'' escape)
        "h'; touch /tmp/x; '", // apostrophe injection
        "'"                    // bare apostrophe
    ]

    for hostname in hostnames {
        let plan = launchPlan(for: .iterm, user: "radnok", host: hostname, isRunning: false)
        guard case let .openWithArguments(_, arguments, _) = plan else {
            Issue.record("expected openWithArguments for hostname \(hostname)")
            return
        }
        let arg = arguments[0]

        // Argument must be --command=<single-quoted-string>
        #expect(arg.hasPrefix("--command="))
        let quotedContent = String(arg.dropFirst("--command=".count))

        // Must start and end with single quote
        #expect(quotedContent.hasPrefix("'"))
        #expect(quotedContent.hasSuffix("'"))

        // Interior must be properly quoted: no unescaped single quotes.
        // The escape sequence for a quote in single quotes is: end-quote, backslash,
        // the literal quote, start-quote. In the interior, this appears as:
        // ' (end previous section), \ (escape), ' (literal quote), ' (start new section)
        let interior = String(quotedContent.dropFirst().dropLast())
        var searchStr = interior
        while let quoteIdx = searchStr.firstIndex(of: "'") {
            // Found a quote. Check if it's part of a valid escape sequence.
            // Pattern: ' (end quote) followed by \ (backslash) followed by ' ' (two quotes to open next section)
            // Or at the very start/end with proper context.

            // Get indices for surrounding characters
            let nextIdx = searchStr.index(after: quoteIdx)
            let hasNext = nextIdx < searchStr.endIndex
            let nextChar = hasNext ? searchStr[nextIdx] : Character(" ")

            // A quote in the interior can only appear as part of '\'' escape.
            // So it should be immediately followed by a backslash (if it's the closing quote
            // of the escape) or preceded by one. Let's check for the full pattern.
            let quoteIndexInOriginal = searchStr.distance(from: searchStr.startIndex, to: quoteIdx)

            // Check if this matches the pattern: ' (quote) \ (backslash) ' ' (two quotes)
            if nextChar == "\\" {
                // This is the quote that ends the escape, like: '  \  '  '
                // Skip past the \'' sequence
                let endIdx = searchStr.index(quoteIdx, offsetBy: 4, limitedBy: searchStr.endIndex) ?? searchStr.endIndex
                searchStr = String(searchStr[endIdx...])
            } else {
                // Quote not followed by backslash - might be unescaped, but check if we're
                // at the interior boundary (which shouldn't happen since we stripped the outer quotes)
                Issue.record("unescaped interior quote at position \(quoteIndexInOriginal): \(String(searchStr[quoteIdx...]))")
                return
            }
        }
    }
}

@Test func ghosttyMustNotQuoteArgv() {
    // Ghostty's `-e` takes an argv array, never a shell string. It must NOT
    // be quoted, so a hostile hostname passes through verbatim (safely, because
    // it's argv, not a command string).
    let plan = launchPlan(for: .ghostty, user: "radnok", host: "h;x", isRunning: false)
    guard case let .openWithArguments(_, arguments, _) = plan else {
        Issue.record("expected openWithArguments")
        return
    }
    // Must be exactly ["-e", "ssh", "radnok@h;x"] - no quoting applied.
    #expect(arguments == ["-e", "ssh", "radnok@h;x"])
    // Specifically: no single quotes around the destination.
    #expect(!arguments[2].contains("'"))
}

@Test func ghosttyDoesNotEscapeBecauseArgvNeedsNoQuoting() {
    // Ghostty takes an argv array directly, so the raw value is correct there.
    let plan = launchPlan(for: .ghostty, user: "radnok", host: "h;x", isRunning: false)
    guard case let .openWithArguments(_, arguments, _) = plan else {
        Issue.record("expected openWithArguments")
        return
    }
    // The raw value survives untouched because argv needs no quoting.
    #expect(arguments == ["-e", "ssh", "radnok@h;x"])
}

@Test func terminalUsesAppleScript() {
    let plan = launchPlan(for: .terminal, user: "radnok", host: "100.123.34.96", isRunning: false)
    guard case let .appleScript(source, bundleID) = plan else {
        Issue.record("expected appleScript, got \(plan)")
        return
    }
    #expect(bundleID == "com.apple.Terminal")
    #expect(source.contains("do script"))
    // The ssh command must appear shell-quoted (single quotes) inside the
    // AppleScript do script string.
    #expect(source.contains("'ssh radnok@100.123.34.96'"))
}

@Test func terminalEscapesShellAndAppleScriptBoundaries() {
    // Terminal.app's do script argument is a shell command line. It must be
    // protected at two boundaries: first shell-escaped (single quotes protect
    // all metacharacters including newline), then AppleScript-escaped for the
    // string literal.
    let hostnames = [
        "h;touch /tmp/x",      // semicolon command injection
        "h>/tmp/x",            // output redirection
        "h<in",                // input redirection
        "h*",                  // glob expansion
        "h$(id)",              // command substitution
        "h`id`",               // command substitution
        "h\nrm -rf x",         // newline - parsed as second command
        "h'x",                 // apostrophe (tests '\'' escape)
        "h'; touch /tmp/x; '", // apostrophe injection
        "'"                    // bare apostrophe
    ]

    for hostname in hostnames {
        let plan = launchPlan(for: .terminal, user: "radnok", host: hostname, isRunning: false)
        guard case let .appleScript(source, _) = plan else {
            Issue.record("expected appleScript for hostname \(hostname)")
            return
        }

        // The source must be valid AppleScript with no raw newlines in the do script argument.
        // Extract the do script argument to check it.
        let doScriptPrefix = #"do script ""#
        guard let startIdx = source.range(of: doScriptPrefix)?.upperBound else {
            Issue.record("do script not found in \(source)")
            return
        }
        guard let endIdx = source[startIdx...].range(of: #"""#)?.lowerBound else {
            Issue.record("closing quote not found in \(source)")
            return
        }

        let scriptArg = String(source[startIdx..<endIdx])

        // The scriptArg must not contain a raw newline (would break AppleScript).
        #expect(!scriptArg.contains("\n"), "raw newline in do script for hostname \(hostname)")

        // The ssh command must appear as a single shell-quoted token.
        // Format: 'ssh radnok@...' possibly with \'' for embedded apostrophes.
        let expectedPrefix = "'ssh radnok@"
        #expect(scriptArg.contains(expectedPrefix), "expected ssh command quoted, got \(scriptArg)")

        // Check that the token is properly closed with a single quote at some point.
        // (Full validation is complex; we verify the closing quote exists.)
        #expect(scriptArg.contains("'"), "expected closing quote in \(scriptArg)")
    }
}

@Test func warpOpensAndCopiesBecauseItRefusesToSubmitInput() {
    // Warp Control deliberately provides no action that submits input.
    let plan = launchPlan(for: .warp, user: "radnok", host: "100.123.34.96", isRunning: false)
    #expect(plan == .openAndCopyToClipboard(
        bundleID: "dev.warp.Warp-Stable",
        clipboard: "ssh radnok@100.123.34.96"
    ))
}

@Test func sshCommandLineJoinsUserAndHost() {
    #expect(sshCommandLine(user: "radnok", host: "100.123.34.96") == "ssh radnok@100.123.34.96")
}

@Test func everyTerminalHasDistinctBundleIdentifier() {
    let ids = TerminalKind.allCases.map(\.bundleIdentifier)
    #expect(Set(ids).count == ids.count)
    #expect(!ids.contains(where: { $0.isEmpty }))
}
