import Foundation

// Hand-off payload for the Memories explorer route (`Route.promptMemories`).
// Plain value semantics — the old memoryRootURL-only equality existed for
// WindowGroup dedupe, which is gone with the one-window-type collapse.
// `selectedFile` + `expanded` carry the inline tab's state across.
// `promptUuid` + `isDaemonWatched` let the popout subscribe to the
// `.memories(promptUuid)` invalidation domain instead of polling (optional so
// route payloads persisted before these fields still decode).
struct PromptMemoriesWindowID: Codable, Hashable, Identifiable {
    let memoryRootURL: URL
    let promptName: String
    let selectedFile: URL?
    let expanded: [URL]
    var promptUuid: String?
    var isDaemonWatched: Bool?

    var id: URL { memoryRootURL }
}
