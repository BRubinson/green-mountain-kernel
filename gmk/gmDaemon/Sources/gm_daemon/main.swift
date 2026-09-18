import GmKernelHost

// The `gm_daemon` executable is a shim over the `GmKernelHost` library, so the
// multi-call `gm_kernel` Mach-O and the app bundle run one implementation of the server.
// The headless personality is load-bearing: `DaemonClient.autostart()` spawns a binary
// from hooks, SSH and CI, none of which can launch an application.
KernelHost.bootHeadlessAndRun()
