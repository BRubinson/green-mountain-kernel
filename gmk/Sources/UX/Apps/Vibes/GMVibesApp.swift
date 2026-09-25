import SwiftUI

/// THE ENTRY POINT of the one Mach-O. A personality resolved from argv runs
/// before any AppKit symbol is touched, so a CLI stays a plain process; only a
/// bare launch from inside the bundle — which is what LaunchServices does —
/// becomes the app, the only kernel host.
@main
enum GMVibesApp {

    /// The entry point that resolves personalities and launches the app.
    ///
    /// A personality resolved from argv runs before any AppKit symbol is
    /// touched, so a CLI stays a plain process; only a bare launch from inside
    /// the bundle becomes the app.
    static func main() {
        let arguments = CommandLine.arguments
        switch arguments.dropFirst().first {
        case "--version", "version":
            // So `.gm_version` is not the only thing that can answer "what is
            // actually installed here".
            FileHandle.standardOutput.write(Data("gm_kernel protocol v\(GmWireProtocol.version)\n".utf8))
            exit(0)
        case "--help", "-h", "help":
            FileHandle.standardOutput.write(Data(GmPersonality.usage.utf8))
            exit(0)
        default:
            break
        }
        if let (personality, argv) = GmPersonality.resolve(arguments) {
            personality.run(argv)
        }
        // The bundle is what says "app". LaunchServices passes no arguments, but
        // Xcode's debugger passes `-NSDocumentRevisionsDebugMode YES` and AppKit
        // accepts `-Key value` user-default pairs, so inside a bundle anything
        // that is not a personality is the app. A bare `gm_kernel` OUTSIDE a
        // bundle opens NOTHING: a typo must never become a process holding the database.
        if Bundle.main.bundleURL.pathExtension == "app" {
            MainActor.assumeIsolated { GMVibesScenes.main() }
            return
        }
        FileHandle.standardError.write(Data(GmPersonality.usage.utf8))
        exit(2)
    }
}

/// The app personality's scenes.
///
/// A separate type from the entry because a type that supplies its own `App.main()` cannot reach the stock launch.
private struct GMVibesScenes: App {
    // Bounded flush of dirty prompt edits on quit.
    @NSApplicationDelegateAdaptor(GMVibesAppDelegate.self) private var appDelegate
    @State private var services: GMVibesServices
    @State private var vitals: KernelVitals
    @Environment(\.openWindow) private var openWindow

    /// Initializes the app scenes with services and vitals.
    ///
    /// NO SECOND SAMPLER: `DaemonConnectionModel` samples the process vitals
    /// on one cadence, so the menu bar READS that rather than measuring on its
    /// own, and it can never disagree with the status pill. ORDER IS FIXED HERE AND
    /// MUST NOT BE TIDIED: `GMVibesServices()` ARBITRATES DATABASE OWNERSHIP on
    /// its first line — flock, migrate, bind the socket, or alert and quit when
    /// another app copy already holds it — so it must exist before anything that
    /// reads from it.
    init() {
        // ORDER IS FIXED HERE AND MUST NOT BE TIDIED. `GMVibesServices()` ARBITRATES DATABASE
        // OWNERSHIP on its first line — flock, migrate, bind the socket, or alert and quit when
        // another app copy already holds it — so it must exist before anything that reads from
        // it. `KernelVitals` takes its report source as a closure because a `@State` default
        // cannot reference another `@State` property, which is what forces both into this
        // initialiser.
        let services = GMVibesServices()
        _services = State(initialValue: services)
        _vitals = State(initialValue: KernelVitals(report: { services.vitalsReport }))
        // The adaptor builds the delegate before `init` runs, so it cannot construct services
        // of its own. Its `applicationShouldTerminate` stops the kernel in order — flush the
        // dirty drafts, then close the database — on every termination path.
        appDelegate.services = services
    }

    /// Who holds the database, as the answering kernel reports it.
    ///
    /// The mapping lives on `GMVibesServices`, beside the connection model it reads.
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
                onQuit: { NSApp.terminate(nil) }
            )
        } label: {
            // NO `.renderingMode(.original)` here — template rendering is the
            // point. It is what lets the status bar tint the glyph with the
            // rest of the row, in both appearances and while highlighted.
            Image(nsImage: KernelMenuBarIcon.image)
        }
        // `.window`, not the default `.menu`. AppKit's menu style renders only
        // menu items and would drop the role row's colour and layout — the one
        // thing that has to be unmissable, because the role row is how a user
        // learns the database failed to open, and a warning nobody can see is cosmetic.
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

/// ⌘Q PUTS GM VIBES AWAY.
///
/// IT DOES NOT END THE KERNEL. Stock `NSApp.terminate` tears the writer from hooks and MCP;
/// `.appTermination` is REPLACED (not disabled). Inert ⌘Q closes all windows; `WindowPresence`
/// drops activation on last close, Dock icon and ⌘-Tab disappear. Kernel stopped from ONE place:
/// menu bar's two-step quit. ⌘W keeps stock meaning.
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
