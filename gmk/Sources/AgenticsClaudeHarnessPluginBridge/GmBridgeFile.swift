import Foundation

protocol GmBridgeFile {

    var relativePath: String { get }

    var isEmpty: Bool { get }

    var isExecutable: Bool { get }

    /// Renders the file contents as a string.
    ///
    /// - Returns: The rendered content, or nil if the file is empty.
    /// - Throws: Encoding errors when rendering fails.
    func contents() throws -> String?
}

extension GmBridgeFile {

    var isEmpty: Bool { false }

    var isExecutable: Bool { false }
}

protocol GmBridgeJsonFile: GmBridgeFile, Encodable {}

extension GmBridgeJsonFile {

    /// Encodes the file as JSON with sorted keys and pretty printing.
    ///
    /// - Returns: The JSON representation with a trailing newline, or nil if empty.
    /// - Throws: Encoding errors from the JSON encoder.
    func contents() throws -> String? {
        guard !isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self) + "\n"
    }
}
