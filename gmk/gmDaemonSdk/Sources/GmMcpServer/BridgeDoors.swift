import Foundation
import GmDaemonSdk

/// The last of the bridge's roster: the named search doors, the two `projects_*`
/// doors, and the tools that exist in order to REFUSE.
///
/// THE BRIDGE IS THE ONLY SOURCE OF THIS VOCABULARY. Every name here is
/// declared by a `GmAgentTool` in `gmAgententicsSdk`: the plugin's
/// `allowed-tools` frontmatter is generated from the bridge, so a name the
/// server invents is never granted and a name the bridge declares but the
/// server does not serve is a grant resolving to nothing.

/// REFUSALS ARE PUBLISHED RATHER THAN OMITTED. An omitted tool is
/// indistinguishable from a capability nobody thought of, and an agent that
/// cannot see a refusal invents a workaround.
func makeBridgeDoorTools() -> [Tool] {
    [
        // THE SEARCH AND `projects_*` DOORS LIVE IN `RecallDoors.swift`, not
        // here. An earlier draft of this file declared them too and produced
        // DUPLICATE NAMES in `tools/list` — the same tool twice, which an MCP
        // client resolves by whichever it saw last. If a name appears in both
        // files, delete it from THIS one: `RecallDoors` holds the real
        // implementations, and this file holds only what nothing else covers.

        // ── The refusals ─────────────────────────────────────────────────
        refusal(
            "diagram_not_supported",
            "The diagram family is not served on this surface.",
            "Diagrams are authored in GMVibes and read through the DIAGRAM verbs; no agent-facing door is offered."
        ),
        refusal(
            "fs_not_supported",
            "The filesystem family is not served on this surface.",
            "File access belongs to the harness's own Read/Write/Edit tools, which are subject to its permission system. A second path around that is not a capability, it is a hole."
        ),
        refusal(
            "system_not_supported",
            "The system family is not served on this surface.",
            "Process and shell access belongs to the harness's Bash tool, where it is visible to the permission prompt and the PostToolUse capture."
        ),
    ]
}

/// A tool that exists to say no, and to say WHY.
///
/// The reason is the whole value. "Not supported" alone invites a retry with
/// different arguments; a named reason ends the question and points at whatever
/// does serve the need.
private func refusal(_ name: String, _ description: String, _ reason: String) -> Tool {
    Tool(
        name: name,
        description: "\(description) NOT AVAILABLE: \(reason)",
        params: [],
        refuses: true,
        run: { _, _ in
            throw ToolError(message: "\(name) is deliberately not supported. \(reason)")
        }
    )
}
