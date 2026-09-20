import Foundation

enum GmBridgeMonitor {

    enum When: Equatable, Hashable, Sendable {

        case always

        case onSkillInvoke(String)

        var wireValue: String {
            switch self {
            case .always: return "always"
            case .onSkillInvoke(let skill): return "on-skill-invoke:\(skill)"
            }
        }
    }

    struct Entry: Encodable, Equatable, Sendable {

        var name: String

        var command: String

        var description: String

        var when: When?

        init(
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

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(command, forKey: .command)
            try container.encode(description, forKey: .description)
            try container.encodeIfPresent(when?.wireValue, forKey: .when)
        }
    }

    struct File: Encodable, Equatable, Sendable, GmBridgeJsonFile {

        var relativePath: String { "monitors/monitors.json" }

        var monitors: [Entry]

        init(monitors: [Entry]) {
            self.monitors = monitors
        }

        var isEmpty: Bool {
            monitors.isEmpty
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(monitors)
        }
    }
}
