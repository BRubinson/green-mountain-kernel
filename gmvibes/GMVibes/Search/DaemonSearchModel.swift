import Foundation
import Observation
import SwiftUI
import GMCCDaemonKit

/// The debounced SEARCH engine shared by the ⌘K palette and the search screen.
/// Query text stays in the VIEW (@State, the KBiteSearchPane shape) — this owns
/// only the RPC lifecycle and its published results, so both surfaces inherit
/// one cancellation/error discipline instead of copy-pasting it.
@Observable @MainActor
final class DaemonSearchModel {
    private(set) var hits: [SearchHit] = []
    private(set) var searched = false
    private(set) var isSearching = false
    private(set) var errorText: String?

    let limit: Int
    @ObservationIgnored private var task: Task<Void, Never>?

    init(limit: Int) { self.limit = limit }

    /// `debounce: .zero` for discrete actions (chip tap, scope toggle, palette
    /// hand-off) — still routed here so any in-flight task is cancelled first.
    func schedule(
        query: String,
        sessionUuid: String? = nil,
        kinds: Set<SearchKind> = [],
        debounce: Duration = .milliseconds(300)
    ) {
        task?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if !hits.isEmpty { hits = [] }
            searched = false
            isSearching = false
            errorText = nil
            return
        }
        // Ordered for stable request identity across renders; empty ⇒ all kinds.
        let kindList = kinds.isEmpty ? nil : SearchKind.allCases.filter(kinds.contains)
        isSearching = true
        task = Task { [limit] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            do {
                let result = try await GMCCDaemonService.shared.search(
                    query: trimmed, sessionUuid: sessionUuid, kinds: kindList, limit: limit
                )
                guard !Task.isCancelled else { return }
                if hits != result { hits = result }   // change-gated publication
                searched = true
                errorText = nil
            } catch let error as DaemonError {
                guard !Task.isCancelled else { return }
                hits = []   // never strand stale hits behind an error view
                errorText = error.searchMessage
            } catch {
                guard !Task.isCancelled else { return }
                hits = []
                errorText = String(describing: error)
            }
            isSearching = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isSearching = false
    }
}

// DaemonError's userMessage doc invites feature surfaces to re-word a few
// cases; the generic message remains the fallback so new cases need no edit.
private extension DaemonError {
    var searchMessage: String {
        switch self {
        case .server(let code, _) where code == "BAD_REQUEST":
            return "Type at least one searchable word."
        case .notFound:
            return "That session isn't in the GMCC database."
        case .notInstalled:
            return "Daemon not installed — search is unavailable."
        default:
            return userMessage
        }
    }
}

// Forward-compat: `SearchHit.kind` is a RAW STRING by wire contract. An
// unrecognized kind renders with a neutral badge and is NEVER filtered out.
extension SearchHit {
    var resolvedKind: SearchKind? { SearchKind(rawValue: kind) }
    /// Kind + subject uuid: subject uuids come from six different tables.
    var rowID: String { "\(kind):\(subjectUuid)" }
}

extension SearchKind {
    var label: String {
        switch self {
        case .prompt: "Prompt"
        case .clarificationQuestion: "Clarify · Question"
        case .clarificationNote: "Clarify · Note"
        case .architectureSummary: "Architecture"
        case .architectureGeneralChange: "Arch · General"
        case .architecturePersistenceChange: "Arch · Persistence"
        case .explorationSummary: "Exploration"
        case .explorationFinding: "Explore · Finding"
        case .reviewSummary: "Review"
        case .reviewFinding: "Review · Finding"
        }
    }
    var systemImage: String {
        switch self {
        case .prompt: "doc.text"
        case .clarificationQuestion: "questionmark.bubble"
        case .clarificationNote: "note.text"
        case .architectureSummary: "square.stack.3d.up"
        case .architectureGeneralChange: "square.and.pencil"
        case .architecturePersistenceChange: "cylinder.split.1x2"
        case .explorationSummary: "binoculars"
        case .explorationFinding: "sparkle.magnifyingglass"
        case .reviewSummary: "checkmark.seal"
        case .reviewFinding: "exclamationmark.bubble"
        }
    }
    var tint: Color {
        switch self {
        case .prompt: .teal
        case .clarificationQuestion, .clarificationNote: .blue
        case .architectureSummary, .architectureGeneralChange, .architecturePersistenceChange: .purple
        case .explorationSummary, .explorationFinding: .indigo
        case .reviewSummary, .reviewFinding: .pink
        }
    }
}
