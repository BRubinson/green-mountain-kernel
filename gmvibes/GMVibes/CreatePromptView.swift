import SwiftUI
import GMCCDaemonKit

// Authoring sheet: create a new prompt in an existing session via PROMPT_CREATE
// (the daemon allocates the per-session seq atomically — no client-side id
// derivation). Captures name + backstory/goal/detail + a kbite multi-select
// (pre-seeded from the session-scope registry; options from KBITE_LIST
// all:true); selected kbites are registered at prompt scope after creation.
struct CreatePromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GMCCEnvironment.self) private var gmcc

    let store: SessionStore
    // Parent session's backstory, inherited into the new prompt at sheet-open
    // (pre-filled, editable — the prompt's backstory may then diverge).
    let sessionBackstory: String

    @State private var name: String = ""
    @State private var backstory: String = ""
    @State private var didSeedBackstory = false
    @State private var goal: String = ""
    @State private var detail: String = ""
    @State private var availableKbites: [String] = []
    @State private var selectedKbites: Set<String> = []
    @State private var isSaving = false
    @State private var errorText: String?

    // Code derives from the TRIMMED name so code and stored name agree.
    private var segment: String {
        CkfsPathResolver.slug(name.trimmingCharacters(in: .whitespaces))
    }
    private var canSave: Bool { !segment.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Name", text: $name)
                    if !segment.isEmpty {
                        LabeledContent("Code", value: segment)
                    }
                }
                Section("Backstory") {
                    TextEditor(text: $backstory).frame(minHeight: 60).font(.body)
                }
                Section("Goal") {
                    TextEditor(text: $goal).frame(minHeight: 80).font(.body)
                }
                Section("Detail") {
                    TextEditor(text: $detail).frame(minHeight: 100).font(.body)
                }
                Section("KBites") {
                    if availableKbites.isEmpty {
                        Text("No kbites in the GMCC database yet.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(availableKbites, id: \.self) { kbite in
                            Toggle(kbite, isOn: Binding(
                                get: { selectedKbites.contains(kbite) },
                                set: { on in
                                    if on { selectedKbites.insert(kbite) } else { selectedKbites.remove(kbite) }
                                }
                            ))
                        }
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red).font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await save() } }.disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .task {
            await loadKbites()
            // Inherit the session backstory once; never clobber user edits on re-entry.
            if !didSeedBackstory { backstory = sessionBackstory; didSeedBackstory = true }
        }
    }

    // MARK: - KBite options

    private func loadKbites() async {
        // Session-scope registry seeds the preselection (kbite inheritance).
        let sessionCodes = (try? await GMCCDaemonService.shared.listKbites(
            scope: .session, ownerUuid: store.sessionUuid))?.map(\.code) ?? []
        let names = (try? await GMCCDaemonService.shared.listKbites(
            scope: .session, ownerUuid: store.sessionUuid, all: true))?.map(\.code) ?? []
        // Always surface inherited kbites even if the registry list misses them.
        let preselected = Set(sessionCodes)
        let merged = Set(names).union(preselected)
        availableKbites = merged.sorted()
        selectedKbites = preselected
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        errorText = nil
        let service = GMCCDaemonService.shared
        let kbites = availableKbites.filter { selectedKbites.contains($0) }   // stable order
        do {
            // Code passed EXPLICITLY — a nil code defaults to "p{seq}".
            // ckfsRelativeStoragePath stays nil: the daemon allocates seq
            // atomically and derives the slugged path itself (v8); the
            // returned row's path is the only folder the resolver (and the
            // daemon's MemoryWatcher) will ever look at.
            let row = try await service.createPrompt(PromptCreateRequest(
                sessionUuid: store.sessionUuid,
                code: segment,
                name: name.trimmingCharacters(in: .whitespaces),
                backstory: backstory,
                goal: goal,
                detail: detail
            ))
            for code in kbites {
                _ = try? await service.addKbite(scope: .prompt, ownerUuid: row.uuid, code: code)
            }
            // Give the prompt its filesystem presence (memory/ for bot
            // artifacts) — the daemon owns the row, the app owns the folder.
            // Created at the daemon-returned storage path VERBATIM: the
            // daemon's MemoryWatcher matches that string exactly, so a slugged
            // folder of our own would never receive PROMPT_MEMORY_CHANGED
            // (spaces/capitals in the dirname are the accepted cost). An
            // empty storage path creates NOTHING: the resolver has no
            // guessing legs, so a conventionally-named folder could never be
            // found again.
            if let root = gmcc[.ckfsRoot], !root.isEmpty,
               !row.ckfsRelativeStoragePath.isEmpty {
                let memory = URL(fileURLWithPath: root, isDirectory: true)
                    .appendingPathComponent(row.ckfsRelativeStoragePath, isDirectory: true)
                    .appendingPathComponent("memory", isDirectory: true)
                try? FileManager.default.createDirectory(
                    at: memory, withIntermediateDirectories: true)
            }
            await store.refresh()
            isSaving = false
            dismiss()
        } catch let error as DaemonError {
            errorText = error.userMessage
            isSaving = false
        } catch {
            errorText = String(describing: error)
            isSaving = false
        }
    }

}
