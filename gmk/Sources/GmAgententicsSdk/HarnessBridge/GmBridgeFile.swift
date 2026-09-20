import Foundation

protocol GmBridgeFile {

    var relativePath: String { get }

    var isEmpty: Bool { get }

    var isExecutable: Bool { get }

    func contents() throws -> String?
}

extension GmBridgeFile {

    var isEmpty: Bool { false }

    var isExecutable: Bool { false }
}

protocol GmBridgeJsonFile: GmBridgeFile, Encodable {}

extension GmBridgeJsonFile {

    func contents() throws -> String? {
        guard !isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self) + "\n"
    }
}
