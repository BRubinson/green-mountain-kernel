import GmHookCli

// The `gm_hook` executable, reduced to a shim.
//
// The implementation lives in the `GmHookCli` LIBRARY so the one multi-call
// `gm_kernel` Mach-O can carry this personality too. Both doors run identical
// code: `~/gmfs/bin/gm_hook` is a symlink at the kernel binary, which dispatches
// on argv[0] and lands in the same `GmHookCli.main(_:)` this shim calls.
//
// This target survives so `swift build` still produces a standalone `gm_hook`,
// which is what the release-store staging path and `swift test` fixtures expect.
GmHookCli.main()
