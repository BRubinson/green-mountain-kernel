import GmMcpServer

// The `gm_mcp` executable, reduced to a shim.
//
// The server lives in the `GmMcpServer` LIBRARY so the one multi-call
// `gm_kernel` Mach-O can serve the pen too. `.mcp.json` still names a `command`
// and `run_mcp.sh` still execs `$GM_BIN/gm_mcp` — that path is now a symlink at
// the kernel binary, which dispatches on argv[0] into this same entry point.
// Keeping the manifest's `command` string is what keeps
// DocsContractTests.testMcpManifestIsWellFormedAndEveryServerLaunches green.
GmMcpServer.main()
