import GmDaemonSdk
import SwiftUI

@main
struct GMVibesApp: App {
    // Bounded flush of dirty prompt edits on quit (replaces the old
    // synchronous main-thread write in onDisappear).
    @NSApplicationDelegateAdaptor(GMVibesAppDelegate.self) private var appDelegate
    @State private var services: GMVibesServices
    @State private var vitals: KernelVitals
    @Environment(\.openWindow) private var openWindow

    /// NO SECOND POLLER. `DaemonConnectionModel` already runs the health
    /// watchdog and keeps `ping` current, so the vitals sampler is wired to READ
    /// that rather than open its own connection — one socket, one cadence, and no
    /// chance of the menu bar disagreeing with the status pill about whether the
    /// kernel is up.
    ///
    /// Built in `init` because `KernelVitals` takes its report source as a
    /// closure at construction, and a `@State` default cannot reference another
    /// `@State` property.
    init() {
        let services = GMVibesServices()
        _services = State(initialValue: services)
        _vitals = State(initialValue: KernelVitals(report: {
            guard let ping = services.daemon.ping else { return nil }
            return KernelVitalsReport(
                uptimeSeconds: ping.uptimeSeconds,
                residentMemoryBytes: ping.residentMemoryBytes,
                cpuPercent: ping.cpuPercent)
        }))
    }

    /// Who holds the database, as the answering kernel reports it.
    ///
    /// `writerRole` and `writerBundlePath` are additive optionals, so a kernel
    /// that predates them answers nil and this reads `.unknown` — which is
    /// correct rather than merely safe: this app does not yet host the writer, so
    /// claiming either role would be a lie.
    private var role: KernelRole {
        guard let ping = services.daemon.ping else { return .unknown }
        return KernelRole(
            writerRole: ping.writerRole,
            holderPid: ping.daemonPid,
            bundlePath: ping.writerBundlePath)
    }

    var body: some Scene {
        // THE MENU BAR IS DECLARED FIRST, BEFORE THE WindowGroup, AND THE ORDER
        // IS LOAD-BEARING.
        //
        // Two reasons. A resident kernel that popped a window at every login
        // would be a regression nobody asked for, and scene order is what decides
        // whether SwiftUI opens one. And `INFOPLIST_KEY_LSUIElement = YES` removes
        // the Dock icon — so without a menu-bar item shipping in the SAME change,
        // the app would have no Dock presence AND no menu presence, which is
        // strictly worse than having a Dock icon. The two must land together.
        //
        // LSUIElement governs the LAUNCH state only. It is process-wide, and the
        // windows below are ordinary app windows that need a Dock entry, a
        // ⌘-Tab slot, a main menu and a window manager willing to tile them —
        // so `WindowPresence` raises the activation policy to `.regular` while
        // any window is open and drops it back on the last close. Only the
        // resident kernel is invisible; its windows are not.
        MenuBarExtra {
            KernelMenuBarContent(
                role: role,
                vitals: vitals,
                protocolVersion: services.daemon.ping?.protocolVersion,
                buildSha: services.daemon.ping?.buildSha,
                onNewWindow: { openWindow(value: WindowSeed()) },
                onQuit: { NSApp.terminate(nil) },
                onActivateHolder: nil)
        } label: {
            // NO `.renderingMode(.original)` here — template rendering is the
            // point. It is what lets the status bar tint the glyph with the
            // rest of the row, in both appearances and while highlighted.
            Image(nsImage: KernelMenuBarIcon.image)
        }
        // `.window`, not the default `.menu`. AppKit's menu style renders only
        // menu items and would drop the role row's colour and layout — the one
        // thing that has to be unmissable, because client mode is the mitigation
        // for a second copy and a mitigation nobody can see is cosmetic.
        .menuBarExtraStyle(.window)

        // THE window type. Every window navigates the whole app via WindowNav;
        // WindowSeed's per-open UUID makes dedupe structurally impossible, and
        // its decoder always yields landing so restoration lands there too.
        WindowGroup("GM Vibes", for: WindowSeed.self) { $seed in
            GMVibesWindow(seed: seed ?? WindowSeed())
                .gmEnv(services)
        } defaultValue: {
            WindowSeed()
        }
        .windowResizability(.contentMinSize)
        .commands {
            FindCommands()
            PaletteCommands()
        }
    }

}

struct PaletteCommands: Commands {
    @FocusedValue(\.commandPalette) private var openPalette: (() -> Void)?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Command Palette…") { openPalette?() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(openPalette == nil)
        }
    }
}

struct FindCommands: Commands {
    @FocusedValue(\.findInPage) private var find: (() -> Void)?
    @FocusedValue(\.findNext) private var findNext: (() -> Void)?
    @FocusedValue(\.findPrevious) private var findPrev: (() -> Void)?

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find\u{2026}") { find?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(find == nil)
            Button("Find Next") { findNext?() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(findNext == nil)
            Button("Find Previous") { findPrev?() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(findPrev == nil)
        }
    }
}
