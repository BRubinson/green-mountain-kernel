import SwiftUI
import GMCCDaemonKit

/// DOPE_INIT cannot be a bare button: it requires a validated code + name.
/// The code is checked client-side on every keystroke via the kit's public
/// `DopeCode.validateCode` (^[a-z][a-z0-9_]*$, no `__`, no trailing `_`,
/// ≤64 bytes) so no daemon round trip is ever spent on a malformed code.
/// Idempotent server-side (create-or-return, the archOpen precedent).
struct DopeInitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: DopeStore
    let key: DopeStore.Key
    let forPrompt: Bool
    /// Codes already known at this target (own + fallback level), so the
    /// user never types blind. Informational union — collision semantics use
    /// `sameTypeCodes` only.
    let siblingCodes: [String]
    /// Codes at the scope TYPE this sheet creates. The daemon's idempotent
    /// create-or-return is scoped per (scope_type, promptUuid): only a
    /// same-type match is "opened"; an other-type match yields a separate
    /// new scope that merely shares the code.
    let sameTypeCodes: [String]

    @State private var code = ""
    @State private var name = ""
    @State private var descriptionText = ""
    @State private var submitting = false
    @State private var submitError: String?

    private var codeIssue: String? {
        guard !code.isEmpty else { return nil }
        do {
            try DopeCode.validateCode(code, field: "scope code")
            return nil
        } catch {
            return String(describing: error)
        }
    }

    /// Server-side init is create-or-return, so a collision is not an error —
    /// but the user deserves to know they are OPENING, not creating.
    /// Informational only: `canSubmit` deliberately ignores it.
    private var collidesWithSibling: Bool { sameTypeCodes.contains(code) }
    /// The code exists only at the OTHER scope type — initializing here
    /// creates a separate scope, not a link to it.
    private var shadowsOtherType: Bool {
        !collidesWithSibling && siblingCodes.contains(code)
    }

    private var canSubmit: Bool {
        !code.isEmpty && codeIssue == nil && !name.isEmpty && !submitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(forPrompt ? "Initialize Prompt Dope Scope" : "Initialize Session Dope Scope")
                .font(.title3.weight(.semibold))
            Text(forPrompt
                ? "Creates a PROMPT-typed dope scope for this prompt."
                : "Creates this session's SESSION_BASE dope scope.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Code (e.g. game_model)", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                if let codeIssue {
                    Label(codeIssue, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !siblingCodes.isEmpty {
                    Text("Existing codes: \(siblingCodes.joined(separator: ", "))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if collidesWithSibling {
                    Label("A scope with this code already exists — Initialize will open it, never overwrite it.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if shadowsOtherType {
                    Label(forPrompt
                        ? "A session-base scope uses this code — initializing here creates a separate prompt scope, not a link to it."
                        : "A prompt scope uses this code — initializing here creates a separate session-base scope, not a link to it.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            if let submitError {
                Label(submitError, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(submitting ? "Initializing…" : "Initialize") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func submit() {
        submitting = true
        submitError = nil
        Task {
            do {
                try await store.initScope(
                    key: key, code: code, name: name, description: descriptionText)
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
