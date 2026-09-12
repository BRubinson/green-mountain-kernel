import SwiftUI
import GMCCDaemonKit

/// The "Add dope scope" modal: pick entities from the workspace's bound dope
/// scope and land them as dopeEntity cards — plus the scope's
/// dopeScopePersistenceLayer container when the canvas doesn't hold one yet —
/// in ONE batch through the edit-session funnel. Deliberately no existence
/// validation: bindings are ghost-tolerant codes, and the daemon renders an
/// absent code as a ghost card, never an error.
struct DiagramDopeScopeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: DiagramWorkspace

    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 400, height: 480)
    }

    private var header: some View {
        HStack {
            Text("Add Dope Scope Entities").font(.headline)
            Spacer(minLength: 0)
            if let dope = workspace.dope {
                Text(dope.tree.body.code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if let dope = workspace.dope {
            let onCanvas = presentEntityCodes(scopeCode: dope.tree.body.code)
            List {
                ForEach(dope.tree.domains, id: \.identity.uuid) { domain in
                    Section(domain.body.name) {
                        ForEach(domain.entities, id: \.identity.uuid) { entity in
                            let code = "\(domain.body.code).\(entity.body.code)"
                            let present = onCanvas.contains(code)
                            Toggle(isOn: Binding(
                                get: { present || selected.contains(code) },
                                set: { on in
                                    if on { selected.insert(code) }
                                    else { selected.remove(code) }
                                }
                            )) {
                                HStack(spacing: 6) {
                                    Text(entity.body.name)
                                    Text(code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(present)
                            .help(present ? "Already on the canvas" : code)
                        }
                    }
                }
            }
            .listStyle(.inset)
        } else {
            ContentUnavailableView(
                "No Dope Scope Bound",
                systemImage: "square.stack.3d.up.slash",
                description: Text("This diagram has no resolvable dope scope "
                    + "binding — create diagrams over a dope scope to add its "
                    + "entities here."))
        }
    }

    private var footer: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Cancel") { dismiss() }
            Button("Add \(selected.count) Entit\(selected.count == 1 ? "y" : "ies")") {
                commit()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty || workspace.dope == nil)
        }
        .padding(12)
    }

    /// Entity codes already carded under this scope's container(s) — shown
    /// checked-and-disabled so the sheet reads as "what's on the canvas",
    /// and a second add of the same code takes an explicit different path.
    private func presentEntityCodes(scopeCode: String) -> Set<String> {
        var codes: Set<String> = []
        for element in workspace.tree.elements {
            guard case .dopeScopePersistenceLayer(let payload) = element.payload,
                  payload.dopeScopeCode == scopeCode else { continue }
            for child in element.children {
                if case .dopeEntity(let entity) = child.payload {
                    codes.insert(entity.entityCode)
                }
            }
        }
        return codes
    }

    /// The scope's container element, when the canvas already holds one.
    private func container(scopeCode: String) -> DiagramElementNode? {
        workspace.tree.elements.first { element in
            if case .dopeScopePersistenceLayer(let payload) = element.payload {
                return payload.dopeScopeCode == scopeCode
            }
            return false
        }
    }

    /// ONE batch: the container add (when absent) via clientRef, then every
    /// picked entity parented under it — the same in-batch parenting the
    /// drawing layer's lazy creation uses. New cards stack in a fresh column
    /// to the right of the current content, so they never land under it.
    private func commit() {
        guard let dope = workspace.dope, !selected.isEmpty else { return }
        let scopeCode = dope.tree.body.code
        let session = workspace.editSession!
        let existing = container(scopeCode: scopeCode)

        let containerRef = "scope_add"
        var parentUuid: String?
        var parentCenter = CGPoint.zero
        if let existing {
            parentUuid = existing.identity.uuid
            parentCenter = CGPoint(x: existing.base.centerX, y: existing.base.centerY)
        } else {
            session.stage(.elementAdd(DiagramElementAdd(
                clientRef: containerRef,
                code: "scope_\(scopeCode)",
                name: dope.tree.body.name,
                centerX: 0, centerY: 0, elementZ: 0,
                payload: .dopeScopePersistenceLayer(
                    DopeScopePersistenceLayerPayload(dopeScopeCode: scopeCode)))))
        }

        let bounds = workspace.resolved.contentBounds
        let columnX = (bounds.isEmpty ? 0 : bounds.maxX) + 200
        var y = bounds.isEmpty ? 0 : bounds.minY
        for code in selected.sorted() {
            // Child centers are PARENT-LOCAL (the accumulated-transform
            // contract), so diagram-space targets shift by the container's
            // own center.
            let local = CGPoint(x: columnX - parentCenter.x, y: y - parentCenter.y)
            session.stage(.elementAdd(DiagramElementAdd(
                parentElementUuid: parentUuid,
                parentClientRef: parentUuid == nil ? containerRef : nil,
                name: code,
                centerX: local.x, centerY: local.y,
                payload: .dopeEntity(DopeEntityPayload(entityCode: code)))))
            y += 180
        }
        Task { await workspace.flush() }
    }
}
