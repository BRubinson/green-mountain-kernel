import SwiftUI
import GMCCDaemonKit

/// KBites route host. KnowledgeBitesView is a TabView with a toolbar but no
/// navigation container of its own, so wrap it in the ScreenScaffold as the
/// title/toolbar host; the wrapper also owns the view-local KBiteStore.
struct KBitesScene: View {
    @State private var store = KBiteStore()

    var body: some View {
        ScreenScaffold {
            KnowledgeBitesView()
                .environment(store)
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}

struct KnowledgeBitesView: View {
    @Environment(GMCCEnvironment.self) private var gmcc
    @Environment(KBiteStore.self) private var store

    private enum KBiteTab: Hashable { case open, digested, search }

    @State private var selectedTab: KBiteTab = .digested

    var body: some View {
        TabView(selection: $selectedTab) {
            KBitesPaneView(root: .open)
                .tabItem { Label("Open", systemImage: "tray") }
                .tag(KBiteTab.open)

            KBitesPaneView(root: .digested)
                .tabItem { Label("Digested", systemImage: "books.vertical") }
                .tag(KBiteTab.digested)

            // Search-first discovery over db-digested kbite content (FTS5,
            // bm25-ranked). Filesystem browsing stays on the other tabs; content
            // digested to the db from now on exists ONLY here.
            KBiteSearchPane()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(KBiteTab.search)
        }
        .navigationTitle("Knowledge Bites")
        .toolbar {
            ToolbarItem {
                Button {
                    if let url = rootFolderURL { VSCode.open(url) }
                } label: {
                    Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .disabled(rootFolderURL == nil)
                .help("Open this kbites folder (in the ckfs) in VS Code")
            }
            ToolbarItem {
                Button {
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // The ckfs folder backing the current tab (open / digested kbites root).
    private var rootFolderURL: URL? {
        let key: GMCCEnvKey
        switch selectedTab {
        case .open: key = KBiteRoot.open.envKey
        case .digested, .search: key = KBiteRoot.digested.envKey
        }
        guard let path = gmcc[key], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

// MARK: - Daemon search pane (KBITE_SEARCH → KBITE_FILE_GET)

private struct KBiteSearchPane: View {
    @State private var query = ""
    @State private var hits: [KbiteSearchHit] = []
    @State private var searched = false
    @State private var selectedFileUuid: String?
    @State private var fileContent: String?
    @State private var fileName: String?
    @State private var fileError: String?
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("Search digested kbite content…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)
                    .onChange(of: query) { _, _ in scheduleSearch() }
                Divider()
                hitList
            }
            .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)

            reader
                .frame(minWidth: 360)
        }
    }

    @ViewBuilder
    private var hitList: some View {
        if let errorText {
            ContentUnavailableView("Search Unavailable", systemImage: "bolt.slash",
                                   description: Text(errorText))
        } else if hits.isEmpty {
            ContentUnavailableView(
                searched ? "No Matches" : "Search KBites",
                systemImage: "magnifyingglass",
                description: Text(searched
                    ? "No db-digested content matched. Kbites digested before the migration are browsable in the Digested tab."
                    : "FTS5 search over kbite content digested into the GMCC database.")
            )
        } else {
            List(hits, id: \.fileUuid, selection: $selectedFileUuid) { hit in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(hit.kbiteCode)
                            .font(.caption.weight(.semibold).monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: .capsule)
                        Text(hit.fileName).font(.callout.weight(.medium)).lineLimit(1)
                    }
                    if !hit.fileSummary.isEmpty {
                        Text(hit.fileSummary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if !hit.matchedKeywords.isEmpty {
                        Text(hit.matchedKeywords.joined(separator: " · "))
                            .font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                .tag(hit.fileUuid)
            }
            .listStyle(.sidebar)
            .onChange(of: selectedFileUuid) { _, uuid in
                guard let uuid else { return }
                loadFile(uuid)
            }
        }
    }

    @ViewBuilder
    private var reader: some View {
        if let fileError {
            ContentUnavailableView {
                Label("File Unavailable", systemImage: "bolt.slash")
            } description: {
                Text(fileError)
            } actions: {
                Button("Retry") {
                    if let uuid = selectedFileUuid { loadFile(uuid) }
                }
                .buttonStyle(.bordered)
            }
        } else if let content = fileContent {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let fileName {
                        Text(fileName).font(.headline).padding(.bottom, 4)
                    }
                    MarkdownBlocksView(MarkdownDocument.parse(content))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        } else if selectedFileUuid != nil {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Search, then select a hit to read it.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            searched = false
            errorText = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let result = try await GMCCDaemonService.shared.searchKbites(query: trimmed, limit: 40)
                guard !Task.isCancelled else { return }
                hits = result
                searched = true
                errorText = nil
            } catch let error as DaemonError {
                hits = []   // never leave stale results behind an error view
                if case .unreachable(let m) = error { errorText = m }
                else if case .notInstalled = error { errorText = "Daemon not installed" }
                else { errorText = String(describing: error) }
            } catch {
                hits = []
                errorText = String(describing: error)
            }
        }
    }

    private func loadFile(_ uuid: String) {
        fileContent = nil
        fileName = nil
        fileError = nil
        Task {
            do {
                let file = try await GMCCDaemonService.shared.getKbiteFile(fileUuid: uuid)
                guard selectedFileUuid == uuid else { return }
                fileName = file.resourceFileName
                fileContent = file.resourceFileContent ?? "*Binary file — content stored on the filesystem.*"
            } catch {
                guard selectedFileUuid == uuid else { return }
                fileError = String(describing: error)
            }
        }
    }
}

private struct KBitesPaneView: View {
    let root: KBiteRoot

    @Environment(GMCCEnvironment.self) private var gmcc
    @Environment(KBiteStore.self) private var store

    @State private var selectedFile: URL?

    var body: some View {
        let kbites = store.kbites(in: root, gmcc: gmcc)

        if kbites.isEmpty {
            emptyState
        } else {
            HSplitView {
                KBiteAccordionSidebar(kbites: kbites, selection: $selectedFile)
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 460)

                if let file = selectedFile, isPreviewableFile(file) {
                    KBiteMarkdownView(url: file)
                        .frame(minWidth: 360)
                } else {
                    Text("Select a kbite, then click a file to preview.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minWidth: 360)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        guard let path = gmcc[root.envKey] else {
            return "\(root.envKey.rawValue) couldn't be resolved from the daemon or a conventional location."
        }
        return "No kbites at\n\(path)"
    }

    private func isPreviewableFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return !isDir.boolValue
    }
}

private struct KBiteAccordionSidebar: View {
    let kbites: [KBiteEntry]
    @Binding var selection: URL?

    @State private var expandedURL: URL?
    @State private var loadedNodes: [URL: KBiteFileNode] = [:]

    var body: some View {
        List(selection: $selection) {
            ForEach(kbites) { kbite in
                kbiteSection(kbite)
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            if expandedURL == nil, let first = kbites.first {
                expand(first.url)
            }
        }
    }

    @ViewBuilder
    private func kbiteSection(_ kbite: KBiteEntry) -> some View {
        DisclosureGroup(isExpanded: bindingFor(kbite.url)) {
            if let node = loadedNodes[kbite.url] {
                OutlineGroup(node.children ?? [], children: \.children) { child in
                    fileRow(child)
                        .tag(child.url as URL?)
                }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label(kbite.name, systemImage: "shippingbox.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = kbite.url
                    if expandedURL == kbite.url {
                        expandedURL = nil
                    } else {
                        expand(kbite.url)
                    }
                }
        }
        .tag(kbite.url as URL?)
    }

    @ViewBuilder
    private func fileRow(_ node: KBiteFileNode) -> some View {
        if node.isDirectory {
            Label(node.name, systemImage: "folder.fill")
                .foregroundStyle(.secondary)
        } else {
            let isMarkdown = node.url.pathExtension.lowercased() == "md"
            Label {
                Text(node.name)
                    .fontWeight(isMarkdown ? .medium : .regular)
            } icon: {
                Image(systemName: isMarkdown ? "doc.text.fill" : "doc")
                    .foregroundStyle(isMarkdown ? Color.accentColor : .secondary)
            }
            .contextMenu {
                OpenInWindowButton(url: node.url)
            }
        }
    }

    private func bindingFor(_ url: URL) -> Binding<Bool> {
        Binding(
            get: { expandedURL == url },
            set: { isOpen in
                if isOpen {
                    expand(url)
                } else if expandedURL == url {
                    expandedURL = nil
                }
            }
        )
    }

    private func expand(_ url: URL) {
        expandedURL = url
        if loadedNodes[url] == nil {
            loadedNodes[url] = KBiteFileNode.load(from: url)
        }
    }
}

private struct OpenInWindowButton: View {
    let url: URL
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(value: WindowSeed(.kbiteFile(url)))
        } label: {
            Label("Open in Window", systemImage: "macwindow.badge.plus")
        }
    }
}
