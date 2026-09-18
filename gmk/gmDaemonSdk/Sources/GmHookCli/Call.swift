import Foundation
import GmDaemonSdk

/// Any JSON value, as a Codable — the type that makes an untyped passthrough
/// possible without teaching the client 123 payload shapes.
///
/// It rides the SAME `DaemonClient.request` as every typed verb, so it inherits
/// the hello handshake, the protocol-version check, the reconnect-once retry and
/// the server-error mapping. A hand-rolled socket write would inherit none of
/// that and would be a second wire client to keep in step.
///
/// THE TYPE ITSELF MOVED TO `GmDaemonSdk` AT v30 (`GmJsonValue`), because the
/// harness envelope — `MCP_CALL` and `HOOK_EVENT` — needs the same shape on the
/// protocol side. The alias keeps every use site below reading as it did; see
/// `Protocol/GmJsonValue.swift` for why one type beat two copies.
typealias JSONValue = GmJsonValue

/// `gm_hook call <MESSAGE_TYPE> [--json '<payload>' | --json-file <path>]`
///
/// KEYS ARE SENT VERBATIM. The wire is snake_case, and this does not translate
/// — a caller reaching for the raw passthrough is working at wire level and a
/// silent key rewrite here would be a second dialect to learn.
func runCall(_ argv: [String]) -> Int32 {
    guard let typeName = argv.first, !typeName.hasPrefix("-") else {
        FileHandle.standardError.write(
            Data("[GMB] usage: gm_hook call <MESSAGE_TYPE> [--json '<payload>'] [--json-file <path>]\n".utf8))
        return 2
    }
    guard let type = MessageType(rawValue: typeName.uppercased()) else {
        FileHandle.standardError.write(
            Data(
                """
                [GMB] unknown message type '\(typeName)'. `gm_hook verbs --json` lists every type the daemon serves.

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
