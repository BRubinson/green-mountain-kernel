import Foundation

/// Where a diagram's materialized files live.
///
/// GMFS-rooted at EVERY tier. Every tier carries a
/// `gmfs_relative_storage_path`, so rooting there gives a PROJECT-tier
/// diagram a home even though a project spans zero-to-many checkouts, and it
/// puts the files outside the repo. Pure arithmetic, no I/O: identical in the
/// CLI and the app because both call this rather than rebuilding the
/// convention.
enum DiagramStorage {

    /// The path segment a diagram's own files live under, relative to its
    /// owner's GMFS storage directory. `gmcc_diagram_path` overrides it.
    static let defaultDirectory = "diagrams"
    static let screenshotsDirectory = "screenshots"

    /// `{owner storage}/{gmcc_diagram_path ?? "diagrams"}/screenshots/{code}.png`
    ///
    /// One mutable file per diagram code — not one per revision. Staleness
    /// is decided by comparing a sidecar fingerprint, so a bot always reads
    /// the same path and never has to guess which of several files is
    /// current.
    static func screenshotRelativePath(
        ownerStoragePath: String,
        gmccDiagramPath: String?,
        diagramCode: String,
        fileExtension: String = "png"
    ) throws -> String {
        let owner = try sanitizedSegments(ownerStoragePath, label: "owner storage path")
        let middle = try sanitizedSegments(
            gmccDiagramPath ?? defaultDirectory,
            label: "gmcc_diagram_path"
        )
        try validateName(diagramCode, label: "diagram code")
        return
            (owner + middle + [
                screenshotsDirectory,
                "\(diagramCode).\(fileExtension)",
            ])
            .joined(separator: "/")
    }

    /// The fingerprint sidecar sits beside its PNG, same stem.
    static func fingerprintRelativePath(
        ownerStoragePath: String,
        gmccDiagramPath: String?,
        diagramCode: String
    ) throws -> String {
        try screenshotRelativePath(
            ownerStoragePath: ownerStoragePath,
            gmccDiagramPath: gmccDiagramPath,
            diagramCode: diagramCode,
            fileExtension: "render.json"
        )
    }

    // MARK: - Path hygiene

    /// Split and validate, so a stored path can never climb out of the GMFS
    /// root. This runs BEFORE any sandbox check — defence in depth, and it
    /// gives a comprehensible error instead of a containment refusal.
    static func sanitizedSegments(_ raw: String, label: String) throws -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.badRequest(detail: "\(label) is empty")
        }
        guard !trimmed.hasPrefix("/") else {
            throw StoreError.badRequest(
                detail: "\(label) must be GMFS-relative, not absolute: \(trimmed)"
            )
        }
        let segments = trimmed.split(separator: "/").map(String.init)
        guard !segments.isEmpty else {
            throw StoreError.badRequest(detail: "\(label) has no path segments")
        }
        for segment in segments { try validateName(segment, label: label) }
        return segments
    }

    static func validateName(_ name: String, label: String) throws {
        guard !name.isEmpty else {
            throw StoreError.badRequest(detail: "\(label) has an empty segment")
        }
        guard name != "..", name != "." else {
            throw StoreError.badRequest(detail: "\(label) contains a relative segment")
        }
        guard !name.hasPrefix(".") else {
            throw StoreError.badRequest(
                detail: "\(label) segment '\(name)' may not start with a dot"
            )
        }
        guard !name.contains("/") else {
            throw StoreError.badRequest(detail: "\(label) segment contains a slash")
        }
    }
}

/// The staleness key for a rendered diagram: the full input tuple, not the
/// diagram's revision.
///
/// `bumpDiagramRevision` fires only on diagram mutations, but an entity card
/// draws its rows from the bound dope tree, so editing a dope property
/// changes the picture while revision and `updated_at` sit still. The render
/// CODE is in the key too, via `algoVersion`: a card metric or router padding
/// change repaints with every persisted input identical.
struct DiagramRenderFingerprint: Codable, Hashable, Sendable {
    /// BUMP THIS when resolver or view geometry changes: card metrics,
    /// `edgeRoutingPadding`, router cost constants, the edge canvas's
    /// stroke geometry. Renders older than the bump re-render once.
    // 2 (v23): real arrowheads + tail decorations + routingKind dispatch,
    // pressure-aware freehand outlines, uml_node chrome, block markdown in
    // text surfaces. Bump on EVERY look change — this constant is the
    // fingerprint's only representative of render code.
    static let renderAlgoVersion = 2

    let diagramUuid: String
    let diagramRevision: Int64
    /// dope scope code -> that scope's revision, for every RESOLVED binding.
    /// Sorted by key when encoded, so the JSON is stable.
    let dopeRevisions: [String: Int64]
    let scheme: String
    let scale: Double
    let algoVersion: Int

    init(
        diagramUuid: String,
        diagramRevision: Int64,
        dopeRevisions: [String: Int64],
        scheme: String,
        scale: Double,
        algoVersion: Int = DiagramRenderFingerprint.renderAlgoVersion
    ) {
        self.diagramUuid = diagramUuid
        self.diagramRevision = diagramRevision
        self.dopeRevisions = dopeRevisions
        self.scheme = scheme
        self.scale = scale
        self.algoVersion = algoVersion
    }

    /// A rendered file is reusable only against an identical key.
    ///
    /// `diagramUuid` is part of it: a diagram renamed onto a code another
    /// diagram once held would otherwise inherit that diagram's PNG.
    func matches(_ other: DiagramRenderFingerprint) -> Bool { self == other }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    static func decoded(_ data: Data) -> DiagramRenderFingerprint? {
        try? JSONDecoder().decode(DiagramRenderFingerprint.self, from: data)
    }
}
