import GmDaemonSdk
import GmVibesCore
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
        // ORDER IS FIXED HERE AND MUST NOT BE TIDIED. `GMVibesServices()`
        // ARBITRATES DATABASE OWNERSHIP on its first line — takes the flock,
        // migrates, binds the socket, or degrades to client mode — so it has to
        // exist before anything that reads from it. `KernelVitals` takes its
        // report source as a closure precisely because a `@State` default cannot
        // reference another `@State` property, which is what forces both into
        // this initialiser rather than into property defaults.
        let services = GMVibesServices()
        _services = State(initialValue: services)
        _vitals = State(initialValue: KernelVitals(report: { services.vitalsReport }))
        // The delegate is built by the adaptor before `init` runs, so it cannot
        // construct services of its own. Hand it the one we just made: its
        // `applicationShouldTerminate` is what stops the kernel in order —
        // flush the dirty drafts, then close the database — on every
        // termination path, including the ones no menu item passes through.
        appDelegate.services = services
    }

    /// Who holds the database, as the answering kernel reports it.
    ///
    /// The mapping lives on `GMVibesServices` in `GmVibesCore`, beside the
    /// connection model it reads — see the facade note there for why the app
    /// target is handed four scalars rather than the model itself.
    private var role: KernelRole { services.kernelRole }

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
                onActivateHolder: services.activateHolder)
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
/// Once this process holds the database lock, the stock `NSApp.terminate` on ⌘Q
/// would tear the writer out from under every hook and every MCP session on the
/// machine — from a keystroke people press in a text editor without thinking.
/// So `.appTermination` is replaced.
///
/// Replaced rather than merely disabled: an inert ⌘Q reads as a hung app, and
/// the muscle memory has to land somewhere sensible. Closing every window is
/// what "quit" means to the person pressing it — `WindowPresence` drops the
/// activation policy back to `.accessory` on the last close, so the Dock icon
/// and the ⌘-Tab slot disappear exactly as they would on a real quit. What
/// survives is the menu bar item and the kernel behind it.
///
/// The kernel is stopped from ONE place: the menu bar's two-step confirming
/// quit. That asymmetry is deliberate. Ending the writer should cost a
/// deliberate gesture; putting the windows away should cost ⌘Q.
///
/// ⌘W keeps its stock meaning through the standard Close item — do not rebind
/// it here.
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
