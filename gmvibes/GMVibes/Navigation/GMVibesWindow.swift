import SwiftUI

/// The single window root. Every window can reach the whole app: a sliding
/// global rail on the left (collapsed by default) and a route-switched content
/// area. The session screen is a `NavigationSplitView`, so routes swap at the
/// root instead of pushing onto a `NavigationStack`.
struct GMVibesWindow: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(DaemonConnectionModel.self) private var daemon
    @Environment(GMCCEnvironment.self) private var gmcc
    @State private var nav: WindowNav
    // Above the `.id(nav.route)` boundary so the non-persisted diagram
    // workspaces survive in-window navigation (including the session
    // screen's own Search round-trip) and die with the window — the seam
    // DrawingsStore occupied before the Drawing/ tear-out.
    @State private var diagrams = DiagramWorkspaceStore()

    init(seed: WindowSeed) {
        _nav = State(initialValue: WindowNav(initial: seed.route))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sandbox stacks are visually indistinguishable from prod except
            // for this strip: GMCC_ROOT is set only by the sandbox launcher
            // (gm sandbox refresh), never in a normal launch.
            if let sandboxRoot = Self.sandboxRoot {
                SandboxBanner(root: sandboxRoot)
            }
            // The rail SLIDES OVER content (ZStack) rather than pushing it aside:
            // an HStack would add its 200pt to the content's own minWidth and
            // over-constrain a minimum-size window.
            ZStack(alignment: .leading) {
                content
                    // Recreate per route so each screen's toolbar/title declarations
                    // tear down cleanly on navigation.
                    .id(nav.route)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if nav.railOpen {
                    GlobalNavRail()
                        .shadow(radius: 8, x: 2)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy(duration: 0.18), value: nav.railOpen)
        .frame(minWidth: 760, minHeight: 480)
        // The shared app top bar, leading group — identical on every window.
        // Middle (title/subtitle) and trailing slot are declared per screen via
        // .navigationTitle/.navigationSubtitle and .toolbar(.primaryAction).
        // On the session route its `.navigation` placement puts it RIGHT of
        // the sidebar divider, next to the native collapse toggle — items in
        // the sidebar section would clip away when the sidebar closes.
        .toolbar {
            GlobalToolbarGroup(nav: nav, openWindow: openWindow)
        }
        .overlay {
            if nav.paletteOpen { CommandPalette() }
        }
        .focusedSceneValue(\.commandPalette) { nav.paletteOpen = true }
        // PATHS_GET loader at the window root (not Landing — instance-only
        // windows need it too). GMCCEnvironment's env fetch can't live in its
        // synchronous init; the probe seeds values there and the daemon's
        // typed roots overlay them here on every generation bump and on
        // CONFIG_SET (.paths). Coalescing is the env's own change-gate.
        .task(id: daemon.generation) {
            let paths = daemon.hub.stream(for: .paths)
            await gmcc.loadFromDaemon()   // single-flight — N windows, 1 RPC
            for await _ in paths {
                await gmcc.loadFromDaemon()
            }
        }
        // The SessionScopeCache lease, held by the WINDOW — above the
        // `.id(nav.route)` boundary, same altitude/reasoning as DrawingsStore.
        // Keyed on the session UUID (not the route), so hopping between
        // `.session` and `.sessionPrompt` on one session never restarts this
        // task: acquire/release never re-runs and the scope structurally
        // cannot retire mid-navigation (the grace list goes back to being an
        // optimization). `.task` is contractually balanced against view
        // lifetime, so the pair can't be broken.
        .task(id: nav.route?.sessionScopeUuid) {
            guard let uuid = nav.route?.sessionScopeUuid else { return }
            SessionScopeCache.shared.acquire(uuid)
            defer { SessionScopeCache.shared.release(uuid) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
            }
        }
        .environment(nav)
        .environment(diagrams)
    }

    /// Non-empty GMCC_ROOT == sandboxed. Read once: the env of a process
    /// never changes after launch.
    private static let sandboxRoot: String? = {
        guard let root = ProcessInfo.processInfo.environment["GMCC_ROOT"],
              !root.isEmpty else { return nil }
        return root
    }()

    @ViewBuilder
    private var content: some View {
        // Every arm mounts exactly ONE navigation container (ScreenScaffold,
        // declared here or inside the screen) so titlebar geometry — and the
        // `.navigation` placement of GlobalToolbarGroup — is identical on
        // every route. The trailing slot is each screen's to fill via
        // `.toolbar(placement: .primaryAction)`; empty renders empty.
        switch nav.route {
        case nil:
            ScreenScaffold { LandingView() }
        case .session(let windowID):
            SessionScreen(windowID: windowID)
        case .sessionPrompt(let windowID):
            SessionPromptScreen(windowID: windowID)
        case .diagram(let diagramID):
            DiagramScreen(windowID: diagramID)
        case .project(let projectUuid):
            ProjectScreen(projectUuid: projectUuid)
        case .instance(let instanceUuid):
            InstanceScreen(instanceUuid: instanceUuid)
        case .projects:
            ProjectsView()   // scaffold inside (owns the searchable binding)
        case .kbites:
            KBitesScene()    // scaffold inside (owns the KBiteStore)
        case .kbiteFile(let url):
            ScreenScaffold { KBiteMarkdownWindowView(url: url) }
        case .promptMemories(let windowID):
            ScreenScaffold { PromptMemoriesWindow(windowID: windowID) }
        case .search(let seed):
            ScreenScaffold { SearchScreen(seed: seed) }
        }
    }
}

/// The yellow "you are sandboxed" strip pinned above all window content.
/// Deliberately loud and always present — a sandboxed window must never be
/// mistakable for prod.
private struct SandboxBanner: View {
    let root: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox.fill")
            Text("SANDBOX")
                .fontWeight(.bold)
            Text(root)
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(0.75)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.black.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color.yellow)
    }
}

/// The app-wide top-bar group: Back · daemon status pill · rail toggle · new
/// window · ⌘K actions. Declared once, by GMVibesWindow, with `.navigation`
/// placement: on plain routes that's the bar's leading edge; on the session
/// route (NavigationSplitView) it pins the group RIGHT of the sidebar divider,
/// beside the native collapse toggle — never in the sidebar section, whose
/// items clip away when the sidebar closes. Dependencies are passed in rather
/// than read from @Environment so the struct stays host-agnostic.
struct GlobalToolbarGroup: ToolbarContent {
    let nav: WindowNav
    let openWindow: OpenWindowAction

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if nav.canGoBack {
                Button {
                    nav.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .help("Go back")
            }
            GmccDaemonStatus()
            Button {
                nav.railOpen.toggle()
            } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.leading")
            }
            .help("Toggle the global navigation sidebar")
            Button {
                openWindow(value: WindowSeed())
            } label: {
                Label("New Window", systemImage: "macwindow.badge.plus")
            }
            .help("Open a new GM Vibes window on the landing page")
            Button {
                nav.paletteOpen = true
            } label: {
                Label("Actions", systemImage: "command")
            }
            .help("App-wide actions (⌘K)")
        }
    }
}

