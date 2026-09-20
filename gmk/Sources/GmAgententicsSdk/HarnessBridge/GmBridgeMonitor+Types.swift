import Foundation

public enum GmBridgeMonitor {

    public enum When: Equatable, Hashable, Sendable {

        case always

        case onSkillInvoke(String)

        public var wireValue: String {
            switch self {
            case .always: return "always"
            case .onSkillInvoke(let skill): return "on-skill-invoke:\(skill)"
            }
        }
    }

    public struct Entry: Encodable, Equatable, Sendable {

        public var name: String

        public var command: String

        public var description: String

        public var when: When?

        public init(
            name: String,
            command: String,
            description: String,
            when: When? = nil
        ) {
            self.name = name
            self.command = command
            self.description = description
            self.when = when
        }

        enum CodingKeys: String, CodingKey {
            case name
            case command
            case description
            case when
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(command, forKey: .command)
            try container.encode(description, forKey: .description)
            try container.encodeIfPresent(when?.wireValue, forKey: .when)
        }
    }

    public struct File: Encodable, Equatable, Sendable, GmBridgeJsonFile {

        public var relativePath: String { "monitors/monitors.json" }

        public var monitors: [Entry]

        public init(monitors: [Entry]) {
            self.monitors = monitors
        }

        public var isEmpty: Bool {
            monitors.isEmpty
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(monitors)
        }
    }
}
