import Foundation

enum GmBridgeWorkflow {

    struct Phase: Equatable, Sendable {

        var title: String

        var detail: String?

        var model: GmBridgeClaudeTypeModel?

        /// Creates a workflow phase with title, detail, and optional model.
        ///
        /// - Parameters:
        ///   - title: The phase title.
        ///   - detail: Optional additional detail text.
        ///   - model: The Claude model for this phase, or nil.
        init(
            title: String,
            detail: String? = nil,
            model: GmBridgeClaudeTypeModel? = nil
        ) {
            self.title = title
            self.detail = detail
            self.model = model
        }
    }

    struct File: Equatable, Sendable, GmBridgeFile {

        var name: String

        var description: String

        var whenToUse: String?

        var phases: [Phase]

        var body: String

        /// Creates a workflow file with metadata and phases.
        ///
        /// - Parameters:
        ///   - name: The workflow name.
        ///   - description: A description of what the workflow does.
        ///   - whenToUse: Optional guidance on when to invoke the workflow.
        ///   - phases: The phases this workflow contains.
        ///   - body: The JavaScript/TypeScript body code.
        init(
            name: String,
            description: String,
            whenToUse: String? = nil,
            phases: [Phase] = [],
            body: String = ""
        ) {
            self.name = name
            self.description = description
            self.whenToUse = whenToUse
            self.phases = phases
            self.body = body
        }

        var relativePath: String {
            "workflows/\(name).js"
        }

        var isEmpty: Bool {
            body.isEmpty
        }

        /// Renders the workflow metadata and body as JavaScript code.
        ///
        /// - Returns: The rendered JavaScript with meta export and body, or nil
        ///   if the file is empty.
        /// - Throws: Errors if YAML serialization fails.
        func contents() throws -> String? {
            guard !isEmpty else { return nil }

            var lines = ["export const meta = {"]
            lines.append("  name: \(try GmBridgeYaml.inline(name)),")
            lines.append("  description: \(try GmBridgeYaml.inline(description)),")
            if let whenToUse {
                lines.append("  whenToUse: \(try GmBridgeYaml.inline(whenToUse)),")
            }
            if !phases.isEmpty {
                lines.append("  phases: [")
                for phase in phases {
                    var fields = ["title: \(try GmBridgeYaml.inline(phase.title))"]
                    if let detail = phase.detail {
                        fields.append("detail: \(try GmBridgeYaml.inline(detail))")
                    }
                    if let model = phase.model {
                        fields.append("model: \(try GmBridgeYaml.inline(model.rawValue))")
                    }
                    lines.append("    { \(fields.joined(separator: ", ")) },")
                }
                lines.append("  ],")
            }
            lines.append("}")

            let content = body.hasSuffix("\n") ? body : body + "\n"
            return lines.joined(separator: "\n") + "\n\n" + content
        }
    }
}
