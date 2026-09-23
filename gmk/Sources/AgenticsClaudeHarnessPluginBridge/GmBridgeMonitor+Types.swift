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

        /// Creates a monitor entry with command, name, and optional trigger.
        ///
        /// - Parameters:
        ///   - name: The monitor's display name.
        ///   - command: The command to run when triggered.
        ///   - description: A description of what the monitor does.
        ///   - when: When to run the monitor; defaults to nil.
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

        /// Encodes the monitor entry to the given encoder.
        ///
        /// - Parameter encoder: The encoder to encode into.
        /// - Throws: `EncodingError` if encoding fails.
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

        /// Creates a monitors file with the given entries.
        ///
        /// - Parameter monitors: The monitor entries to include.
        init(monitors: [Entry]) {
            self.monitors = monitors
        }

        var isEmpty: Bool {
            monitors.isEmpty
        }

        /// Encodes the monitors file to the given encoder.
        ///
        /// - Parameter encoder: The encoder to encode into.
        /// - Throws: `EncodingError` if encoding fails.
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(monitors)
        }
    }
}
