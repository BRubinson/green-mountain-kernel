import Foundation

public enum GmBridgeOutputStyle {

    public struct File: Equatable, Sendable, GmBridgeFile {

        public var name: String

        public var displayName: String?

        public var description: String?

        public var keepCodingInstructions: Bool?

        /// Plugin output styles only: apply this style automatically whenever
        /// the plugin is enabled, overriding the user's `outputStyle` setting.
        ///
        /// OPTIONAL ON PURPOSE, exactly like `keepCodingInstructions`. A
        /// non-optional `Bool` would write `force-for-plugin: false` into every
        /// style that simply had no opinion, which is a different statement from
        /// omitting the key.
        public var forceForPlugin: Bool?

        public var body: String

        public init(
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

        public var relativePath: String {
            "output-styles/\(name).md"
        }

        public var isEmpty: Bool {
            body.isEmpty
        }

        public func contents() throws -> String? {
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
                    "keep-coding-instructions: \(GmBridgeYaml.bool(keepCodingInstructions))")
            }
            if let forceForPlugin {
                lines.append(
                    "force-for-plugin: \(GmBridgeYaml.bool(forceForPlugin))")
            }
            lines.append("---")

            let content = body.hasSuffix("\n") ? body : body + "\n"
            return lines.joined(separator: "\n") + "\n\n" + content
        }
    }
}
