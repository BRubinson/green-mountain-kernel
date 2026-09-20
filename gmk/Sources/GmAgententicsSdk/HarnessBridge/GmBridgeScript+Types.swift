import Foundation

enum GmBridgeScript {

    enum Location: String, Equatable, Hashable, Sendable, CaseIterable {

        case scripts

        case bin
    }

    enum Interpreter: String, Equatable, Hashable, Sendable, CaseIterable {

        case bash

        case zsh

        case python

        case node

        var shebang: String {
            switch self {
            case .bash: return "#!/usr/bin/env bash"
            case .zsh: return "#!/usr/bin/env zsh"
            case .python: return "#!/usr/bin/env python3"
            case .node: return "#!/usr/bin/env node"
            }
        }
    }

    struct File: Equatable, Sendable, GmBridgeFile {

        var name: String

        var location: Location

        var interpreter: Interpreter?

        var body: String

        init(
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

        var relativePath: String {
            "\(location.rawValue)/\(name)"
        }

        var pluginPath: String {
            "\(GmBridgeClaudeTypePath.pluginRoot)/\(relativePath)"
        }

        var isEmpty: Bool {
            body.isEmpty
        }

        var isExecutable: Bool { true }

        func contents() -> String? {
            guard !isEmpty else { return nil }

            let content = body.hasSuffix("\n") ? body : body + "\n"
            guard let interpreter, !body.hasPrefix("#!") else { return content }
            return interpreter.shebang + "\n" + content
        }
    }
}
