import Foundation

public enum GmBridgeScript {

    public enum Location: String, Equatable, Hashable, Sendable, CaseIterable {

        case scripts

        case bin
    }

    public enum Interpreter: String, Equatable, Hashable, Sendable, CaseIterable {

        case bash

        case zsh

        case python

        case node

        public var shebang: String {
            switch self {
            case .bash: return "#!/usr/bin/env bash"
            case .zsh: return "#!/usr/bin/env zsh"
            case .python: return "#!/usr/bin/env python3"
            case .node: return "#!/usr/bin/env node"
            }
        }
    }

    public struct File: Equatable, Sendable, GmBridgeFile {

        public var name: String

        public var location: Location

        public var interpreter: Interpreter?

        public var body: String

        public init(
            name: String,
            location: Location = .scripts,
            interpreter: Interpreter? = nil,
            body: String = ""
        ) {
            self.name = name
            self.location = location
            self.interpreter = interpreter
            self.body = body
        }

        public var relativePath: String {
            "\(location.rawValue)/\(name)"
        }

        public var pluginPath: String {
            "\(GmBridgeClaudeTypePath.pluginRoot)/\(relativePath)"
        }

        public var isEmpty: Bool {
            body.isEmpty
        }

        public var isExecutable: Bool { true }

        public func contents() throws -> String? {
            guard !isEmpty else { return nil }

            let content = body.hasSuffix("\n") ? body : body + "\n"
            guard let interpreter, !body.hasPrefix("#!") else { return content }
            return interpreter.shebang + "\n" + content
        }
    }
}
