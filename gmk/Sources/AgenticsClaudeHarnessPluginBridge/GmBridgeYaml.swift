import Foundation

enum GmBridgeYaml {

    /// Formats a string as a YAML scalar, quoting if necessary.
    ///
    /// - Parameter value: The string value to format.
    /// - Returns: The value quoted if it contains special characters, otherwise unquoted.
    static func scalar(_ value: String) -> String {
        let needsQuoting =
            value.isEmpty
            || value != value.trimmingCharacters(in: .whitespacesAndNewlines)
            || value.contains(": ")
            || value.hasSuffix(":")
            || value.contains("\n")
            || value.contains(" #")
            || "-?:,[]{}#&*!|>'\"%@`".contains(value.first ?? " ")

        guard needsQuoting else { return value }

        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// Formats a boolean as a YAML literal.
    ///
    /// - Parameter value: The boolean value.
    /// - Returns: Either `"true"` or `"false"`.
    static func bool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    /// Formats a list of tools as a comma-separated YAML sequence.
    ///
    /// - Parameter tools: The tools to format.
    /// - Returns: The tools' frontmatter values joined by commas.
    static func tools(_ tools: [GmBridgeClaudeTypeTool]) -> String {
        tools.map(\.frontmatterValue).joined(separator: ", ")
    }

    /// Formats a list of strings with a custom separator.
    ///
    /// - Parameters:
    ///   - values: The strings to join.
    ///   - separator: The separator string; defaults to `", "`.
    /// - Returns: The strings joined by the separator.
    static func list(_ values: [String], separator: String = ", ") -> String {
        values.joined(separator: separator)
    }

    /// Formats an encodable value as inline JSON.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: The JSON representation.
    /// - Throws: Any encoding error.
    static func inline<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// Formats a string as a single line, replacing newlines with spaces.
    ///
    /// - Parameter value: The string to format.
    /// - Returns: The string with newlines converted to spaces and trimmed.
    static func oneLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
