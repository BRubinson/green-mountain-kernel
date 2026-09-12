import Foundation

/// Snake_case code validation and dot-path reference parsing. Codes are the
/// ONLY relationship mechanism in .doped.json (uuids are banned there), so a
/// malformed code silently breaks a greppable reference — validation runs on
/// every write path, granular and whole-tree alike.
public enum DopeCode {

    /// The reserved middle segment that distinguishes an enum ref
    /// (`domain.enums.enum_code`) from a property ref
    /// (`domain.entity.property`). Entities may therefore never be coded
    /// `enums`.
    public static let reservedEnumSegment = "enums"

    public struct ValidationError: Error, CustomStringConvertible, Sendable {
        public let description: String
        public init(_ description: String) { self.description = description }
    }

    /// `^[a-z][a-z0-9_]*$`, no `__`, no trailing `_`, ≤ 64 bytes.
    public static func validateCode(_ code: String, field: String) throws {
        func bad(_ why: String) -> ValidationError {
            ValidationError("\(field) '\(code)' \(why)")
        }
        guard !code.isEmpty else { throw bad("is empty") }
        guard code.utf8.count <= 64 else { throw bad("exceeds 64 bytes") }
        guard let first = code.unicodeScalars.first,
              ("a"..."z").contains(Character(first)) else {
            throw bad("must start with a lowercase letter")
        }
        for ch in code.unicodeScalars {
            let c = Character(ch)
            guard ("a"..."z").contains(c) || ("0"..."9").contains(c) || c == "_" else {
                throw bad("may only contain a-z, 0-9 and _")
            }
        }
        guard !code.contains("__") else { throw bad("may not contain __") }
        guard !code.hasSuffix("_") else { throw bad("may not end with _") }
    }

    /// A parsed dot-path reference.
    public enum Ref: Hashable, Sendable {
        /// `domain_code.entity_code.property_code`
        case property(domain: String, entity: String, property: String)
        /// `domain_code.enums.enum_code`
        case enumType(domain: String, enumCode: String)
        /// `domain_code.entity_code` — a base_composable target. Two
        /// segments, so it can never collide with the three-segment forms.
        case entity(domain: String, entity: String)
    }

    public static func parseRef(_ raw: String, field: String) throws -> Ref {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 3, !parts.contains(where: \.isEmpty) else {
            throw ValidationError(
                "\(field) '\(raw)' must be domain.entity.property or domain.enums.enum_code")
        }
        for (i, part) in parts.enumerated() where !(i == 1 && part == reservedEnumSegment) {
            try validateCode(part, field: "\(field) segment \(i + 1)")
        }
        if parts[1] == reservedEnumSegment {
            return .enumType(domain: parts[0], enumCode: parts[2])
        }
        return .property(domain: parts[0], entity: parts[1], property: parts[2])
    }

    /// Strictly 2-segment. Deliberately NOT folded into parseRef: a truncated
    /// property ref must stay an error there, not silently become an entity.
    public static func parseEntityRef(_ raw: String, field: String) throws -> Ref {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 2, !parts.contains(where: \.isEmpty) else {
            throw ValidationError("\(field) '\(raw)' must be domain.entity")
        }
        for (i, part) in parts.enumerated() {
            try validateCode(part, field: "\(field) segment \(i + 1)")
        }
        guard parts[1] != reservedEnumSegment else {
            throw ValidationError(
                "\(field) '\(raw)' names entity 'enums' — reserved (no entity may carry that code)")
        }
        return .entity(domain: parts[0], entity: parts[1])
    }

    public static func formatPropertyRef(domain: String, entity: String, property: String) -> String {
        "\(domain).\(entity).\(property)"
    }

    public static func formatEnumRef(domain: String, enumCode: String) -> String {
        "\(domain).\(reservedEnumSegment).\(enumCode)"
    }

    public static func formatEntityRef(domain: String, entity: String) -> String {
        "\(domain).\(entity)"
    }
}
