import Foundation
import AppKit
import GMCCDaemonKit

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
            let row = try await service.updatePromptContent(PromptUpdateContentRequest(
                promptUuid: promptUuid,
                expectedVersion: version,
                backstory: backstory,
                goal: goal,
                detail: detail
            ))
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
            backstory: draft.backstory, goal: draft.goal, detail: draft.detail)
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
        boxes.values.contains { $0.isDirty }
    }

    func flushAll() async {
        // Concurrent: N open prompts must not serialize N socket timeouts.
        await withTaskGroup(of: Void.self) { group in
            for box in boxes.values where box.isDirty {
                group.addTask { @MainActor in await box.flush() }
            }
        }
    }
}

final class GMVibesAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let registry = PromptFlushRegistry.shared
        guard registry.hasDirtyDrafts else { return .terminateNow }
        // Reply on a deadline that never awaits the flush: the save path
        // bottoms out in non-cancellable blocking socket I/O (no SO_RCVTIMEO),
        // so gating the reply on it could hang the quit indefinitely. Both
        // completions run on the main actor, so the fired-once flag is safe.
        var replied = false
        let finish = {
            if !replied {
                replied = true
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
