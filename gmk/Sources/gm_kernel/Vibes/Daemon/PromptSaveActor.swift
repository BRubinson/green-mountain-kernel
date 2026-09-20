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

    init(promptUuid: String, version: Int64) {
        self.promptUuid = promptUuid
        self.version = version
    }

    /// Adopt an externally-refreshed row's version as the new expected base
    /// (after the UI accepts a remote change or resolves a conflict).
    /// MONOTONIC: the actor is shared by every pane on this prompt, so a pane
    /// holding a stale snapshot must never rewind a peer's version thread.
    func adoptVersion(_ newVersion: Int64) {
        version = max(version, newVersion)
    }

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

/// Reference-backed dirty-state holder for one open prompt. The editor pane is
/// a value-type View whose @State is unreadable after teardown; the box holds
/// the latest unsaved draft + the save actor by reference, so the teardown and
/// quit flush paths never touch view state.
@MainActor
final class PromptDraftBox {
    let promptKey: String
    var saver: PromptSaveActor?
    private(set) var pendingDraft: PromptEditHistory.EditState?

    init(promptKey: String) {
        self.promptKey = promptKey
    }

    var isDirty: Bool { pendingDraft != nil }

    func markDirty(_ state: PromptEditHistory.EditState) {
        pendingDraft = state
    }

    func markSaved(_ state: PromptEditHistory.EditState) {
        if pendingDraft == state { pendingDraft = nil }
    }

    /// Best-effort teardown/quit flush — silent (banners are gone with the
    /// view); a conflict or lock here just leaves the draft pending.
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

    func register(_ box: PromptDraftBox) {
        boxes[box.promptKey] = box
    }

    func unregister(_ key: String) {
        boxes[key] = nil
    }

    var hasDirtyDrafts: Bool {
        boxes.values.contains(where: \.isDirty)
    }

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

    /// The kernel this process hosts, if it does. Assigned once by
    /// `GMVibesApp.init` — the delegate is constructed by
    /// `@NSApplicationDelegateAdaptor` before the services exist, so it cannot
    /// build its own.
    ///
    /// WEAK IS WRONG HERE and strong is deliberate: the whole job is to run
    /// during termination, which is exactly when other references are going
    /// away.
    var services: GMVibesServices?

    /// Termination is ordered: flush dirty prompt drafts on a bounded deadline, THEN stop the
    /// kernel (listener down, DAEMON_STOP, WAL checkpointed, database closed, socket and
    /// pidfile unlinked). The flush is a write and the stop closes the database.
    ///
    /// The deadline does not gate on the flush, because the save path can bottom out in
    /// blocking I/O and a quit must never be hostage to it. Kernel shutdown runs on BOTH
    /// completion paths: a flush that timed out must still close the database, or the WAL is
    /// left for the next boot to recover.
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
