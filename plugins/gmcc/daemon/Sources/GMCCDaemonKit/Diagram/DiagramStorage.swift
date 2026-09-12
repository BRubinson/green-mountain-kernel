import Foundation

/// Where a diagram's materialized files live.
///
/// CKFS-rooted at EVERY tier. The predecessor anchored screenshots to the
/// diagram's instance checkout, which is why a PROJECT-tier diagram could
/// not have one at all: a project spans zero-to-many checkouts and none of
/// them is "the" one. Every tier carries a `ckfs_relative_storage_path`, so
/// rooting there removes the special case instead of working around it —
/// and, incidentally, means the files are outside the repo, so there is no
/// .gitignore to manage.
///
/// Pure arithmetic, no I/O: testable without a filesystem, and identical in
/// the CLI and the app because both call this rather than each rebuilding
/// the convention.
public enum DiagramStorage {

    /// The path segment a diagram's own files live under, relative to its
    /// owner's CKFS storage directory. `gmcc_diagram_path` was inert
    /// free-text with zero consumers before this; it is the override.
    public static let defaultDirectory = "diagrams"
    public static let screenshotsDirectory = "screenshots"

    /// `{owner storage}/{gmcc_diagram_path ?? "diagrams"}/screenshots/{code}.png`
    ///
    /// One mutable file per diagram code — not one per revision. Staleness
    /// is decided by comparing a sidecar fingerprint, so a bot always reads
    /// the same path and never has to guess which of several files is
    /// current.
    public static func screenshotRelativePath(
        ownerStoragePath: String, gmccDiagramPath: String?, diagramCode: String,
        fileExtension: String = "png"
    ) throws -> String {
        let owner = try sanitizedSegments(ownerStoragePath, label: "owner storage path")
        let middle = try sanitizedSegments(
            gmccDiagramPath ?? defaultDirectory, label: "gmcc_diagram_path")
        try validateName(diagramCode, label: "diagram code")
        return (owner + middle + [screenshotsDirectory,
                                  "\(diagramCode).\(fileExtension)"]).joined(separator: "/")
    }

    /// The fingerprint sidecar sits beside its PNG, same stem.
    public static func fingerprintRelativePath(
        ownerStoragePath: String, gmccDiagramPath: String?, diagramCode: String
    ) throws -> String {
        try screenshotRelativePath(
            ownerStoragePath: ownerStoragePath, gmccDiagramPath: gmccDiagramPath,
            diagramCode: diagramCode, fileExtension: "render.json")
    }

    // MARK: - Path hygiene

    /// Split and validate, so a stored path can never climb out of the CKFS
    /// root. This runs BEFORE any sandbox check — defence in depth, and it
    /// gives a comprehensible error instead of a containment refusal.
    public static func sanitizedSegments(_ raw: String, label: String) throws -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.badRequest(detail: "\(label) is empty")
        }
        guard !trimmed.hasPrefix("/") else {
            throw StoreError.badRequest(
                detail: "\(label) must be CKFS-relative, not absolute: \(trimmed)")
        }
        let segments = trimmed.split(separator: "/").map(String.init)
        guard !segments.isEmpty else {
            throw StoreError.badRequest(detail: "\(label) has no path segments")
        }
        for segment in segments { try validateName(segment, label: label) }
        return segments
    }

    public static func validateName(_ name: String, label: String) throws {
        guard !name.isEmpty else {
            throw StoreError.badRequest(detail: "\(label) has an empty segment")
        }
        guard name != "..", name != "." else {
            throw StoreError.badRequest(detail: "\(label) contains a relative segment")
        }
        guard !name.hasPrefix(".") else {
            throw StoreError.badRequest(
                detail: "\(label) segment '\(name)' may not start with a dot")
        }
        guard !name.contains("/") else {
            throw StoreError.badRequest(detail: "\(label) segment contains a slash")
        }
    }
}

/// The staleness key for a rendered diagram.
///
/// The obvious key — the diagram's own revision — is WRONG, and quietly so.
/// `bumpDiagramRevision` fires only on diagram mutations, but an entity card
/// draws its rows from the bound dope tree. Edit a dope property and the
/// picture changes while `diagram.revision` and `updated_at` sit still, so a
/// revision-or-mtime check reports "fresh" and hands a bot yesterday's
/// schema with a current-looking path. Nothing about that failure is
/// visible: the file exists, the timestamp is recent, the content is stale.
///
/// So the key is the full input tuple. Everything the render is a function
/// of goes in — including the render CODE, via `algoVersion`, because
/// changing a card metric or the router's padding changes the picture with
/// every persisted input identical.
public struct DiagramRenderFingerprint: Codable, Hashable, Sendable {
    /// BUMP THIS when resolver or view geometry changes: card metrics,
    /// `edgeRoutingPadding`, router cost constants, the edge canvas's
    /// stroke geometry. Renders older than the bump re-render once.
    // 2 (v23): real arrowheads + tail decorations + routingKind dispatch,
    // pressure-aware freehand outlines, uml_node chrome, block markdown in
    // text surfaces. Bump on EVERY look change — this constant is the
    // fingerprint's only representative of render code.
    public static let renderAlgoVersion = 2

    public let diagramUuid: String
    public let diagramRevision: Int64
    /// dope scope code -> that scope's revision, for every RESOLVED binding.
    /// Sorted by key when encoded, so the JSON is stable.
    public let dopeRevisions: [String: Int64]
    public let scheme: String
    public let scale: Double
    public let algoVersion: Int

    public init(diagramUuid: String, diagramRevision: Int64,
                dopeRevisions: [String: Int64], scheme: String, scale: Double,
                algoVersion: Int = DiagramRenderFingerprint.renderAlgoVersion) {
        self.diagramUuid = diagramUuid
        self.diagramRevision = diagramRevision
        self.dopeRevisions = dopeRevisions
        self.scheme = scheme
        self.scale = scale
        self.algoVersion = algoVersion
    }

    /// A rendered file is reusable only against an identical key.
    ///
    /// `diagramUuid` is part of it on purpose: a diagram renamed to a code
    /// another diagram used to hold would otherwise inherit that diagram's
    /// PNG. Comparing identity catches it and forces a re-render.
    public func matches(_ other: DiagramRenderFingerprint) -> Bool { self == other }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    public static func decoded(_ data: Data) -> DiagramRenderFingerprint? {
        try? JSONDecoder().decode(DiagramRenderFingerprint.self, from: data)
    }
}
