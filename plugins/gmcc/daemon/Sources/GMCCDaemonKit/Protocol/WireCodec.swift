import Foundation

/// The single source of JSON coders for the wire and every human-facing JSON
/// printer. snake_case is applied by strategy, not by hand-written CodingKeys —
/// wire types declare NO CodingKeys except the two intentional renames
/// (RawEnvelopeHead.typeRaw → "type", ErrorPayload.codeRaw → "code"), and a
/// type retaining an explicit CodingKeys enum must list every OTHER key as a
/// bare case: under .convertFromSnakeCase an explicit snake_case raw value
/// stops matching and an Optional field silently decodes to nil.
///
/// All five coder sites route through here: NDJSON.encodeLine, NDJSON.decode,
/// gm's printJSON, gm's event-stream printer, and (via NDJSON) DaemonClient.
/// A bare JSONEncoder() anywhere else silently emits camelCase — the golden
/// contract in Tests/GMCCDaemonKitTests/Fixtures/wire_keys.golden is the
/// tripwire (regenerate + diff with scripts/wire_keys.py).
public enum WireCodec {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    public static let decoder: JSONDecoder = {
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
    public static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}
