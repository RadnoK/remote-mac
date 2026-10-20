import ApplicationServices
import Foundation

/// Whether this process may drive other apps through the Accessibility API,
/// which the Screen Sharing chooser automation needs. Behind a protocol so
/// tests never touch the real permission or its system prompt.
public protocol AccessibilityPermission: Sendable {
    var isTrusted: Bool { get }
    /// Shows the system prompt that deep-links to the Accessibility pane.
    func requestTrust()
}

public struct SystemAccessibilityPermission: AccessibilityPermission {
    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func requestTrust() {
        // The literal is the value of `kAXTrustedCheckOptionPrompt`; reading
        // that C global directly is a Swift 6 concurrency error.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
