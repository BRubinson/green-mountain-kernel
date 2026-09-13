import Foundation

public enum GmBridgeYaml {

    public static func scalar(_ value: String) -> String {
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

    public static func bool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    public static func tools(_ tools: [GmBridgeClaudeTypeTool]) -> String {
        tools.map(\.frontmatterValue).joined(separator: ", ")
    }

    public static func list(_ values: [String], separator: String = ", ") -> String {
        values.joined(separator: separator)
    }

    public static func inline<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func oneLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
