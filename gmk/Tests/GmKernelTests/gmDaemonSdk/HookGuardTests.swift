import Foundation
import GmDaemonSdk
import XCTest

/// The PreToolUse guard: `gm_hook` is the harness's client and an agent never
/// calls it, so a Bash command that invokes it is DENIED.
///
/// Pure string work — no kernel, no socket — so this is a plain `XCTestCase`
/// rather than a `KernelBackedTestCase`. Both directions are pinned: the
/// invocations that must be refused, and the mentions that must NOT be, because
/// a guard that trips on `grep gm_hook` makes this repository undevelopable
/// from inside its own tooling.
final class HookGuardTests: XCTestCase {

    func testCommandPositionInvocationsAreDenied() {
        for command in [
            "gm_hook call BACKUP --json '{}'",
            "  gm_hook verbs --json",
            "~/gmfs/bin/gm_hook paths --json",
            "\"${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_hook\" context ensure",
            "cd /tmp && gm_hook status",
            "true; gm_hook ping",
            "echo x | gm_hook hook post-tool-use",
            "exec gm_hook hook pre-tool-use",
            "OUT=$(gm_hook paths --json)",
            "(gm_hook status)",
            "gm_hook",
        ] {
            XCTAssertTrue(HookRunner.invokesGmHook(command), "must deny: \(command)")
        }
    }

    func testMentionsThatAreNotInvocationsPass() {
        for command in [
            "grep -rn gm_hook plugins/gmcc",
            "grep -rn \"gm_hook\" gmk/",
            "ls -la ~/gmfs/bin",
            "echo 'gm_hook is the harness client'",
            "git log --oneline -- gmk/gmDaemonSdk/Sources/GmHookCli",
            "swift build --package-path gmk/gmKernel",
            "cat plugins/gmcc/hooks/hooks.json",
            "rg gm_hook_missing .",
            "bash gmk/scripts/rebuild_local.sh",
        ] {
            XCTAssertFalse(HookRunner.invokesGmHook(command), "must allow: \(command)")
        }
    }

    func testTheHookResponseIsADeny() throws {
        let payload = #"{"tool_name":"Bash","tool_input":{"command":"gm_hook call BACKUP --json '{}'"}}"#
        let line = try XCTUnwrap(HookRunner.preToolUse(stdin: Data(payload.utf8)))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let specific = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(specific["permissionDecision"] as? String, "deny")
    }

    func testANonInvokingCommandIsSilent() {
        let payload = #"{"tool_name":"Bash","tool_input":{"command":"grep -rn gm_hook plugins/"}}"#
        XCTAssertNil(HookRunner.preToolUse(stdin: Data(payload.utf8)))
    }

    func testOtherToolsAreSilent() {
        let payload = #"{"tool_name":"Edit","tool_input":{"command":"gm_hook call BACKUP"}}"#
        XCTAssertNil(HookRunner.preToolUse(stdin: Data(payload.utf8)))
    }
}
