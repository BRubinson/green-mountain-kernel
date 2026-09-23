import Foundation
import Observation

// External, shareable state for the Memories explorer (selection + expansion). The
// inline tab owns one; CMD-click hands its current values to the popout window via
// PromptMemoriesWindowID, so the popout opens on the same file/expansion.
@MainActor
@Observable
final class MemoriesExplorerModel {
    var selectedFile: URL?
    var expanded: Set<URL>
    // Whether the default-expand seeding has run for the current root yet.
    var didSeedExpansion = false

    /// Creates a Memories explorer model with initial state.
    ///
    /// - Parameters:
    ///   - selectedFile: The initially selected file, if any.
    ///   - expanded: The initially expanded folder URLs.
    init(selectedFile: URL? = nil, expanded: Set<URL> = []) {
        self.selectedFile = selectedFile
        self.expanded = expanded
    }
}
