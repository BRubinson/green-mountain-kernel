import SwiftUI
import GMCCDaemonKit

/// Read-only architecture section (ARCH_GET): summary body + status,
/// persistence-first change rows — RENDERED IN WIRE ORDER, never re-sorted
/// (persistence-before-general is the daemon's positional contract) — each
/// decorated with derived implementation state, then unplanned changes (scope
/// drift) and the ordering audit. All arch writes stay bot/CLI-side.
struct ArchitecturePane: View {
    let phase: PromptPhaseStore.Phase<ArchGetResponse>

    var body: some View {
        switch phase {
        case .idle:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading architecture…").font(.callout).foregroundStyle(.secondary)
            }
        case .absent:
            // Stays READ-ONLY: every arch write is bot/CLI-side by design.
            Label("Not opened yet — run the bot to start architecture.",
                  systemImage: "square.stack.3d.up.slash")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        case .loaded(let response):
            content(response)
        }
    }

    @ViewBuilder
    private func content(_ response: ArchGetResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                statusChip(response.summary.architectureStatus)
                orderingChip(response.orderingRespected)
                Spacer()
                Text(progressLabel(response))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !response.summary.body.isEmpty {
                Text(response.summary.body)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.purple.opacity(0.06), in: .rect(cornerRadius: 8))
            }

            if !response.persistenceChanges.isEmpty {
                sectionHeader("Persistence Changes")
                ForEach(response.persistenceChanges, id: \.uuid) { change in
                    persistenceRow(change)
                }
            }

            if !response.generalChanges.isEmpty {
                sectionHeader("Changes")
                ForEach(response.generalChanges, id: \.uuid) { change in
                    generalRow(change)
                }
            }

            if !response.unplannedChanges.isEmpty {
                sectionHeader("Unplanned Changes (scope drift)")
                ForEach(response.unplannedChanges, id: \.path) { change in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(change.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(change.changeCount) changes")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func persistenceRow(_ change: ArchPersistenceChangeRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                implementationIcon(change.implementation)
                Text(change.className).font(.callout.weight(.medium))
                Text(change.filePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                implementationLabel(change.implementation)
            }
            Text(change.reasonBrief)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
            if !change.fields.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(change.fields, id: \.uuid) { field in
                        HStack(spacing: 6) {
                            Text(field.fieldName).font(.caption.monospaced())
                            Text(field.dataType)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if field.nullable { fieldTag("nullable") }
                            if field.isForeignKey { fieldTag("FK → \(field.fkTarget ?? "?")") }
                            if field.isIndexed { fieldTag("indexed") }
                        }
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 3)
    }

    private func generalRow(_ change: ArchGeneralChangeRow) -> some View {
        DisclosureGroup {
            Text(change.changeCode)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    implementationIcon(change.implementation)
                    Text(change.filePath)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    depthBadge(change.changeDepth)
                    Spacer()
                    implementationLabel(change.implementation)
                }
                Text(change.reasonBrief)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }
    }

    private func fieldTag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(.quaternary.opacity(0.5), in: .capsule)
            .foregroundStyle(.secondary)
    }

    private func depthBadge(_ depth: String) -> some View {
        Text(depth)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.purple.opacity(0.12), in: .capsule)
            .foregroundStyle(.purple)
    }

    @ViewBuilder
    private func implementationIcon(_ state: ChangeImplementationState) -> some View {
        if state.fileChangeCount > 0 {
            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        } else {
            Image(systemName: "circle.dashed").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func implementationLabel(_ state: ChangeImplementationState) -> some View {
        if state.fileChangeCount > 0 {
            Text("\(state.fileChangeCount) edits")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else {
            Text("planned")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func progressLabel(_ response: ArchGetResponse) -> String {
        let planned = response.persistenceChanges.count + response.generalChanges.count
        let touched = response.persistenceChanges.filter { $0.implementation.fileChangeCount > 0 }.count
            + response.generalChanges.filter { $0.implementation.fileChangeCount > 0 }.count
        return "\(touched)/\(planned) implemented"
    }

    @ViewBuilder
    private func statusChip(_ status: ArchitectureStatus?) -> some View {
        let (label, color): (String, Color) = switch status {
        case .drafting: ("Drafting", .orange)
        case .proposed: ("Proposed", .blue)
        case .approved: ("Approved", .green)
        case .none: ("—", .gray)
        }
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }

    /// The persistence-first execution audit: nil = not assessable (either
    /// side empty/untouched) — a distinct third state, not "false".
    @ViewBuilder
    private func orderingChip(_ respected: Bool?) -> some View {
        switch respected {
        case .some(true):
            Label("persistence-first", systemImage: "checkmark.seal")
                .font(.caption2)
                .foregroundStyle(.green)
        case .some(false):
            Label("ordering violated", systemImage: "xmark.seal")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .none:
            // The third state must be visibly distinct from "chip missing".
            Label("ordering not assessable", systemImage: "seal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
