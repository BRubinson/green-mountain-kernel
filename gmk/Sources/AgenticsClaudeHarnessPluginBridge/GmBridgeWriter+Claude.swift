//
//  GmBridgeWriter+Claude.swift
//  gmAgententicsSdk
//
//  Created by Bryce Rubinson on 9/13/26.
//

import Foundation

/// Writes the ENTIRE `plugins/gmcc` Claude Code plugin from the bridge values in
/// this package, and from nothing else.
///
/// Nothing is read back out of the existing plugin, so a missing file is fixed by
/// declaring a `GmBridgeFile`, never by special-casing it here. Each type renders
/// its own `contents()`, leaving the writer a loop. Output is sorted by path and
/// JSON is `.sortedKeys` + `.withoutEscapingSlashes`: a delete-and-rewrite plugin
/// is reviewable only while its regeneration stays diffable.
enum GmBridgeWriter {

    /// What one run did, so a caller can report it without re-reading the tree.
    struct Report: Sendable {
        var written: [String] = []
        /// Declared, but rendered nothing — `contents()` returned nil.
        ///
        /// Never silent. A quietly skipped script leaves `hooks.json` and
        /// `.mcp.json` pointing at files that do not exist — a plugin that
        /// installs, boots and records nothing. Every omission is reported, and
        /// `verify` turns the boot-critical ones into a refusal.
        var omitted: [String] = []
        var bytes: Int = 0
        /// Pen-tool names cited by the rendered tree that the served roster does
        /// not carry — a grant or an instruction that resolves to nothing.
        var unknownToolNames: [String] = []
        /// Disagreements between the reflected roster and the declarations it is
        /// reflected from.
        var rosterProblems: [String] = []
    }

    enum WriteError: Error, CustomStringConvertible {
        case notAbsolute(String)
        case missingBootCritical([String])
        case refusedOutsideRepo(String)

        var description: String {
            switch self {
            case .notAbsolute(let path):
                return "output directory must be an absolute path, got '\(path)'"
            case .missingBootCritical(let paths):
                return """
                    refusing to write: \(paths.count) boot-critical file(s) rendered nothing — \
                    \(paths.sorted().joined(separator: ", ")). A plugin missing these installs \
                    and then does nothing, silently. Declare their contents in the bridge first.
                    """
            case .refusedOutsideRepo(let path):
                return "refusing to delete '\(path)': it is not a plugin directory this writer recognises"
            }
        }
    }

    /// Files whose absence breaks the plugin at boot rather than degrading it.
    ///
    /// Chosen by CONSEQUENCE, not by importance. `hooks/hooks.json` names the
    /// SessionStart script and three executables under `hooks/bin`, and
    /// `.mcp.json` names `bin/gm_mcp` — all five binaries produced by
    /// `build_plugin_binaries.sh` AFTER the swap, never by this writer. If the
    /// manifests are emitted and those are not, every hook is a dangling exec
    /// that exits 0 silently and the pen refuses to start, loudly.
    static let bootCritical: Set<String> = [
        ".claude-plugin/plugin.json",
        "hooks/hooks.json",
        ".mcp.json",
        "scripts/gm_session_startup.sh",
        "scripts/install_gm.sh",
        "scripts/gm_releases.sh",
    ]

    /// Every file the plugin consists of, in a stable order.
    ///
    /// Ordering is by `relativePath` rather than by declaration order so two
    /// runs of the same bridge produce byte-identical trees regardless of how
    /// the `all` arrays happen to be written.
    static var files: [any GmBridgeFile] {
        var all: [any GmBridgeFile] = [
            GmBridgeClaudePlugin.current,
            GmBridgeClaudePluginSettings.current,
            GmBridgeMcp.current,
            GmBridgeHook.current,
            GmBridgeLsp.current,
            GmBridgeMonitor.current,
        ]
        all += GmBridgeHook.sources as [any GmBridgeFile]
        all += GmBridgePersonality.sources as [any GmBridgeFile]
        all += GmBridgeSkill.all as [any GmBridgeFile]
        all += GmBridgeSkillPhase.all as [any GmBridgeFile]
        all += GmBridgeCommand.all as [any GmBridgeFile]
        all += GmBridgeAgent.all as [any GmBridgeFile]
        all += GmBridgeScript.all as [any GmBridgeFile]
        all += GmBridgeResource.all as [any GmBridgeFile]
        all += GmBridgePrompt.all as [any GmBridgeFile]
        all += GmBridgeWorkflow.all as [any GmBridgeFile]
        all += GmBridgeOutputStyle.all as [any GmBridgeFile]
        all += GmBridgeTheme.all as [any GmBridgeFile]
        return all.sorted { $0.relativePath < $1.relativePath }
    }

    /// Render every file WITHOUT touching the disk.
    ///
    /// The half that `--check` runs and the half `write` reuses, so the thing
    /// inspected and the thing written cannot differ.
    /// Renders the plugin file tree from bridge instructions.
    ///
    /// - Returns: A tuple with rendered files (path, body, executable flag) and omitted file paths.
    static func render() -> (rendered: [(path: String, body: String, executable: Bool)], omitted: [String]) {
        var rendered: [(String, String, Bool)] = []
        var omitted: [String] = []
        for file in files {
            guard let body = (try? file.contents()) ?? nil else {
                omitted.append(file.relativePath)
                continue
            }
            rendered.append((file.relativePath, body, file.isExecutable))
        }
        return (rendered, omitted)
    }

    /// Verifies that the render is complete and the roster is valid.
    ///
    /// Separate from `write` on purpose. The check is runnable without the
    /// destructive step, so `--check` is a real answer rather than a rehearsal
    /// of a different code path.
    ///
    /// - Returns: A report with written files, omitted files, byte count, unknown tool names, and roster problems.
    /// - Throws: `WriteError.missingBootCritical` if any boot-critical files are missing; `WriteError` errors on verification failure.
    static func verify() throws -> Report {
        let (rendered, omitted) = render()
        let fatal = Set(omitted).intersection(bootCritical)
        if !fatal.isEmpty { throw WriteError.missingBootCritical(Array(fatal)) }
        return Report(
            written: rendered.map(\.path).sorted(),
            omitted: omitted.sorted(),
            bytes: rendered.reduce(0) { $0 + $1.body.utf8.count },
            unknownToolNames: unknownToolNames(in: rendered),
            rosterProblems: rosterProblems()
        )
    }

    /// The qualified spelling of a pen tool: what `allowed-tools` frontmatter
    /// carries and what the harness resolves a call against.
    ///
    /// Computed rather than stored: `Regex` is not `Sendable`, so a static let
    /// would be a shared mutable global.
    static var qualifiedToolCitation: Regex<(Substring, Substring)> {
        /mcp__plugin_gmcc_cde__([a-z0-9_]+)/
    }

    /// The bare, backticked spelling the phase and instruction prose uses when
    /// it names a tool beside its op.
    static var bareToolCitation: Regex<(Substring, Substring)> {
        /`(cde_[a-z0-9_]+)`/
    }

    /// Returns every cde tool name cited in a body, in either spelling.
    ///
    /// What a body cites is what its reader will reach for, so a grant derived
    /// from this cannot omit a tool the prose sends an agent after.
    ///
    /// - Parameter body: The text to search for tool citations.
    /// - Returns: A set of cde tool names found in the body.
    static func citedToolNames(in body: String) -> Set<String> {
        var names: Set<String> = []
        for match in body.matches(of: qualifiedToolCitation) { names.insert(String(match.1)) }
        for match in body.matches(of: bareToolCitation) { names.insert(String(match.1)) }
        return names
    }

    /// Returns every qualified tool name cited but not served.
    ///
    /// Checks both `allowed-tools` frontmatter and prose. A name nothing serves
    /// is silent at runtime in both directions: a grant resolves to no tool,
    /// and an instruction sends an agent after a door that is not there.
    ///
    /// - Parameter rendered: The rendered file tuples with paths and bodies.
    /// - Returns: A sorted array of unknown tool names.
    static func unknownToolNames(
        in rendered: [(path: String, body: String, executable: Bool)]
    ) -> [String] {
        let served = Set(GmAgentTools.names)
        var unknown: Set<String> = []
        for file in rendered {
            for match in file.body.matches(of: qualifiedToolCitation)
            where !served.contains(String(match.1)) {
                unknown.insert(String(match.1))
            }
        }
        return unknown.sorted()
    }

    /// Checks the reflected roster against declared tool schemas.
    ///
    /// Verifies that reflected names match declared names, and each tool's op
    /// table matches the enum its schema advertises.
    ///
    /// - Returns: An array of problem descriptions; empty if no problems found.
    static func rosterProblems() -> [String] {
        do {
            let reflected = try GmBridgeRoster.specs().map(\.name).sorted()
            let declared = GmAgentTools.names.sorted()
            guard reflected != declared else { return [] }
            return [
                "the reflected roster and GmAgentTools disagree — reflected "
                    + "[\(reflected.joined(separator: ", "))] vs declared "
                    + "[\(declared.joined(separator: ", "))]"
            ]
        } catch {
            return ["\(error)"]
        }
    }

    /// Rewrites the plugin directory with the rendered bridge output.
    ///
    /// Uses stage-and-swap: the tree is built beside the target and moved
    /// through a trash directory, so a crash leaves either the old tree or the
    /// new one rather than a half-plugin. Verification runs first to ensure
    /// bootability.
    ///
    /// - Parameter directory: The plugin directory to write to; must be absolute.
    /// - Returns: A report with written files, omitted files, byte count, unknown tool names, and roster problems.
    /// - Throws: `WriteError.notAbsolute` if the directory path is not absolute; `WriteError.refusedOutsideRepo` if the directory is not a plugin; `WriteError` errors on write failure.
    @discardableResult
    static func write(to directory: URL) throws -> Report {
        guard directory.path.hasPrefix("/") else {
            throw WriteError.notAbsolute(directory.path)
        }
        // A guard against being pointed at the wrong directory: the target must
        // either already be a plugin, or not exist. Anything else and the
        // delete is somebody's source tree.
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) {
            let manifest = directory.appendingPathComponent(".claude-plugin/plugin.json")
            guard fm.fileExists(atPath: manifest.path) else {
                throw WriteError.refusedOutsideRepo(directory.path)
            }
        }

        let report = try verify()
        let (rendered, _) = render()

        let parent = directory.deletingLastPathComponent()
        let stamp = "\(ProcessInfo.processInfo.processIdentifier)"
        let staging = parent.appendingPathComponent(".\(directory.lastPathComponent).staging-\(stamp)")
        let trash = parent.appendingPathComponent(".\(directory.lastPathComponent).trash-\(stamp)")

        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        for (path, body, executable) in rendered {
            let target = staging.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: target, atomically: true, encoding: .utf8)
            if executable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            }
        }

        // THE SWAP. Move the old tree aside before moving the new one in, so
        // there is no moment where the path does not exist.
        if fm.fileExists(atPath: directory.path) {
            try fm.moveItem(at: directory, to: trash)
        }
        do {
            try fm.moveItem(at: staging, to: directory)
        } catch {
            // Put it back rather than leaving the caller with nothing.
            if fm.fileExists(atPath: trash.path) {
                try? fm.moveItem(at: trash, to: directory)
            }
            throw error
        }
        try? fm.removeItem(at: trash)
        return report
    }
}
