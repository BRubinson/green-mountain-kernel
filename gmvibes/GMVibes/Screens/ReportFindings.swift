import SwiftUI
import GMCCDaemonKit

/// Shared primitives for the two v9 report read surfaces (ExplorationPane,
/// ReviewPane) and the phaseCard header badges — one vocabulary for ratings,
/// kinds, resolutions, and counts instead of four private copies of the
/// partition logic. (The lifecycle bar was the second badge placement until
/// it was deleted for the workflow strip; the stub-based builders below
/// survive for any cold-start caller that needs them.)

enum FindingRatings {
    /// The daemon's consumption threshold and tombstone sentinel.
    /// `Store.findingReadThreshold` is INTERNAL to the kit, so the contract
    /// is mirrored here, not imported.
    static let readThreshold = 100
    static let tombstone = 999
}

/// Both full rows and stubs carry a nullable rating; visibility is the same
/// question for all four shapes.
protocol RatedFinding {
    var findingRating: Int? { get }
}

extension ExplorationFindingRow: RatedFinding {}
extension ExplorationFindingStub: RatedFinding {}
extension ReviewFindingRow: RatedFinding {}
extension ReviewFindingStub: RatedFinding {}

extension Array where Element: RatedFinding {
    /// FILTERS, never sorts. The daemon's order (unranked first, then rating
    /// ascending — the resume-queue contract) must survive to the screen.
    func visibleFindings(showLowPriority: Bool, showTombstones: Bool) -> [Element] {
        filter { finding in
            guard let rating = finding.findingRating else { return true }   // unranked: ALWAYS
            if rating >= FindingRatings.tombstone { return showTombstones } // 999 before 100
            if rating >= FindingRatings.readThreshold { return showLowPriority }
            return true
        }
    }

    var tombstoneCount: Int {
        filter { ($0.findingRating ?? 0) >= FindingRatings.tombstone }.count
    }

    var unrankedCount: Int {
        filter { $0.findingRating == nil }.count
    }
}

// MARK: - Kind styling

/// Kind labels switch on the RAW wire string with a passthrough default so
/// unknown kinds degrade to their raw name instead of vanishing (the
/// ClarificationPane "Other" precedent).
enum ReportKindStyle {
    static func exploration(_ raw: String) -> (label: String, tint: Color) {
        switch ExplorationFindingKind(rawValue: raw) {
        case .persistenceModel: ("Persistence", .indigo)
        case .implementationPattern: ("Pattern", .blue)
        case .existingFunctionality: ("Existing", .teal)
        case .scopeCreepRisk: ("Scope Risk", .orange)
        case .generalRelevantChange: ("Change", .purple)
        case .keyFile: ("Key File", .mint)
        case .other: ("Other", .gray)
        case .none: (raw, .gray)
        }
    }

    static func review(_ raw: String) -> (label: String, tint: Color) {
        switch ReviewFindingKind(rawValue: raw) {
        case .correctnessBug: ("Bug", .red)
        case .specDeviation: ("Spec", .orange)
        case .regressionRisk: ("Regression", .yellow)
        case .security: ("Security", .pink)
        case .simplification: ("Simplify", .teal)
        case .other: ("Other", .gray)
        case .none: (raw, .gray)
        }
    }
}

extension ReviewVerdict {
    var display: (label: String, tint: Color) {
        switch self {
        case .approved: ("Approved", .green)
        case .approvedWithNits: ("Approved w/ nits", .yellow)
        case .changesRequested: ("Changes requested", .orange)
        }
    }
}

// MARK: - Row chrome

struct FindingKindBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(tint.opacity(0.14), in: .capsule)
            .foregroundStyle(tint)
    }
}

/// Rating or "unranked" — unranked is the resume work-queue signal, so it
/// reads orange, not neutral.
struct FindingRatingPill: View {
    let rating: Int?

    var body: some View {
        if let rating {
            Text(String(rating))
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(tint.opacity(0.14), in: .capsule)
                .foregroundStyle(tint)
        } else {
            Text("unranked")
                .font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.orange.opacity(0.14), in: .capsule)
                .foregroundStyle(.orange)
        }
    }

    private var tint: Color {
        guard let rating else { return .orange }
        if rating >= FindingRatings.tombstone { return .gray }
        if rating >= FindingRatings.readThreshold { return .secondary }
        return rating < 10 ? .red : .primary
    }
}

/// Per-finding fix-loop resolution (review only). Unknown raw statuses render
/// neutrally rather than disappearing.
struct ResolutionBadge: View {
    let rawStatus: String

    var body: some View {
        let (icon, tint): (String, Color) = switch ReviewFindingStatus(rawValue: rawStatus) {
        case .open: ("circle", .orange)
        case .fixed: ("checkmark.circle.fill", .green)
        case .accepted: ("checkmark.circle", .blue)
        case .wontFix: ("minus.circle", .gray)
        case .none: ("questionmark.circle", .gray)
        }
        Label(rawStatus.replacingOccurrences(of: "_", with: " "), systemImage: icon)
            .font(.caption2)
            .foregroundStyle(tint)
    }
}

// MARK: - Count badges (phaseCard headers)

struct ReportBadgeItem: Identifiable {
    let id: String
    let text: String
    let systemImage: String
    let tint: Color
}

extension ReportBadgeItem {
    // Informational ONLY — these never participate in gate logic. Builders
    // exist for both the PROMPT_LIST stub (cold start) and the live response
    // (authoritative once loaded — report writes don't re-list the session).

    static func exploration(_ stub: ExplorationReportStub) -> [ReportBadgeItem] {
        explorationItems(
            unranked: stub.unrankedFindingCount,
            findings: stub.findingCount,
            keyFiles: stub.keyFileCount
        )
    }

    static func exploration(_ response: ExploreGetResponse) -> [ReportBadgeItem] {
        explorationItems(
            unranked: response.findings.unrankedCount,
            findings: response.findings.count + response.findingStubs.count,
            keyFiles: response.keyFiles.count
        )
    }

    static func review(_ stub: ReviewReportStub) -> [ReportBadgeItem] {
        reviewItems(
            verdict: stub.verdict.flatMap(ReviewVerdict.init(rawValue:)),
            open: stub.openFindingCount,
            unranked: stub.unrankedFindingCount
        )
    }

    static func review(_ response: ReviewGetResponse) -> [ReportBadgeItem] {
        let openCount = response.findings.filter { $0.status == ReviewFindingStatus.open.rawValue }.count
            + response.findingStubs.filter { $0.status == ReviewFindingStatus.open.rawValue }.count
        return reviewItems(
            verdict: response.summary.verdict.flatMap(ReviewVerdict.init(rawValue:)),
            open: openCount,
            unranked: response.findings.unrankedCount
        )
    }

    private static func explorationItems(unranked: Int, findings: Int, keyFiles: Int) -> [ReportBadgeItem] {
        var items: [ReportBadgeItem] = []
        if unranked > 0 {   // stalled-run signal
            items.append(.init(id: "explore-unranked", text: "\(unranked) unranked",
                               systemImage: "exclamationmark.circle", tint: .orange))
        }
        if findings > 0 {
            items.append(.init(id: "explore-findings", text: "\(findings) findings",
                               systemImage: "sparkle.magnifyingglass", tint: .secondary))
        }
        if keyFiles > 0 {
            items.append(.init(id: "explore-keyfiles", text: "\(keyFiles) key files",
                               systemImage: "doc.text.magnifyingglass", tint: .secondary))
        }
        return items
    }

    private static func reviewItems(verdict: ReviewVerdict?, open: Int, unranked: Int) -> [ReportBadgeItem] {
        var items: [ReportBadgeItem] = []
        if let verdict {
            let display = verdict.display
            items.append(.init(id: "review-verdict", text: display.label,
                               systemImage: "checkmark.seal", tint: display.tint))
        }
        if open > 0 {   // fix-loop progress signal
            items.append(.init(id: "review-open", text: "\(open) open",
                               systemImage: "circle", tint: .orange))
        }
        if unranked > 0 {
            items.append(.init(id: "review-unranked", text: "\(unranked) unranked",
                               systemImage: "exclamationmark.circle", tint: .orange))
        }
        return items
    }
}

struct ReportBadgeCluster: View {
    let items: [ReportBadgeItem]

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 4) {
                ForEach(items) { item in
                    Label(item.text, systemImage: item.systemImage)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(item.tint.opacity(0.12), in: .capsule)
                        .foregroundStyle(item.tint)
                }
            }
        }
    }
}
