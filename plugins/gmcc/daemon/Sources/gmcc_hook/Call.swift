import Foundation
import GMCCDaemonKit

/// Any JSON value, as a Codable — the type that makes an untyped passthrough
/// possible without teaching the client 123 payload shapes.
///
/// It rides the SAME `DaemonClient.request` as every typed verb, so it inherits
/// the hello handshake, the protocol-version check, the reconnect-once retry and
/// the server-error mapping. A hand-rolled socket write would inherit none of
/// that and would be a second wire client to keep in step.
enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int64.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
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

/// `gmcc_hook call <MESSAGE_TYPE> [--json '<payload>' | --json-file <path>]`
///
/// KEYS ARE SENT VERBATIM. The wire is snake_case, and this does not translate
/// — a caller reaching for the raw passthrough is working at wire level and a
/// silent key rewrite here would be a second dialect to learn.
func runCall(_ argv: [String]) -> Int32 {
    guard let typeName = argv.first, !typeName.hasPrefix("-") else {
        FileHandle.standardError.write(Data("[GMB] usage: gmcc_hook call <MESSAGE_TYPE> [--json '<payload>'] [--json-file <path>]\n".utf8))
        return 2
    }
    guard let type = MessageType(rawValue: typeName.uppercased()) else {
        FileHandle.standardError.write(Data("""
            [GMB] unknown message type '\(typeName)'. `gmcc_hook verbs --json` lists every type the daemon serves.

            """.utf8))
        return 2
    }

    var payloadData = Data("{}".utf8)
    var index = 1
    while index < argv.count {
        switch argv[index] {
        case "--json":
            guard index + 1 < argv.count else {
                FileHandle.standardError.write(Data("[GMB] --json needs a value\n".utf8))
                return 2
            }
            payloadData = Data(argv[index + 1].utf8)
            index += 2
        case "--json-file":
            // ARG_MAX is smaller than the daemon's content caps, so a large
            // body (an overview, a finding, a care-package intent) cannot be
            // passed inline at all. This is the same reason the retired CLI grew
            // its --*-file flags.
            guard index + 1 < argv.count,
                  let data = FileManager.default.contents(atPath: argv[index + 1])
            else {
                FileHandle.standardError.write(Data("[GMB] --json-file needs a readable path\n".utf8))
                return 2
            }
            payloadData = data
            index += 2
        default:
            index += 1
        }
    }

    let payload: JSONValue
    do {
        payload = try JSONDecoder().decode(JSONValue.self, from: payloadData)
    } catch {
        FileHandle.standardError.write(Data("[GMB] payload is not valid JSON: \(error)\n".utf8))
        return 2
    }

    let client = DaemonClient()
    defer { client.close() }
    do {
        let response: JSONValue = try client.request(type: type, payload: payload, responseType: JSONValue.self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(response), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        return 0
    } catch {
        FileHandle.standardError.write(Data("[GMB] \(error)\n".utf8))
        return 1
    }
}
