import XCTest
@testable import GMCCDaemonKit

/// Item 2's fixture cases: normal branch, nested-slash branch, detached HEAD,
/// linked worktree (.git as file, absolute gitdir), submodule-style relative
/// gitdir, and missing/unreadable roots.
final class GitHeadTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("githead-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
    }

    private func makeRepo(_ name: String, head: String, gitIsFile: String? = nil) throws -> String {
        let repo = fixtureRoot.appendingPathComponent(name, isDirectory: true)
        if let gitdirLine = gitIsFile {
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            try gitdirLine.write(
                to: repo.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        } else {
            let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
            try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
            try head.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        }
        return repo.path
    }

    func testBranch() throws {
        let repo = try makeRepo("normal", head: "ref: refs/heads/main\n")
        XCTAssertEqual(GitHead.resolve(repoRoot: repo), .branch("main"))
    }

    func testNestedSlashBranchSlugsForwardOnly() throws {
        let repo = try makeRepo("nested", head: "ref: refs/heads/feature/nested-slash\n")
        guard case .branch(let branch) = GitHead.resolve(repoRoot: repo) else {
            return XCTFail("expected branch")
        }
        XCTAssertEqual(GitHead.sessionCode(forBranch: branch), "feature__nested-slash")
    }

    func testDetached() throws {
        let repo = try makeRepo("detached", head: "96c92a7e2f1e2b6a2a54371a9b2c3d4e5f60718293a4b5c6\n")
        XCTAssertEqual(GitHead.resolve(repoRoot: repo), .detached)
    }

    func testWorktreeAbsoluteGitdir() throws {
        // Real repo holding the worktree metadata…
        let backing = fixtureRoot.appendingPathComponent("backing/.git/worktrees/wt", isDirectory: true)
        try FileManager.default.createDirectory(at: backing, withIntermediateDirectories: true)
        try "ref: refs/heads/wt-branch\n".write(
            to: backing.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        // …and the worktree checkout whose .git is a FILE with an absolute gitdir.
        let repo = try makeRepo("worktree", head: "", gitIsFile: "gitdir: \(backing.path)\n")
        XCTAssertEqual(GitHead.resolve(repoRoot: repo), .branch("wt-branch"))
    }

    func testSubmoduleRelativeGitdir() throws {
        // Submodules emit "gitdir: ../.git/modules/name" — resolved against
        // the repo root.
        let modules = fixtureRoot.appendingPathComponent("parent/.git/modules/sub", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try "ref: refs/heads/sub-main\n".write(
            to: modules.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let sub = fixtureRoot.appendingPathComponent("parent/sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "gitdir: ../.git/modules/sub\n".write(
            to: sub.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(GitHead.resolve(repoRoot: sub.path), .branch("sub-main"))
    }

    func testMissingRootUnavailable() throws {
        XCTAssertEqual(GitHead.resolve(repoRoot: fixtureRoot.path + "/does-not-exist"), .unavailable)
        // A directory with no .git at all.
        let bare = fixtureRoot.appendingPathComponent("no-git", isDirectory: true)
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        XCTAssertEqual(GitHead.resolve(repoRoot: bare.path), .unavailable)
    }
}
