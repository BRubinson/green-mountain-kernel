import Foundation
import AppKit

/// Per-prompt serialized writer over PROMPT_UPDATE_CONTENT. Actor isolation IS
/// the serialization; every successful write threads the returned row's
/// version into the next request, and `lastWrittenVersion` is the echo
/// watermark — a refetched row at or below it is our own UPDATE_PROMPT echo
/// (the event itself carries no version or origin, so the comparison happens
/// on the refetched row).
actor PromptSaveActor {
    enum Outcome: Equatable {
        case saved(Int64)
        case conflict
        case locked
        case failed(String)
    }

    private let service = GMCCDaemonService.shared
    private let promptUuid: String
    private var version: Int64
    private(set) var lastWrittenVersion: Int64 = 0

    /// Creates a save actor for a prompt.
    ///
    /// - Parameters:
    ///   - promptUuid: The uuid of the prompt to save.
    ///   - version: The version of the initial read.
    init(promptUuid: String, version: Int64) {
        self.promptUuid = promptUuid
        self.version = version
    }

    /// Adopt an externally-refreshed version as the new expected base.
    ///
    /// Called after the UI accepts a remote change or resolves a conflict.
    /// MONOTONIC: the actor is shared by every pane on this prompt, so a pane
    /// holding a stale snapshot must never rewind a peer's version thread.
    ///
    /// - Parameter newVersion: The externally-refreshed row version.
    func adoptVersion(_ newVersion: Int64) {
        version = max(version, newVersion)
    }

    /// Save the prompt's content with optimistic concurrency control.
    ///
    /// - Parameters:
    ///   - backstory: The prompt's backstory section.
    ///   - goal: The prompt's goal section.
    ///   - detail: The prompt's detail section.
    /// - Returns: A `PromptSaveActor.Outcome` representing the save result.
    func save(backstory: String, goal: String, detail: String) async -> Outcome {
        do {
            let row = try await service.updatePromptContent(
                PromptUpdateContentRequest(
                    promptUuid: promptUuid,
                    expectedVersion: version,
                    backstory: backstory,
                    goal: goal,
                    detail: detail
                )
            )
            version = row.version
            lastWrittenVersion = row.version
            return .saved(row.version)
        } catch let error as DaemonError {
            switch error {
            case .versionConflict: return .conflict
            case .contentLocked: return .locked
            case .server(let code, let message): return .failed("\(code): \(message)")
            case .unreachable(let m), .transport(let m): return .failed(m)
            default: return .failed(String(describing: error))
            }
        } catch {
            return .failed(String(describing: error))
        }
    }
}

/// Reference-backed dirty-state holder for one open prompt.
///
/// The editor pane is a value-type View whose @State is unreadable after
/// teardown; the box holds the latest unsaved draft + the save actor by
/// reference, so the teardown and quit flush paths never touch view state.
@MainActor
final class PromptDraftBox {
    let promptKey: String
    var saver: PromptSaveActor?
    private(set) var pendingDraft: PromptEditHistory.EditState?

    /// Creates a draft box for a prompt.
    ///
    /// - Parameter promptKey: The key identifying the prompt.
    init(promptKey: String) {
        self.promptKey = promptKey
    }

    var isDirty: Bool { pendingDraft != nil }

    /// Mark the draft as having unsaved changes.
    ///
    /// - Parameter state: The current edit state to store as pending.
    func markDirty(_ state: PromptEditHistory.EditState) {
        pendingDraft = state
    }

    /// Mark the draft as saved if it matches the pending state.
    ///
    /// - Parameter state: The edit state that was just saved.
    func markSaved(_ state: PromptEditHistory.EditState) {
        if pendingDraft == state { pendingDraft = nil }
    }

    /// Best-effort flush of the pending draft during teardown or quit.
    ///
    /// Silent: banners are gone with the view. A conflict or lock just
    /// leaves the draft pending for the next opportunity to save.
    func flush() async {
        guard let saver, let draft = pendingDraft else { return }
        let outcome = await saver.save(
            backstory: draft.backstory,
            goal: draft.goal,
            detail: draft.detail
        )
        if case .saved = outcome, pendingDraft == draft {
            pendingDraft = nil
        }
    }
}

/// App-level registry of open prompts' draft boxes, drained with a bounded
/// deadline before termination (the documented AppKit mechanism replaces the
/// old synchronous main-thread yaml write in onDisappear).
@MainActor
final class PromptFlushRegistry {
    static let shared = PromptFlushRegistry()

    private var boxes: [String: PromptDraftBox] = [:]

    /// Register a draft box with the flush registry.
    ///
    /// - Parameter box: The draft box to register.
    func register(_ box: PromptDraftBox) {
        boxes[box.promptKey] = box
    }

    /// Unregister a draft box from the flush registry.
    ///
    /// - Parameter key: The key of the draft box to unregister.
    func unregister(_ key: String) {
        boxes[key] = nil
    }

    var hasDirtyDrafts: Bool {
        boxes.values.contains(where: \.isDirty)
    }

    /// Flush all dirty draft boxes concurrently.
    ///
    /// - Note: Concurrent flushes ensure N open prompts do not serialize N socket timeouts.
    func flushAll() async {
        // Concurrent: N open prompts must not serialize N socket timeouts.
        await withTaskGroup(of: Void.self) { group in
            for box in boxes.values where box.isDirty {
                group.addTask { await box.flush() }
            }
        }
    }
}

final class GMVibesAppDelegate: NSObject, NSApplicationDelegate {
    override init() { super.init() }

    /// The kernel this process hosts, if it does.
    ///
    /// Assigned once by `GMVibesApp.init` — the delegate is constructed by
    /// `@NSApplicationDelegateAdaptor` before the services exist, so it cannot build its own.
    /// WEAK IS WRONG HERE and strong is deliberate: the whole job is to run during termination,
    /// which is exactly when other references are going away.
    var services: GMVibesServices?

    /// Handle application termination with graceful shutdown of the kernel.
    ///
    /// Termination is ordered: flush dirty prompt drafts on a bounded deadline,
    /// THEN stop the kernel (listener down, DAEMON_STOP, WAL checkpointed,
    /// database closed, socket and pidfile unlinked). The flush is a write and
    /// the stop closes the database, so the deadline does not gate on the flush;
    /// the save path can bottom out in blocking I/O and a quit must never be
    /// hostage to it. Kernel shutdown runs on both completion paths: a
    /// timed-out flush still closes the database, or the WAL is left for the
    /// next boot to recover.
    ///
    /// - Parameter sender: The application requesting termination.
    /// - Returns: `terminateNow` if no dirty drafts exist; `terminateLater` otherwise.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let registry = PromptFlushRegistry.shared
        guard registry.hasDirtyDrafts else {
            services?.shutdownKernel()
            return .terminateNow
        }
        // Both completions run on the main actor, so the fired-once flag is safe.
        var replied = false
        let finish = { [services] in
            if !replied {
                replied = true
                services?.shutdownKernel()
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        Task { @MainActor in
            await registry.flushAll()
            finish()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            finish()
        }
        return .terminateLater
    }
}
