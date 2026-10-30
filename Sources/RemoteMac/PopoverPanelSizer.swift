import AppKit
import SwiftUI

/// Snaps the menu bar panel back to its content's height, and gives it a
/// translucent background up to macOS 26.
///
/// `MenuBarExtra(.window)` grows the panel when tall content appears but
/// never shrinks it again (observed on macOS 26): reopened on the short
/// "no machines" view, the panel keeps the tallest frame it has ever shown
/// and floats the content in the leftover space. This view sits in the
/// popover's background and re-fits the window whenever it lands in one or
/// the content case changes.
///
/// Ported from RouterMenu's `PopoverPanelSizer` — the bug, and the fix, are
/// both specific to `MenuBarExtra(.window)`, not to this app.
struct PopoverPanelSizer: NSViewRepresentable {
    /// Changes when the popover switches content case, so `updateNSView`
    /// fires and re-fits a panel that is already on screen.
    let stateKey: String

    /// The corrected window frame, or nil when the current one already fits.
    /// The top edge stays anchored — AppKit measures `origin.y` from the
    /// bottom of the screen, so the origin absorbs the height delta and the
    /// panel keeps hanging from the menu bar. Sub-point deltas are ignored,
    /// or every layout pass would jiggle the window.
    nonisolated static func fittedFrame(for frame: NSRect,
                                        fittingHeight: CGFloat) -> NSRect? {
        guard fittingHeight > 0 else { return nil }
        let delta = fittingHeight - frame.height
        guard abs(delta) > 1 else { return nil }
        var fitted = frame
        fitted.origin.y -= delta
        fitted.size.height = fittingHeight
        return fitted
    }

    /// Whether the panel needs our backdrop at all. macOS 27 draws its own
    /// glass behind `MenuBarExtra(.window)` — for builds against the 26 and
    /// 27 SDKs alike — and a cleared window with a `.menu` material on top
    /// turns that glass into a flat grey sheet. So from 27 on, the panel's
    /// look is left to the system and this view only re-fits the height.
    nonisolated static func drawsBackdrop(on version: OperatingSystemVersion) -> Bool {
        version.majorVersion < 27
    }

    static let drawsBackdrop = drawsBackdrop(on: ProcessInfo.processInfo.operatingSystemVersion)

    func makeNSView(context: Context) -> TrackerView { TrackerView() }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.refit()
    }

    /// Doubles as the panel's translucent backdrop. It has to be this view,
    /// placed by SwiftUI's own `.background`, rather than an effect view
    /// slotted into the window's content view by hand: on macOS 27 that
    /// content view is a tree of real AppKit views whose order SwiftUI owns,
    /// and a foreign subview ended up on top of it — covering the rows
    /// (an empty grey panel) and taking every click, so clicking a Mac did
    /// nothing.
    final class TrackerView: NSVisualEffectView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            // On macOS 27 the view stays in place for `refit()`, but hidden:
            // the system's glass is the backdrop there.
            guard PopoverPanelSizer.drawsBackdrop else {
                isHidden = true
                return
            }
            // `.menu` is the thinnest of the popover materials — the desktop
            // reads through it, which is the point.
            material = .menu
            blendingMode = .behindWindow
            // .active, not .followsWindowActiveState: the panel resigns key
            // as soon as the user clicks another app, and a backdrop that
            // goes solid grey on the way out is the bug we came to fix.
            state = .active
            // Clipped to the panel's own corners — clearing the window drops
            // the system's rounding, leaving the material square at the tips.
            wantsLayer = true
            layer?.cornerRadius = Self.cornerRadius
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        /// A background never takes a click: the rows and buttons above it
        /// handle their own, and a hit here would swallow theirs.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Without this the panel's own opaque fill hides the material.
            if PopoverPanelSizer.drawsBackdrop, let window {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            refit()
        }

        /// Matches the panel rounding `MenuBarExtra(.window)` draws itself.
        static let cornerRadius: CGFloat = 11

        func refit() {
            // After the in-flight layout pass — fittingSize is stale before it.
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window,
                      let content = window.contentView,
                      let frame = PopoverPanelSizer.fittedFrame(
                          for: window.frame,
                          fittingHeight: content.fittingSize.height) else { return }
                window.setFrame(frame, display: true)
            }
        }
    }
}
