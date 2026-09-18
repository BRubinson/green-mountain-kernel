import GmHookCli

// The `gm_hook` executable: a shim over the `GmHookCli` LIBRARY, so the one
// multi-call `gm_kernel` Mach-O can carry this personality too. Both doors run
// identical code, since `~/gmfs/bin/gm_hook` is a symlink at the kernel binary
// and argv[0] dispatch lands in the same `GmHookCli.main(_:)` this calls. The
// target exists so `swift build` still produces a standalone `gm_hook`, which
// the release-store staging path and the test fixtures expect.
GmHookCli.main()
