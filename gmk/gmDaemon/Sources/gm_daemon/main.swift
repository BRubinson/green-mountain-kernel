import GmKernelHost

// The `gm_daemon` executable, reduced to a shim.
//
// The host lives in the `GmKernelHost` LIBRARY so the one multi-call `gm_kernel`
// Mach-O and the app bundle can both run it — one implementation of the server,
// compiled into two hosts, never two implementations.
//
// This target survives because the headless personality is load-bearing:
// `DaemonClient.autostart()` spawns a binary from hooks, SSH and CI, none of
// which can launch an application. See `KernelHost` for why that rules out an
// app-only writer.
KernelHost.bootHeadlessAndRun()
