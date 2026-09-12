#if canImport(SwiftUI)
import SwiftUI

/// The one selection/emphasis channel: a host sets this ONCE at its scene
/// root via `.environment(\.diagramSelection, …)` and every leaf reads it.
/// The unset default is the empty state, and every consumer's empty-state
/// path renders byte-identically to the pre-slot output — the screenshot
/// call sites never set it and must never change.
///
/// Environment-carried (not init params) so each future emphasis axis
/// (hover, search-match, error markers) is a one-struct change instead of
/// re-threading every leaf init.
public struct DiagramSelectionState: Hashable, Sendable {
    /// The selected element (outline accent on its card/scope).
    public var selectedElementUuid: String?
    /// Elements whose INCIDENT FK edges restroke in accent color.
    public var highlightedElementUuids: Set<String>
    /// Elements faded back (domain filtering, drag ghosting).
    public var dimmedElementUuids: Set<String>

    public init(selectedElementUuid: String? = nil,
                highlightedElementUuids: Set<String> = [],
                dimmedElementUuids: Set<String> = []) {
        self.selectedElementUuid = selectedElementUuid
        self.highlightedElementUuids = highlightedElementUuids
        self.dimmedElementUuids = dimmedElementUuids
    }

    public var isActive: Bool {
        selectedElementUuid != nil
            || !highlightedElementUuids.isEmpty
            || !dimmedElementUuids.isEmpty
    }
}

private struct DiagramSelectionKey: EnvironmentKey {
    static let defaultValue = DiagramSelectionState()
}

extension EnvironmentValues {
    public var diagramSelection: DiagramSelectionState {
        get { self[DiagramSelectionKey.self] }
        set { self[DiagramSelectionKey.self] = newValue }
    }
}
#endif
