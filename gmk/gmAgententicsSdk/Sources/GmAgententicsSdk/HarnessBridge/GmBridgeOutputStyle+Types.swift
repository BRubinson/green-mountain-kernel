import Foundation

public enum GmBridgeOutputStyle {

    public struct File: Equatable, Sendable, GmBridgeFile {

        public var name: String

        public var displayName: String?

        public var description: String?

        public var keepCodingInstructions: Bool?

        public var body: String

        public init(
            name: String,
            displayName: String? = nil,
            description: String? = nil,
            keepCodingInstructions: Bool? = nil,
            body: String = ""
        ) {
            self.name = name
            self.displayName = displayName
            self.description = description
            self.keepCodingInstructions = keepCodingInstructions
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
            lines.append("---")

            let content = body.hasSuffix("\n") ? body : body + "\n"
            return lines.joined(separator: "\n") + "\n\n" + content
        }
    }
}
