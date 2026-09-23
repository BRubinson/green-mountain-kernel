import SwiftUI

/// The post-draft RUN DOCUMENT: one continuous card assembling phase panes.
///
/// Every section embeds its existing pane unchanged, so the panes' contracts
/// ride along with live clarification answer cards and staleness badges. A
/// section renders only when the run left evidence for it. `.absent` renders
/// nothing (/.gm_task prompts never get workflow rows). `.failed` renders one
/// dim caption line.
struct PromptRunDocument: View {
    let stub: PromptStub
    let phases: PromptPhaseStore
    let scope: SessionScope
    let backstory: String
    let goal: String
    let detail: String
    /// The care package's clarified intent, when the run produced one — the
    /// PRIMARY intent text (the frozen goal/detail tuck into a disclosure).
    let clarifiedIntent: String?
    let availableKbites: [String]
    @Binding var selectedKbites: [String]
    /// Find-in-page plumbing from the host pane.
    ///
    /// Segment ids stay "backstory"/"goal"/"detail" — the pane's find
    /// contract, preserved.
    let findQuery: SearchQuery
    let activeLocal: (String) -> Int?

    /// Find-anchor liveness: collapsed Groups don't build anchors for scrollTo.
    ///
    /// Both force open when find query goes active (and stay open when it
    /// clears — a deliberate keep).
    @State private var backstoryExpanded = false
    @State private var originalExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !backstory.isEmpty {
                backstorySection
                Divider()
            }
            intentSection
            phaseSection(
                "Briefing",
                icon: "shippingbox",
                evidence(
                    phases.briefings,
                    stubEvidence: false,
                    hasContent: { !$0.isEmpty }
                )
            ) {
                BriefingPane(phase: phases.briefings)
            }
            phaseSection(
                "Exploration",
                icon: "binoculars",
                evidence(
                    phases.exploration,
                    stubEvidence: stub.reports?.exploration != nil
                )
            ) {
                ExplorationPane(phase: phases.exploration) {
                    await phases.requestFullExploration()
                }
            }
            phaseSection(
                "Clarification",
                icon: "questionmark.bubble",
                evidence(
                    phases.clarification,
                    stubEvidence: stub.reports?.clarification != nil
                )
            ) {
                // `phases` rides along ONLY so the question cards reach
                // `phases.answers` — answering stays live post-draft.
                ClarificationPane(phase: phases.clarification, phases: phases)
            }
            phaseSection(
                "Plan",
                icon: "square.stack.3d.up",
                evidence(
                    phases.architecture,
                    stubEvidence: stub.reports?.architecture != nil
                )
            ) {
                ArchitecturePane(phase: phases.architecture)
            }
            phaseSection(
                "Review",
                icon: "checkmark.seal",
                evidence(
                    phases.review,
                    stubEvidence: stub.reports?.review != nil
                )
            ) {
                ReviewPane(phase: phases.review) {
                    await phases.requestFullReview()
                }
            }
            footerSection
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 12))
        // `initial: true` covers a document constructed while find is
        // already live (the branch flips draft → run document mid-search).
        .onChange(of: findQuery.isActive, initial: true) { _, active in
            if active {
                backstoryExpanded = true
                originalExpanded = true
            }
        }
    }

    // MARK: - Evidence gating

    private enum SectionEvidence: Equatable {
        case hidden
        case failed(String)
        case content
    }

    /// Determines what to render for a phase state.
    ///
    /// Loaded-with-content renders, a non-nil reports stub covers the not-yet-loaded
    /// cold start, absence renders nothing, and failure renders a single dim line.
    ///
    /// - Parameters:
    ///   - phase: The phase state to evaluate.
    ///   - stubEvidence: Whether a reports stub counts as content.
    ///   - hasContent: A predicate determining whether loaded content is non-empty.
    /// - Returns: The evidence for rendering the phase.
    private func evidence<T: Equatable>(
        _ phase: PromptPhaseStore.Phase<T>,
        stubEvidence: Bool,
        hasContent: (T) -> Bool = { _ in true }
    ) -> SectionEvidence {
        switch phase {
        case .idle:
            stubEvidence ? .content : .hidden
        case .absent:
            .hidden
        case .failed(let message):
            .failed(message)
        case .loaded(let value):
            hasContent(value) ? .content : .hidden
        }
    }

    // MARK: - Section chrome

    /// Builds a standardized section container with title and icon.
    ///
    /// An injected divider-and-header rather than a per-section card,
    /// generalized from the editor's refinedSection idiom.
    ///
    /// - Parameters:
    ///   - title: The section title to display.
    ///   - icon: The system icon name for the title label.
    ///   - content: The section content view builder.
    /// - Returns: A styled section view.
    private func documentSection(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Renders a section with evidence-gated visibility and error handling.
    ///
    /// - Parameters:
    ///   - title: The section title to display.
    ///   - icon: The system icon name for the title label.
    ///   - evidence: The evidence state determining visibility.
    ///   - content: The section content view builder.
    /// - Returns: A view rendered according to the evidence state.
    @ViewBuilder
    private func phaseSection(
        _ title: String,
        icon: String,
        _ evidence: SectionEvidence,
        @ViewBuilder content: () -> some View
    ) -> some View {
        switch evidence {
        case .hidden:
            EmptyView()
        case .failed(let message):
            Label("\(title): \(message)", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        case .content:
            documentSection(title, icon: icon, content: content)
            Divider()
        }
    }

    // MARK: - Backstory

    /// Compact and collapsed by default: the backstory is inherited context,
    /// not the run's own record.
    private var backstorySection: some View {
        DisclosureGroup(isExpanded: $backstoryExpanded) {
            HighlightedText(
                source: backstory,
                query: findQuery,
                activeLocalOccurrence: activeLocal("backstory")
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 6)
            .id("backstory")
        } label: {
            Label("Backstory", systemImage: "text.book.closed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Intent

    /// Always renders: the intent is prompt content, gated only on what it holds.
    ///
    /// Clarified intent is PRIMARY when the care package carries one (the human
    /// triple stays reachable in the disclosure beneath — m0025: nothing writes
    /// prompt content past draft); otherwise the frozen goal/detail render
    /// directly.
    @ViewBuilder
    private var intentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let intent = clarifiedIntent {
                HStack(spacing: 8) {
                    Label("Intent", systemImage: "target")
                        .font(.headline)
                    Label("Refined by clarification", systemImage: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                Text(intent)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.blue.opacity(0.06), in: .rect(cornerRadius: 8))
                DisclosureGroup("Original goal & detail", isExpanded: $originalExpanded) {
                    originalGoalDetail
                }
                .font(.caption)
            } else {
                Label("Intent", systemImage: "target")
                    .font(.headline)
                originalGoalDetail
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        Divider()
    }

    private var originalGoalDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Goal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HighlightedText(
                source: goal.isEmpty ? "—" : goal,
                query: findQuery,
                activeLocalOccurrence: activeLocal("goal")
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .id("goal")
            Text("Detail")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HighlightedText(
                source: detail.isEmpty ? "—" : detail,
                query: findQuery,
                activeLocalOccurrence: activeLocal("detail")
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .id("detail")
        }
        .padding(.top, 4)
    }

    // MARK: - Footer

    /// Utility row, demoted below the record: the kbite registry (its
    /// writes-in-any-status contract kept — the binding reaches the host
    /// pane's existing sync) and the dope surface in a compact collapsed
    /// disclosure.
    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            KBitePillBox(available: availableKbites, selected: $selectedKbites)
            DisclosureGroup {
                DopePane(scope: scope, promptUuid: stub.uuid, scrollable: false)
                    .frame(minHeight: 120)
                    .padding(.top, 8)
            } label: {
                Label("Dope", systemImage: "cube.transparent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
