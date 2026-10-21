import AppKit
import ApplicationServices
import Foundation

/// The slice of an Accessibility element the type chooser needs, split from
/// `AXUIElement` so the locator and the selector are testable without a live
/// Screen Sharing window.
public protocol AXNode: Sendable {
    /// Equal for every handle to the same on-screen element, so a window seen
    /// before the `vnc://` URL was opened can be told apart from a new one.
    var id: Int { get }
    var role: String? { get }
    var children: [any AXNode] { get }
    var isEnabled: Bool { get }
    @discardableResult func press() -> Bool
}

/// The two answers and the button that commits them.
public struct TypeChooser: Sendable {
    public let standard: any AXNode
    public let highPerformance: any AXNode
    public let confirm: any AXNode
}

/// Finds Screen Sharing's "Select Screen Sharing Type" chooser by shape
/// alone: the labels sit in AXDescription and are localized, so matching
/// text would break in every language but one.
///
/// The shape is an `AXRadioGroup` holding exactly two `AXRadioButton`s
/// (Standard first, High Performance second) next to at least two
/// `AXButton`s. The confirm button is the last of those siblings, because
/// this SwiftUI dialog leaves `AXDefaultButton` nil and lays out
/// Help / Cancel / Continue with Continue trailing.
public func findTypeChooser(in window: any AXNode) -> TypeChooser? {
    findTypeChooser(under: window, depth: 0)
}

/// The chooser sits two levels below its window. The cap only bounds the
/// Accessibility round trips spent walking unrelated windows on every poll.
private let maxChooserSearchDepth = 6

private func findTypeChooser(under parent: any AXNode, depth: Int) -> TypeChooser? {
    guard depth < maxChooserSearchDepth else { return nil }
    let children = parent.children
    let roles = children.map(\.role)

    for (index, child) in children.enumerated() where roles[index] == kAXRadioGroupRole {
        let radios = child.children.filter { $0.role == kAXRadioButtonRole }
        let buttons = children.indices.filter { roles[$0] == kAXButtonRole }
        if radios.count == 2, buttons.count >= 2, let confirm = buttons.last {
            return TypeChooser(standard: radios[0], highPerformance: radios[1],
                               confirm: children[confirm])
        }
    }
    for child in children {
        if let chooser = findTypeChooser(under: child, depth: depth + 1) { return chooser }
    }
    return nil
}

/// Every Screen Sharing window, as seen by the selector's polling loop.
public protocol ScreenSharingWindowSource: Sendable {
    func windows() -> [any AXNode]
}

/// `@unchecked Sendable` because `AXUIElement` is an immutable CF handle the
/// Accessibility API documents as usable from any thread; the type itself is
/// not annotated.
struct AXElementNode: AXNode, @unchecked Sendable {
    let element: AXUIElement

    var id: Int { Int(bitPattern: UInt(CFHash(element))) }

    var role: String? { attribute(kAXRoleAttribute) as? String }

    var children: [any AXNode] {
        (attribute(kAXChildrenAttribute) as? [AXUIElement])?.map(AXElementNode.init) ?? []
    }

    /// An element without the attribute counts as enabled, which is how the
    /// Accessibility API itself treats it.
    var isEnabled: Bool { (attribute(kAXEnabledAttribute) as? Bool) ?? true }

    @discardableResult
    func press() -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}

/// Resolves the app on every call rather than once: Screen Sharing is
/// usually launched by the very `vnc://` URL the selector is watching for,
/// so its process does not exist yet when the watcher starts.
public struct AXScreenSharingWindowSource: ScreenSharingWindowSource {
    static let bundleIdentifier = "com.apple.ScreenSharing"

    public init() {}

    public func windows() -> [any AXNode] {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.bundleIdentifier).first
        else { return [] }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        else { return [] }
        return windows.map(AXElementNode.init)
    }
}
