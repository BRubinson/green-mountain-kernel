import Foundation

enum GmBridgeTheme {

    enum Base: String, Codable, Equatable, Hashable, Sendable, CaseIterable {

        case dark

        case light
    }

    struct File: Encodable, Equatable, Sendable, GmBridgeJsonFile {

        var slug: String

        var name: String

        var base: Base

        var overrides: [String: String]

        /// Creates a theme file specification.
        ///
        /// - Parameters:
        ///   - slug: The theme slug identifier.
        ///   - name: The human-readable theme name.
        ///   - base: The base theme to override.
        ///   - overrides: Optional color overrides.
        init(
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

        var relativePath: String {
            "themes/\(slug).json"
        }

        var selector: String {
            "custom:\(GmBridgeClaudePlugin.current.name):\(slug)"
        }

        enum CodingKeys: String, CodingKey {
            case name
            case base
            case overrides
        }
    }
}
