import Foundation

/// KBITE_MAW_OPEN — filesystem skeleton only, NO db rows (maws are not
/// tracked in the db; mirrors /gm_crunch_open_maw).
///
/// The interactive KBITE_PURPOSE.md step stays a client-side skill
/// responsibility — a daemon message can never prompt. Idempotent: existing
/// dirs/index are left alone.
enum KbiteMawOpenHandler {
    static let axis1 = ["primary", "secondary"]
    static let axis2 = ["documentation", "example_project", "api_reference", "blogs", "all_others"]

    /// Handles a kbiteMawOpen request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    /// - Returns: A handler result with the maw path and created directories.
    /// - Throws: An error if directory creation or template generation fails.
    static func handle(line: Data, head: EnvelopeHead) throws -> HandlerResult {
        let request = try decodePayload(KbiteMawOpenRequest.self, from: line)
        let fm = FileManager.default
        let mawURL = URL(fileURLWithPath: request.mawPath, isDirectory: true)

        var createdDirs: [String] = []
        for a1 in axis1 {
            for a2 in axis2 {
                let dir = mawURL.appendingPathComponent(a1, isDirectory: true)
                    .appendingPathComponent(a2, isDirectory: true)
                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    createdDirs.append("\(a1)/\(a2)")
                }
            }
        }

        let indexURL = mawURL.appendingPathComponent("MAW_INDEX.md")
        var createdIndex = false
        if !fm.fileExists(atPath: indexURL.path) {
            try mawIndexTemplate(kbiteName: request.kbiteName)
                .write(to: indexURL, atomically: true, encoding: .utf8)
            createdIndex = true
        }

        return try okResult(
            .kbiteMawOpen,
            head,
            KbiteMawOpenResponse(
                mawPath: request.mawPath,
                createdDirs: createdDirs,
                createdIndex: createdIndex
            )
        )
    }

    /// Generates the initial MAW_INDEX.md template for a maw.
    ///
    /// - Parameter kbiteName: The kbite name to reference in the template.
    /// - Returns: The template markdown string.
    private static func mawIndexTemplate(kbiteName: String) -> String {
        """
        # Maw Index: \(kbiteName)

        **Target KBite**: \(kbiteName)
        **Opened**: \(Store.isoNow())
        **Status**: open

        ## Crunchable Index

        | Resource | Path | Status | Keywords | Relevance | Uniqueness | Unique Keywords | Expansion Weight |
        |----------|------|--------|----------|-----------|------------|-----------------|------------------|
        | *No crunchables yet* | - | - | - | - | - | - | - |

        ## Status Legend
        - **pending**: Resource added, not yet analyzed
        - **chewing**: Agent currently processing
        - **chewed**: Analysis complete, ready for digest

        ## Next Steps
        1. Add raw source files to appropriate `{axis1}/{axis2}/{resource_name}/` directories
        2. Run `/gm_crunch_chew \(kbiteName)` to process crunchables
        3. Run `/gm_crunch_digest \(kbiteName)` to finalize the kbite

        """
    }
}
