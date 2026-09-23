import Foundation

enum GmBridgeOutputStyle {

    struct File: Equatable, Sendable, GmBridgeFile {

        var name: String

        var displayName: String?

        var description: String?

        var keepCodingInstructions: Bool?

        /// Plugin output styles only: apply this style automatically whenever
        /// the plugin is enabled, overriding the user's `outputStyle` setting.
        ///
        /// OPTIONAL ON PURPOSE, exactly like `keepCodingInstructions`. A
        /// non-optional `Bool` would write `force-for-plugin: false` into every
        /// style that simply had no opinion, which is a different statement from
        /// omitting the key.
        var forceForPlugin: Bool?

        var body: String

        /// Creates an output style file.
        ///
        /// - Parameters:
        ///   - name: The style name (used in the file path).
        ///   - displayName: The human-readable display name.
        ///   - description: A description of the style.
        ///   - keepCodingInstructions: Whether to keep coding instructions.
        ///   - forceForPlugin: Whether to apply this style automatically for the plugin.
        ///   - body: The markdown content of the style.
        init(
            name: String,
            displayName: String? = nil,
            description: String? = nil,
            keepCodingInstructions: Bool? = nil,
            forceForPlugin: Bool? = nil,
            body: String = ""
        ) {
            self.name = name
            self.displayName = displayName
            self.description = description
            self.keepCodingInstructions = keepCodingInstructions
            self.forceForPlugin = forceForPlugin
            self.body = body
        }

        var relativePath: String {
            "output-styles/\(name).md"
        }

        var isEmpty: Bool {
            body.isEmpty
        }

        /// Returns the file contents as a YAML-frontmatter markdown document.
        ///
        /// - Returns: The formatted contents, or nil if the body is empty.
        func contents() -> String? {
            guard !isEmpty else { return nil }

            var lines = ["---"]
            if let displayName {
                lines.append("name: \(GmBridgeYaml.scalar(displayName))")
            }
            if let description {
                lines.append("description: \(GmBridgeYaml.scalar(description))")
            }
            if let keepCodingInstructions {
                lines.append(
                    "keep-coding-instructions: \(GmBridgeYaml.bool(keepCodingInstructions))"
                )
            }
            if let forceForPlugin {
                lines.append(
                    "force-for-plugin: \(GmBridgeYaml.bool(forceForPlugin))"
                )
            }
            lines.append("---")

            let content = body.hasSuffix("\n") ? body : body + "\n"
            return lines.joined(separator: "\n") + "\n\n" + content
        }
    }
}
