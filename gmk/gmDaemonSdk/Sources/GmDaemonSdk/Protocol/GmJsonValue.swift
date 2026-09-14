import Foundation

/// Any JSON value, as a `Codable` — the type that makes an untyped passthrough
/// possible without teaching a caller 123 payload shapes.
///
/// PROMOTED FROM `GmHookCli` AT v30, AND THE PROMOTION IS THE POINT. This
/// started life as a `fileprivate`-in-spirit enum inside `Call.swift`, serving
/// exactly one caller: `gm_hook call <TYPE> --json`. The harness envelope
/// (`MCP_CALL`, `HOOK_EVENT`) needs the same shape on the PROTOCOL side, and the
/// alternative to moving it was a byte-identical second copy in `Messages.swift`
/// — the same duplication-with-no-checker that the vendored `gm_releases.sh`
/// twin already demonstrates the cost of. One type, two consumers.
///
/// `GmHookCli` keeps the spelling `JSONValue` as a typealias onto this, so the
/// relay code that was written against it reads unchanged.
///
/// WHY AN ENUM AND NOT `[String: Any]`: `Any` is not `Codable`, not `Sendable`,
/// and not `Hashable`. Every payload on this wire is all three, and the envelope
/// machinery relies on it — `Sendable` because payloads cross the server's
/// serial queue, `Hashable` because the message structs are.
///
/// KEYS ARE NEVER TRANSLATED BY THIS TYPE. The wire is snake_case and a caller
/// holding a `GmJsonValue` is working at wire level; a silent key rewrite here
/// would be a second dialect to learn, and it would be invisible at the call
/// site. Whatever went in comes out.
public enum GmJsonValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([GmJsonValue])
    case object([String: GmJsonValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        // Int64 BEFORE Double: a whole number decoded as Double round-trips as
        // `1.0`, and a wire key whose value silently gains a decimal point is
        // the kind of drift that only surfaces in a golden-file diff.
        if let value = try? container.decode(Int64.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([GmJsonValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: GmJsonValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "unrepresentable JSON")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
