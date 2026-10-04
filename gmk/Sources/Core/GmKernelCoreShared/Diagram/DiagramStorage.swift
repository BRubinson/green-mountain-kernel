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

    /// Computes the screenshot path for a diagram.
    ///
    /// Path format: `{owner storage}/{gmcc_diagram_path ?? "diagrams"}/screenshots/{code}.png`.
    /// One mutable file per diagram code, not per revision. Staleness is decided by comparing
    /// a sidecar fingerprint, so a bot always reads the same path.
    ///
    /// - Parameters:
    ///   - ownerStoragePath: Owner's GMFS-relative storage directory.
    ///   - gmccDiagramPath: Override for the diagram directory; defaults to `"diagrams"`.
    ///   - diagramCode: Diagram code identifier.
    ///   - fileExtension: File extension; defaults to `"png"`.
    /// - Returns: GMFS-relative path to the screenshot file.
    /// - Throws: `StoreError` on path validation failure.
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

    /// Computes the fingerprint sidecar path for a diagram.
    ///
    /// The fingerprint file sits beside its PNG with the same stem.
    ///
    /// - Parameters:
    ///   - ownerStoragePath: Owner's GMFS-relative storage directory.
    ///   - gmccDiagramPath: Override for the diagram directory; defaults to `"diagrams"`.
    ///   - diagramCode: Diagram code identifier.
    /// - Returns: GMFS-relative path to the fingerprint file (`render.json`).
    /// - Throws: `StoreError` on path validation failure.
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

    /// Splits and validates a path to prevent escaping the GMFS root.
    ///
    /// Runs before any sandbox check for defence in depth and provides clear error messages
    /// instead of generic containment refusal.
    ///
    /// - Parameters:
    ///   - raw: The path string to split and validate.
    ///   - label: Description used in error messages.
    /// - Returns: Array of validated path segments.
    /// - Throws: `StoreError` on empty, absolute, relative, dotfile, or slashed segments.
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

    /// Validates a path segment name.
    ///
    /// - Parameters:
    ///   - name: The segment to validate.
    ///   - label: Description used in error messages.
    /// - Throws: `StoreError` on empty, relative (`..`, `.`), dotfile, or slashed segments.
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
    ///
    /// Sorted by key when encoded, so the JSON is stable.
    let dopeRevisions: [String: Int64]
    let scheme: String
    let scale: Double
    let algoVersion: Int

    /// Creates a diagram render fingerprint.
    ///
    /// - Parameters:
    ///   - diagramUuid: The diagram identifier.
    ///   - diagramRevision: The diagram's revision number.
    ///   - dopeRevisions: Map of dope scope codes to their revisions for all resolved bindings.
    ///   - scheme: The rendering color scheme.
    ///   - scale: The rendering scale factor.
    ///   - algoVersion: The render algorithm version; defaults to current version.
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

    /// Checks whether this fingerprint matches another.
    ///
    /// A rendered file is reusable only against an identical key. `diagramUuid` is part of it:
    /// a diagram renamed onto a code another diagram once held would otherwise inherit that diagram's PNG.
    ///
    /// - Parameter other: The fingerprint to compare.
    /// - Returns: `true` when the fingerprints are identical.
    func matches(_ other: DiagramRenderFingerprint) -> Bool { self == other }

    /// Encodes this fingerprint to JSON data.
    ///
    /// - Returns: Pretty-printed JSON with sorted keys.
    /// - Throws: Encoding errors.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    /// Decodes a fingerprint from JSON data.
    ///
    /// - Parameter data: JSON data to decode.
    /// - Returns: The decoded fingerprint, or nil on decode failure.
    static func decoded(_ data: Data) -> DiagramRenderFingerprint? {
        try? JSONDecoder().decode(DiagramRenderFingerprint.self, from: data)
    }
}
