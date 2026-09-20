import Foundation

/// The single source of JSON coders for the wire and every human-facing JSON
/// printer. snake_case is applied by STRATEGY, not by hand-written CodingKeys:
/// wire types declare none except the two intentional renames, and a type that
/// keeps an explicit CodingKeys enum must list every other key as a bare case,
/// because under `.convertFromSnakeCase` an explicit snake_case raw value stops
/// matching and an Optional field silently decodes to nil. Every coder site
/// routes through here; a bare `JSONEncoder()` elsewhere silently emits
/// camelCase.
enum WireCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// For `--json` client output: same key contract as the wire, pretty and
    /// deterministically ordered for terminal reading and doc greps.
    ///
    /// `.withoutEscapingSlashes` is display-only and terminal-facing — gm's
    /// output is dense with paths, and `\/Users\/…` is both unreadable over a
    /// shoulder and pure noise in an agent's context. It never reaches the
    /// wire: `encoder` above is the only coder NDJSON touches, and this one
    /// has exactly one caller (gm's printJSON).
    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}
