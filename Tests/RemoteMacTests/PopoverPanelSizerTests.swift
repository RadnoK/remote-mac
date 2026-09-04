import AppKit
import Testing
@testable import RemoteMac

/// Guards the frame math that shrinks the menu bar panel back to its
/// content. Ported from RouterMenu's `PopoverPanelSizerTests` — the bug
/// (and fix) this covers is specific to `MenuBarExtra(.window)`, not to
/// this app.
///
/// RouterMenu's version also covers `TrackerView`'s backdrop installation
/// by creating a real `NSWindow` and adding the tracker as a subview. That
/// path is deliberately NOT ported here: in this environment, instantiating
/// `NSWindow` concurrently with this package's other tests — several of
/// which spawn real subprocesses via `swift-subprocess` (`TailscaleClient`,
/// `SSHStatusClient`, `PortProbeTests`) — reproduced both a process hang
/// (parked forever in `CFRunLoopRun` alongside AppKit's `NSEventThread`,
/// even though every test had already reported "passed") and, once, an
/// outright `SIGSEGV`, depending on scheduling. Neither reproduced with
/// `NSMenu`-only or `NSApplication.shared`-only AppKit calls (see
/// `SettingsWindowOpenerTests`), so the hazard is specific to `NSWindow`
/// construction racing subprocess spawning here, not to touching AppKit at
/// all. `fittedFrame` — the actual bug this file exists to prevent a
/// regression in — needs no `NSWindow` and is fully covered below.
@MainActor
struct PopoverPanelSizerTests {
    private static let tall = NSRect(x: 100, y: 100, width: 320, height: 700)

    @Test func shrinkKeepsTheTopEdgeAnchored() {
        let fitted = PopoverPanelSizer.fittedFrame(for: Self.tall, fittingHeight: 200)
        #expect(fitted == NSRect(x: 100, y: 600, width: 320, height: 200))
        #expect(fitted.map(\.maxY) == Self.tall.maxY, "the panel hangs from the menu bar")
    }

    @Test func growthKeepsTheTopEdgeAnchored() {
        let fitted = PopoverPanelSizer.fittedFrame(for: Self.tall, fittingHeight: 900)
        #expect(fitted == NSRect(x: 100, y: -100, width: 320, height: 900))
    }

    @Test func nearMissesDoNotResize() {
        #expect(PopoverPanelSizer.fittedFrame(for: Self.tall, fittingHeight: 700.5) == nil,
                "sub-point deltas would make every layout pass jiggle the window")
        #expect(PopoverPanelSizer.fittedFrame(for: Self.tall, fittingHeight: 700) == nil)
    }

    @Test func degenerateFittingHeightIsIgnored() {
        #expect(PopoverPanelSizer.fittedFrame(for: Self.tall, fittingHeight: 0) == nil)
        #expect(PopoverPanelSizer.fittedFrame(for: Self.tall, fittingHeight: -50) == nil)
    }
}
