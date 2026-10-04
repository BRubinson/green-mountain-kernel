#if canImport(SwiftUI)
import SwiftUI

/// The one selection/emphasis channel: a host sets this ONCE at its scene root
/// via `.environment(\.diagramSelection, …)` and every leaf reads it.
///
/// The unset default is the empty state, which screenshot call sites rely on.
///
/// Environment-carried rather than init params, so a new emphasis axis (hover,
/// search-match, error markers) is a one-struct change instead of re-threading
/// every leaf init.
struct DiagramSelectionState: Hashable, Sendable {
    /// The selected element (outline accent on its card/scope).
    var selectedElementUuid: String?
    /// Elements whose INCIDENT FK edges restroke in accent color.
    var highlightedElementUuids: Set<String>
    /// Elements faded back (domain filtering, drag ghosting).
    var dimmedElementUuids: Set<String>

    /// Creates a diagram selection state.
    ///
    /// - Parameters:
    ///   - selectedElementUuid: The uuid of the selected element; defaults to nil.
    ///   - highlightedElementUuids: The set of highlighted element uuids; defaults to empty.
    ///   - dimmedElementUuids: The set of dimmed element uuids; defaults to empty.
    init(
        selectedElementUuid: String? = nil,
        highlightedElementUuids: Set<String> = [],
        dimmedElementUuids: Set<String> = []
    ) {
        self.selectedElementUuid = selectedElementUuid
        self.highlightedElementUuids = highlightedElementUuids
        self.dimmedElementUuids = dimmedElementUuids
    }

    var isActive: Bool {
        selectedElementUuid != nil
            || !highlightedElementUuids.isEmpty
            || !dimmedElementUuids.isEmpty
    }
}

private struct DiagramSelectionKey: EnvironmentKey {
    static let defaultValue = DiagramSelectionState()
}

extension EnvironmentValues {
    var diagramSelection: DiagramSelectionState {
        get { self[DiagramSelectionKey.self] }
        set { self[DiagramSelectionKey.self] = newValue }
    }
}
#endif
