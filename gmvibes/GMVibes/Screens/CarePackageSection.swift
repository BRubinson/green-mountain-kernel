import SwiftUI
import GMCCDaemonKit

/// The care package expanded — the clarified-intent bundle a multi-agent clarify
/// flow curates, rendered as its children instead of as a count.
///
/// Replaces `ClarificationPane.carePackageBlock` and the literal
/// "N dope · M kbite · K exploration refs" line it ended with. Every field here
/// was already decoded by CLARIFY_GET and thrown away; the expansion introduces
/// NO new fetch and no second pane — it reuses the one
/// ClarificationPane -> PromptPhaseStore.clarification data flow, so the
/// `package_ref_add` events that already invalidate the prompt keep this live.
///
/// READ-ONLY. Every care-package write stays bot/CLI-side; the app's only
/// clarify write is answering a question.
///
/// Markdown rendering for the intent and the curated bodies is deliberately cut,
/// matching every other report body in the app: plain selectable `Text`.
struct CarePackageSection: View {
    let package: CarePackageRow
    let staleness: CarePackageStaleness?

    /// Refs are only complete at `ready` — while the curators are still adding
    /// children, what is on screen is a partial set, and says so.
    private var isBuilding: Bool { package.status == "building" }

    private var ghosts: Set<String> { Set(staleness?.ghostDotPaths ?? []) }

    private var hasRefs: Bool {
        !package.dopeRefs.isEmpty || !package.kbiteRefs.isEmpty
            || !package.explorationRefs.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Care Package")
                    .font(.subheadline.weight(.semibold))
                packageChip(package.status)
                // nil on a daemon that predates the additive staleness field —
                // the badge simply renders nothing, same as an undrifted scope.
                DopeStalenessBadge(staleness: staleness)
                Spacer()
            }

            if !package.clarifiedIntent.isEmpty {
                Text(package.clarifiedIntent)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.blue.opacity(0.06), in: .rect(cornerRadius: 8))
            }

            if hasRefs {
                VStack(alignment: .leading, spacing: 10) {
                    if isBuilding {
                        Text("curating…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !package.dopeRefs.isEmpty {
                        sectionHeader("Dope Refs")
                        dopeRefs
                    }
                    if !package.kbiteRefs.isEmpty {
                        sectionHeader("KBites")
                        kbiteRefs
                    }
                    if !package.explorationRefs.isEmpty {
                        sectionHeader("Exploration")
                        explorationRefs
                    }
                }
            }
        }
    }

    // MARK: Dope refs

    /// Dot-path chips against the live scope: a ghost is struck through, exactly
    /// as in BriefingPane, because it is the same chip. The curator's `note` is
    /// the whole reason a path made the package, so it rides under the chip.
    private var dopeRefs: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(package.dopeRefs, id: \.uuid) { ref in
                VStack(alignment: .leading, spacing: 2) {
                    DopeDotPathChip(path: ref.dopeCode,
                                    isGhost: ghosts.contains(ref.dopeCode))
                    if let note = ref.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.leading, 7)
                    }
                }
            }
        }
    }

    // MARK: KBite refs

    /// `brief` is denormalized onto the ref at package-complete, so the uuid is
    /// only ever the fallback — the BriefingPane precedent, empty treated as absent.
    private var kbiteRefs: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(package.kbiteRefs, id: \.uuid) { ref in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text((ref.brief?.isEmpty ?? true) ? ref.kbiteResourceFileUuid : ref.brief!)
                        .font(.caption)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
        }
    }

    // MARK: Exploration refs

    /// CURATED COPIES. The source finding is never re-read — `sourceFindingUuid`
    /// is a soft provenance ref that survives source pruning via SET NULL, so its
    /// presence is worth a dot and its absence is not worth a word.
    private var explorationRefs: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(package.explorationRefs, id: \.uuid) { ref in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if ref.sourceFindingUuid != nil {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.tertiary)
                                .help("Curated from an exploration finding.")
                        }
                        Text(ref.curatedTitle)
                            .font(.callout.weight(.medium))
                            .textSelection(.enabled)
                        Spacer()
                    }
                    if !ref.curatedBody.isEmpty {
                        Text(ref.curatedBody)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let path = ref.filePath, !path.isEmpty {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: Bits

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func packageChip(_ status: String) -> some View {
        let (label, color): (String, Color) = status == "ready"
            ? ("Ready", .green) : ("Building", .orange)
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}
