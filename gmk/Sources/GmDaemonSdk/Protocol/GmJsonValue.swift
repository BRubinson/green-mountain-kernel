import Foundation

/// Any JSON value, as a `Codable` — the type that makes an untyped passthrough
/// possible without teaching a caller 123 payload shapes. `GmHookCli` spells it
/// `JSONValue` through a typealias.
/// An enum rather than `[String: Any]` because `Any` is none of `Codable`,
/// `Sendable` or `Hashable`, and the envelope machinery needs all three:
/// `Sendable` because payloads cross the server's serial queue, `Hashable`
/// because the message structs are. KEYS ARE NEVER TRANSLATED HERE — the wire
/// is snake_case and whatever went in comes out.
enum GmJsonValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([GmJsonValue])
    case object([String: GmJsonValue])

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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
