import SwiftUI

@main
struct GMVibesApp: App {
    // Bounded flush of dirty prompt edits on quit (replaces the old
    // synchronous main-thread write in onDisappear).
    @NSApplicationDelegateAdaptor(GMVibesAppDelegate.self) private var appDelegate
    @State private var services = GMVibesServices()

    var body: some Scene {
        // THE window type. Every window navigates the whole app via WindowNav;
        // WindowSeed's per-open UUID makes dedupe structurally impossible, and
        // its decoder always yields landing so restoration lands there too.
        WindowGroup("GM Vibes", for: WindowSeed.self) { $seed in
            GMVibesWindow(seed: seed ?? WindowSeed())
                .gmccEnv(services)
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
