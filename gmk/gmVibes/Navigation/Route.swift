import Foundation

/// Codable navigation payload for the single window type. `nil`/absence means
/// the landing page. The session screen is a `NavigationSplitView`, which must
/// be a container root — so windows switch routes at the root rather than
/// pushing destinations onto a `NavigationStack`.
enum Route: Codable, Hashable {
    /// The session view: prompt list + statuses and the session-level tabs.
    case session(SessionWindowID)
    /// The prompt editor. Reuses SessionWindowID: `targetPromptUUID` is the
    /// prompt identity (nil degrades to the newest-prompt rule). The route IS
    /// the deep link — there is no side channel.
    case sessionPrompt(SessionWindowID)
    /// The full-window diagram editor. Carries the DIAGRAM's identity, not
    /// the session's: a PROJECT-tier diagram has no session at all, and one
    /// dope scope can own many saved diagrams — neither fits a (session,
    /// scope code) key. The session, where there is one, rides inside the
    /// payload for the window lease below.
    case diagram(DiagramWindowID)
    case project(projectUuid: String)
    case instance(instanceUuid: String)
    case projects
    case kbites
    case kbiteFile(URL)
    case promptMemories(PromptMemoriesWindowID)
    case search(SearchSeed)

    /// The session both session routes scope to — the window lease key. The
    /// SAME uuid for `.session` and `.sessionPrompt` on one session, so the
    /// window-root lease task's id never changes across that hop and the
    /// scope structurally cannot retire mid-navigation.
    var sessionScopeUuid: String? {
        switch self {
        case .session(let windowID), .sessionPrompt(let windowID):
            windowID.sessionUUID.wireString
        case .diagram(let diagramID):
            // .diagram MUST keep answering here wherever a session exists:
            // a session-owned diagram resolves its dope bindings through the
            // session's scope, and dropping the lease on the session →
            // diagram hop would let that scope retire mid-navigation. A
            // PROJECT-tier diagram has no session to lease, and nil is the
            // honest answer — the lease task simply does not run.
            diagramID.session?.sessionUUID.wireString
        default:
            nil
        }
    }
}

/// Seed for the dedicated SEARCH screen. uuid-only scope (the session name is
/// resolved from CatalogStore at render time, per SessionWindowID's doctrine);
/// `query` carries the ⌘K palette's text across the hand-off so "show all
/// results" doesn't drop the user on an empty page.
struct SearchSeed: Codable, Hashable {
    var sessionUuid: String? = nil
    var query: String = ""
}

/// Window identity. `id` is unique per open, so `WindowGroup(for:)` NEVER
/// dedupes — two windows on one session are legal (SessionScopeCache makes
/// them safe). Decoding always yields a landing seed: restored windows land
/// on the landing page by design.
struct WindowSeed: Codable, Hashable, Identifiable {
    let id: UUID
    let route: Route?

    init(_ route: Route? = nil) {
        self.id = UUID()
        self.route = route
    }

    init(from decoder: Decoder) throws {
        self.init(nil)
    }
}
