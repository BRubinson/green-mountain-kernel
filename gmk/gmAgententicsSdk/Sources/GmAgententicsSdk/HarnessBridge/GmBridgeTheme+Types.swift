import Foundation

public enum GmBridgeTheme {

    public enum Base: String, Codable, Equatable, Hashable, Sendable, CaseIterable {

        case dark

        case light
    }

    public struct File: Encodable, Equatable, Sendable, GmBridgeJsonFile {

        public var slug: String

        public var name: String

        public var base: Base

        public var overrides: [String: String]

        public init(
            slug: String,
            name: String,
            base: Base,
            overrides: [String: String] = [:]
        ) {
            self.slug = slug
            self.name = name
            self.base = base
            self.overrides = overrides
        }

        public var relativePath: String {
            "themes/\(slug).json"
        }

        public var selector: String {
            "custom:\(GmBridgeClaudePlugin.current.name):\(slug)"
        }

        enum CodingKeys: String, CodingKey {
            case name
            case base
            case overrides
        }
    }
}
