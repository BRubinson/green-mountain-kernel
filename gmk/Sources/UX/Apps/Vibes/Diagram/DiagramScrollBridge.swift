import SwiftUI
import AppKit

/// AppKit because SwiftUI has no scroll-wheel gesture, and two-finger pan is table stakes.
///
/// A LOCAL NSEvent monitor, not a `scrollWheel(with:)` override: SwiftUI's hosting view claims
/// scroll routing before a background representable's NSView sees the event. The monitor's
/// app-global reach is scoped by two checks — the event's window must be this view's window,
/// and its location must fall inside this view's bounds, with an unconsumed event preserving
/// normal dispatch. The NSView removes the monitor on window detach AND deinit, so momentum
/// deltas cannot fire into a dead closure.
struct DiagramScrollBridge: NSViewRepresentable {
    /// Reference-typed sink: closures are swapped in place, so `updateNSView`
    /// never rebuilds the view and can never feed an observation loop.
    @MainActor
    final class Sink {
        var onPan: (CGSize) -> Void = { _ in }
        /// (factor, anchor in view coordinates, top-left origin)
        var onZoom: (CGFloat, CGPoint) -> Void = { _, _ in }
    }
    let sink: Sink

    func makeNSView(context _: Context) -> ScrollCatcher { ScrollCatcher(sink: sink) }
    func updateNSView(_ nsView: ScrollCatcher, context _: Context) { nsView.sink = sink }

    final class ScrollCatcher: NSView {
        var sink: Sink
        private var monitor: Any?

        init(sink: Sink) {
            self.sink = sink
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError("unused") }

        /// v0 ships no keyboard handling — a focusable view here would join the
        /// key-view loop and steal arrow keys from the sidebar List. Flipping
        /// this to true and adding `keyDown` is the entire v1 tool-shortcut seam.
        override var acceptsFirstResponder: Bool { false }
        override var isFlipped: Bool { true }  // match SwiftUI's top-left origin

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        isolated deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        /// Returns nil when consumed, the event untouched when it isn't ours.
        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            let local = convert(event.locationInWindow, from: nil)
            guard bounds.contains(local) else { return event }

            // Mouse wheels report LINES; trackpads report points. Without the
            // scale a wheel notch pans one pixel. `scrollingDeltaX/Y` arrive
            // with the user's natural-scrolling preference ALREADY applied —
            // `isDirectionInvertedFromDevice` merely reports that it happened
            // and must never be used as a correction, or the default
            // configuration pans backwards.
            let unit: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
            var dx = event.scrollingDeltaX * unit
            var dy = event.scrollingDeltaY * unit
            // Shift+wheel means "the other axis" on a device with no X deltas.
            if event.modifierFlags.contains(.shift), dx == 0 { swap(&dx, &dy) }

            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
                // A mouse has no pinch gesture — modifier-scroll is how mouse
                // users zoom at all. Momentum-phase zoom feels broken; drop it.
                guard event.momentumPhase == [] else { return nil }
                sink.onZoom(exp(dy * 0.01), local)
            } else {
                sink.onPan(CGSize(width: dx, height: dy))
            }
            return nil
        }
    }
}
