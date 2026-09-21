import Foundation
import XCTest

/// The PreToolUse guard: `gm_hook` and the generated `gm_hook_*` executables are
/// the harness's clients, so a Bash command that invokes one is DENIED.
///
/// Pure string work — no kernel, no socket — so a plain `XCTestCase`. Both
/// directions are pinned: the invocations that must be refused, and the
/// mentions that must NOT be, because a guard that trips on `grep gm_hook`
/// makes this repository undevelopable from inside its own tooling.
final class HookGuardTests: XCTestCase {

    private func preToolUse(_ payload: String) -> String? {
        PreToolUseHook.run(GmHookContext(stdin: Data(payload.utf8), dryRun: false, caller: nil))
    }

    func testCommandPositionInvocationsAreDenied() {
        for command in [
            "gm_hook call BACKUP --json '{}'",
            "  gm_hook verbs --json",
            "~/gmfs/bin/gm_hook paths --json",
            "\"${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_hook\" context ensure",
            "cd /tmp && gm_hook status",
            "true; gm_hook ping",
            "gm_hook_post_tool_use --dry-run",
            "echo x | ~/.claude/plugins/cache/gmcc/hooks/bin/gm_hook_subagent_start",
            "exec \"${CLAUDE_PLUGIN_ROOT}/hooks/bin/gm_hook_pre_tool_use\"",
            "OUT=$(gm_hook paths --json)",
            "(gm_hook status)",
            "gm_hook",
        ] {
            XCTAssertTrue(GmHookSupport.invokesGmHook(command), "must deny: \(command)")
        }
    }

    func testMentionsThatAreNotInvocationsPass() {
        for command in [
            "grep -rn gm_hook plugins/gmcc",
            "grep -rn \"gm_hook\" gmk/",
            "ls -la ~/gmfs/bin",
            "echo 'gm_hook is the harness client'",
            "git log --oneline -- gmk/Sources/API/Clients/GmKernelCoreClient/HookCli",
            "cat plugins/gmcc/hooks/hooks.json",
            "cat plugins/gmcc/hooks/bin/gm_hook_post_tool_use",
            "ls plugins/gmcc/hooks/src",
            "rg gm_hook_missing .",
            "bash gmk/scripts/rebuild_local.sh",
        ] {
            XCTAssertFalse(GmHookSupport.invokesGmHook(command), "must allow: \(command)")
        }
    }

    func testEveryRegisteredHookBinaryIsInTheDenySet() {
        for event in GmHookEvent.allCases {
            XCTAssertTrue(GmHookSupport.invokesGmHook(event.binaryName), "must deny: \(event.binaryName)")
        }
    }

    func testTheHookResponseIsADeny() throws {
        let payload = #"{"tool_name":"Bash","tool_input":{"command":"gm_hook call BACKUP --json '{}'"}}"#
        let line = try XCTUnwrap(preToolUse(payload))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let specific = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(specific["permissionDecision"] as? String, "deny")
    }

    func testANonInvokingCommandIsSilent() {
        let payload = #"{"tool_name":"Bash","tool_input":{"command":"grep -rn gm_hook plugins/"}}"#
        XCTAssertNil(preToolUse(payload))
    }

    func testOtherToolsAreSilent() {
        let payload = #"{"tool_name":"Edit","tool_input":{"command":"gm_hook call BACKUP"}}"#
        XCTAssertNil(preToolUse(payload))
    }
}
