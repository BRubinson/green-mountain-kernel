import SwiftUI
import GMCCDaemonKit

/// Project settings — today a single field, deliberately shaped to grow.
///
/// PROJECT_UPDATE is the only project-level mutation the daemon offers, and
/// `primary_project_branch` (BASE_DOPED_BRANCH) is its only settable field.
/// `ProjectUpdateRequest` keeps that field Optional so the request can gain
/// more without a wire bump, which is why this sheet sends ONLY what changed
/// rather than echoing the whole row back.
///
/// The sheet takes a `projectUuid`, not a `ProjectRow`. The tree refreshes on
/// every topology event, so a row captured at presentation time can go stale
/// while the user is still typing — and the optimistic lock would then reject
/// a save the user had no way to understand. Re-reading from the catalog on
/// submit means we always lock against the version the UI is showing.
struct ProjectSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalog

    let projectUuid: String

    @State private var branch: String = ""
    @State private var loaded = false
    @State private var submitting = false
    @State private var submitError: String?

    private var project: ProjectRow? { catalog.project(uuid: projectUuid) }

    /// Mirrors the daemon's own rule (Store+Project: a branch name is an
    /// identity, not prose) so a blank never costs a round trip.
    private var trimmedBranch: String {
        branch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isBlank: Bool { trimmedBranch.isEmpty }

    private var isUnchanged: Bool {
        guard let project else { return true }
        return trimmedBranch == project.primaryProjectBranch
    }

    private var canSubmit: Bool { !isBlank && !isUnchanged && !submitting }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Project Settings")
                .font(.title3.weight(.semibold))

            if let project {
                Text(project.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                identityBlock(project)
                Divider()
                branchField(project)
            } else {
                // The project left the catalog under us (deleted, or the
                // daemon went away mid-edit). Say so rather than showing an
                // editable field that cannot save.
                Label("This project is no longer in the catalog.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let submitError {
                Label(submitError, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(submitting ? "Saving…" : "Save") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            // Seed once. Re-seeding on every catalog refresh would overwrite
            // what the user is typing the moment any unrelated topology
            // event lands.
            guard !loaded, let project else { return }
            branch = project.primaryProjectBranch
            loaded = true
        }
    }

    @ViewBuilder
    private func identityBlock(_ project: ProjectRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LabeledContent("Code") {
                Text(project.code).font(.caption.monospaced())
            }
            LabeledContent("Git repo") {
                Text(project.gitRepoName).font(.caption.monospaced())
            }
            LabeledContent("CKFS path") {
                Text(project.ckfsRelativeStoragePath)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func branchField(_ project: ProjectRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Primary project branch")
                .font(.callout.weight(.medium))
            TextField("main", text: $branch)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .disabled(submitting)
                .onSubmit { if canSubmit { submit() } }

            Text("The BASE_DOPED_BRANCH: the branch whose SESSION_INSTANCE dope scope may promote into this project's BASE_PROJECT scope. Applies across every instance of the project.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isBlank {
                Label("A branch name cannot be blank.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isUnchanged {
                Label("Currently \(project.primaryProjectBranch).",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func submit() {
        // Re-read: the row this locks against must be the one on screen now,
        // not the one that existed when the sheet opened.
        guard let current = project else {
            submitError = "This project is no longer in the catalog."
            return
        }
        submitting = true
        submitError = nil
        Task {
            do {
                try await catalog.setPrimaryBranch(
                    projectUuid: current.uuid,
                    expectedVersion: current.version,
                    branch: trimmedBranch)
                dismiss()
            } catch let error as DaemonError {
                submitError = error.userMessage
            } catch {
                submitError = String(describing: error)
            }
            submitting = false
        }
    }
}
