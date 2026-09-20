import GmDaemonSdk
import SwiftUI

/// The app personality. `main.swift` calls `GMVibesApp.main()`; a target with a
/// `main.swift` cannot also carry `@main`.
struct GMVibesApp: App {
    // Bounded flush of dirty prompt edits on quit.
    @NSApplicationDelegateAdaptor(GMVibesAppDelegate.self) private var appDelegate
    @State private var services: GMVibesServices
    @State private var vitals: KernelVitals
    @Environment(\.openWindow) private var openWindow

    /// NO SECOND POLLER. `DaemonConnectionModel` runs the health watchdog and keeps `ping`
    /// current, so the vitals sampler READS that rather than opening its own connection: one
    /// socket, one cadence, and no chance of the menu bar disagreeing with the status pill.
    init() {
        // ORDER IS FIXED HERE AND MUST NOT BE TIDIED. `GMVibesServices()` ARBITRATES DATABASE
        // OWNERSHIP on its first line — flock, migrate, bind the socket, or degrade to client
        // mode — so it must exist before anything that reads from it. `KernelVitals` takes its
        // report source as a closure because a `@State` default cannot reference another
        // `@State` property, which is what forces both into this initialiser.
        let services = GMVibesServices()
        _services = State(initialValue: services)
        _vitals = State(initialValue: KernelVitals(report: { services.vitalsReport }))
        // The adaptor builds the delegate before `init` runs, so it cannot construct services
        // of its own. Its `applicationShouldTerminate` stops the kernel in order — flush the
        // dirty drafts, then close the database — on every termination path.
        appDelegate.services = services
    }

    /// Who holds the database, as the answering kernel reports it. The mapping lives on
    /// `GMVibesServices`, beside the connection model it reads.
    private var role: KernelRole { services.kernelRole }

    var body: some Scene {
        // THE MENU BAR IS DECLARED FIRST, BEFORE THE WindowGroup, AND THE ORDER IS
        // LOAD-BEARING: scene order decides whether SwiftUI opens a window at launch, and a
        // resident kernel must not pop one at every login.
        //
        // `INFOPLIST_KEY_LSUIElement = YES` governs the LAUNCH state only. The windows below
        // are ordinary app windows needing a Dock entry, a ⌘-Tab slot, a main menu and a
        // window manager willing to tile them, so `WindowPresence` raises the activation
        // policy while any window is open. Only the resident kernel is invisible.
        MenuBarExtra {
            KernelMenuBarContent(
                role: role,
                vitals: vitals,
                protocolVersion: services.protocolVersion,
                buildSha: services.buildSha,
                // BEFORE the open, not after: the window manager classifies a
                // window when it is created, and the per-window lease is taken
                // too late to affect the FIRST one. See WindowPresence.
                onNewWindow: {
                    WindowPresence.shared.prepareForWindow()
                    openWindow(value: WindowSeed())
                },
                // THE ONE PATH THAT ENDS THE KERNEL. `KernelMenuBarContent`
                // guards it behind a two-step confirmation, which is the whole
                // reason quitting lives here and not on ⌘Q: this process owns
                // the database for every hook and MCP session on the machine.
                // `applicationShouldTerminate` runs the ordered shutdown.
                onQuit: { NSApp.terminate(nil) },
                // Non-nil only when another APP COPY holds the store. The row
                // is absent rather than disabled when this is nil, which is
                // right for the writer (nothing to activate) and for a headless
                // holder (no window to raise).
                onActivateHolder: services.activateHolder
            )
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
            KernelTerminationCommands()
        }
    }

}

/// ⌘Q PUTS GM VIBES AWAY. IT DOES NOT END THE KERNEL.
///
/// While this process holds the database lock, a stock `NSApp.terminate` would tear the writer
/// out from under every hook and MCP session on the machine. `.appTermination` is REPLACED
/// rather than disabled, because an inert ⌘Q reads as a hung app: it closes every window, and
/// `WindowPresence` drops the activation policy on the last close so the Dock icon and ⌘-Tab
/// slot disappear as on a real quit. The kernel is stopped from ONE place, the menu bar's
/// two-step confirming quit. ⌘W keeps its stock meaning; do not rebind it here.
struct KernelTerminationCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button("Close All Windows") {
                // `canBecomeMain` FILTERS OUT THE MENU BAR PANEL. The
                // MenuBarExtra's window is an ordinary NSWindow in
                // `NSApp.windows`, and closing it tears down the status item —
                // the one thing that must survive this command.
                for window in NSApp.windows where window.isVisible && window.canBecomeMain {
                    window.performClose(nil)
                }
            }
            .keyboardShortcut("q", modifiers: .command)
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
