import Foundation

extension GmBridgeLsp {

    static let sourcekit = Server(
        command: "sourcekit-lsp",
        extensionToLanguage: [".swift": "swift"]
    )

    static let current = File(servers: [:])
}
