import Foundation
import Observation
import GMCCDaemonKit

/// Per-session-window read state: the SessionRow, its prompt stubs, change
/// summaries, and a full PromptGetResponse per stub. The prefetch is
/// deliberately SEQUENTIAL — the daemon serves every request on one serial
/// queue with no fairness, so a burst here would stall the user's terminal
/// `gm` calls. Prefetched bodies serve prose search, the editor's content,
/// and the memory-root derivation in one cache.
@Observable @MainActor
final class SessionStore {
    let sessionUuid: String

    private(set) var session: SessionRow?
    private(set) var prompts: [PromptStub] = []
    private(set) var changeSummary: ChangeSummary?
    private(set) var promptChanges: [PromptChangeSummary] = []
    /// Full prompt payloads by prompt uuid.
    private(set) var promptDetails: [String: PromptGetResponse] = [:]
    private(set) var lastError: String?
    private(set) var hasLoaded = false

    private let service = GMCCDaemonService.shared
    private var inFlight: Task<Void, Never>?

    init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
    }

    /// Coalesced: the store is shared by every window on this session, and
    /// each window's refresh loop calls this per invalidation — N windows must
    /// still cost ONE SESSION_GET + one sequential prefetch.
    func refresh() async {
        if let running = inFlight {
            await running.value
            return
        }
        let task = Task { await self.performRefresh() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performRefresh() async {
        do {
            let response = try await service.getSession(sessionUuid: sessionUuid)
            if session != response.session { session = response.session }
            // Prompts come from PROMPT_LIST with_reports — its enrichment
            // block precomputes every prompt's clarify/arch gate in one round
            // trip (SESSION_GET stays the sole source of the row + change
            // summaries). SEQUENTIAL after it, never concurrent: the daemon's
            // single serial queue has no fairness.
            let enriched = try await service.listPrompts(
                sessionUuid: sessionUuid, withReports: true)
            let sorted = enriched.sorted { $0.seq > $1.seq }
            if prompts != sorted { prompts = sorted }
            if changeSummary != response.changeSummary { changeSummary = response.changeSummary }
            if promptChanges != response.promptChanges { promptChanges = response.promptChanges }
            if lastError != nil { lastError = nil }
            hasLoaded = true

            // Drop details for prompts that no longer exist.
            let live = Set(sorted.map(\.uuid))
            for gone in promptDetails.keys where !live.contains(gone) {
                promptDetails[gone] = nil
            }
            // Sequential prefetch: stale (version drift) or missing details only.
            for stub in sorted {
                if Task.isCancelled { return }
                if promptDetails[stub.uuid]?.prompt.version != stub.version {
                    await refreshPrompt(uuid: stub.uuid)
                }
            }
        } catch let error as DaemonError {
            lastError = error.userMessage
            hasLoaded = true
        } catch {
            lastError = String(describing: error)
            hasLoaded = true
        }
    }

    func refreshPrompt(uuid: String) async {
        do {
            let response = try await service.getPrompt(promptUuid: uuid)
            if promptDetails[uuid] != response { promptDetails[uuid] = response }
        } catch {
            // Targeted load failure is non-fatal; the stub row still renders.
        }
    }

}
