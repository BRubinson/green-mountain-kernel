import Foundation

extension GmBridgeLsp {

    public static let sourcekit = Server(
        command: "sourcekit-lsp",
        extensionToLanguage: [".swift": "swift"]
    )

    public static let current = File(servers: [:])
}
