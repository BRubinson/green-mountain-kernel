import SwiftUI
import AppKit
import GMCCDaemonKit

/// The ONE dope surface, mounted at both levels: the session view's dope tab
/// (`promptUuid: nil` — SESSION_BASE) and the prompt editor's phase card
/// (`promptUuid` set — PROMPT scope preferred, SESSION_BASE fallback with a
/// visible `resolvedVia` chip). Read-only tree render + a never-writing
/// Read Repo validation + the one Init write behind a validated sheet.
struct DopePane: View {
    @Environment(DaemonConnectionModel.self) private var daemon
    let scope: SessionScope
    let promptUuid: String?
    /// false when embedded in an already-scrolling host (the editor's phase
    /// card) — nested ScrollViews collapse to zero height there.
    var scrollable = true
    /// Session-scope hosts (the session tab) pass a navigator to the
    /// full-window Doped Viewer; the callback receives the LOADED scope's
    /// code (the diagram workspace is keyed by it). nil hides the button —
    /// prompt phase cards don't offer the viewer. Passed in rather than read
    /// from @Environment so the pane stays host-agnostic
    /// (GlobalToolbarGroup's convention).
    var onOpenDiagram: ((String) -> Void)? = nil

    @State private var showInit = false
    @State private var searchText = ""
    @State private var expansion = DopeExpansion()
    /// View state ONLY — base domains are hidden by default on every mount and
    /// nothing is ever written back to the daemon.
    @State private var showBaseDomains = false

    private var store: DopeStore { scope.dope }
    /// Stable, code-agnostic identity of this surface — what observation and
    /// candidate lists are keyed by.
    private var target: DopeStore.Key { .init(promptUuid: promptUuid) }
    /// The key being rendered right now (target + the resolved scope pin).
    private var key: DopeStore.Key { store.key(for: promptUuid) }

    private var promptRows: [DopeScopeRow] { store.promptCandidates(target) }
    /// A PROMPT scope and a SESSION_BASE scope may legitimately share a code;
    /// DOPE_GET resolves prompt-first, so the session row is unreachable by
    /// code — and a duplicate Picker tag breaks selection. Drop it.
    private var sessionRows: [DopeScopeRow] {
        store.sessionCandidates(target)
            .filter { row in !promptRows.contains { $0.code == row.code } }
    }
    private var knownCodes: [String] { (promptRows + sessionRows).map(\.code) }
    private var showsPicker: Bool { knownCodes.count > 1 }

    var body: some View {
        Group {
            switch store.phase(key) {
            case .idle:
                ProgressView().controlSize(.regular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .absent:
                // The NORMAL pre-init state — an empty state with the Init
                // affordance, never an error banner.
                ContentUnavailableView {
                    Label("No Dope Yet", systemImage: "cube.transparent")
                } description: {
                    VStack(spacing: 6) {
                        Text(promptUuid == nil
                            ? "This session has no dope scope. Initialize one to start modeling."
                            : "Neither this prompt nor the session has a dope scope yet.")
                        if !knownCodes.isEmpty {
                            // Reached when a pinned code no longer resolves —
                            // name the codes that DO exist, not a blank.
                            Text("Known scope codes: \(knownCodes.joined(separator: ", "))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                } actions: {
                    if showsPicker { scopePicker }
                    Button("Initialize Dope Scope…") { showInit = true }
                        .buttonStyle(.borderedProminent)
                }
            case .needsCode(let daemonMessage):
                // The daemon-side backstop: the store normally pins a
                // candidate from DOPE_LIST before the read, so this is
                // reached only when enumeration failed. Offer the picker if
                // we have rows at all; else the daemon's message names them.
                ContentUnavailableView {
                    Label("Several Dope Scopes", systemImage: "square.stack.3d.up.trianglebadge.exclamationmark")
                } description: {
                    Text(showsPicker
                        ? "More than one dope scope matches. Choose which to open."
                        : daemonMessage)
                } actions: {
                    if showsPicker { scopePicker }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Dope Unavailable", systemImage: "bolt.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await store.load(key) } }
                        .buttonStyle(.bordered)
                }
            case .loaded(let response):
                loadedContent(response)
            }
        }
        .sheet(isPresented: $showInit) {
            DopeInitSheet(store: store, key: target, forPrompt: promptUuid != nil,
                          siblingCodes: knownCodes,
                          sameTypeCodes: (promptUuid == nil
                              ? store.sessionCandidates(target)
                              : promptRows).map(\.code))
        }
        // Event-driven refresh on the dedicated dope domain (NOT .session —
        // see the DOPE_CHANGE arm). Stream hoisted before the first load so a
        // write landing mid-load isn't lost; a bot's tree-build burst
        // coalesces through the trailing debounce + newest-1 buffering.
        // begin/endObserving bound reloadLive's fan-out to MOUNTED surfaces
        // (`.task` is contractually balanced, so the pair can't be broken).
        .task(id: daemon.generation) {
            store.beginObserving(target)
            defer { store.endObserving(target) }
            let stream = daemon.hub.stream(for: .dope(store.sessionUuid))
            await store.refresh(promptUuid: promptUuid)
            for await _ in stream {
                try? await Task.sleep(for: .milliseconds(300))
                await store.reloadLive()
            }
        }
    }

    /// Menu-style picker over the target's candidates. Plain `Picker` rather
    /// than the DesignSystem `SegmentedPicker`: scope-code counts are
    /// unbounded (segments don't scale) and `DopeScopeRow` isn't
    /// `Identifiable` — `ForEach(id: \.uuid)` avoids touching kit
    /// sources. The `Automatic` tag restores daemon-side resolution.
    @ViewBuilder
    private var scopePicker: some View {
        Picker("Dope scope", selection: Binding(
            get: { store.selectedCodes[target] },
            set: { newValue in Task { await store.select(newValue, for: target) } }
        )) {
            Text(promptUuid == nil ? "Automatic" : "Automatic (prompt → session base)")
                .tag(String?.none)
            if !promptRows.isEmpty {
                Section("Prompt scopes") {
                    ForEach(promptRows, id: \.uuid) { row in
                        Text("\(row.code) · rev \(row.revision)").tag(Optional(row.code))
                    }
                }
            }
            if !sessionRows.isEmpty {
                Section(promptUuid == nil ? "Session scopes" : "Session base (fallback)") {
                    ForEach(sessionRows, id: \.uuid) { row in
                        Text("\(row.code) · rev \(row.revision)").tag(Optional(row.code))
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 260)
        .help("Choose which dope scope this surface renders")
    }

    @ViewBuilder
    private func loadedContent(_ response: DopeGetResponse) -> some View {
        if scrollable {
            ScrollView {
                loadedStack(response)
                    .padding(16)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        } else {
            loadedStack(response)
        }
    }

    private func loadedStack(_ response: DopeGetResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(response)
            if let issue = store.repoIssues[key] {
                repoBanner(color: .red, icon: "xmark.octagon.fill", lines: ["Read repo failed: \(issue)"])
            } else if let read = store.repoReads[key] {
                repoResult(read)
            }
            if !response.tree.domains.isEmpty {
                treeControls
            }
            DopeTreeView(tree: response.tree, query: trimmedQuery, expansion: expansion,
                         showBaseDomains: showBaseDomains)
        }
    }

    private func header(_ response: DopeGetResponse) -> some View {
        HStack(spacing: 10) {
            Label(response.tree.body.name, systemImage: "cube.transparent")
                .font(.headline)
            Text(response.tree.body.code)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            // The fallback must never be invisible: which scope answered.
            Text(response.resolvedVia == "prompt" ? "prompt scope" : "session base")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.15), in: .capsule)
            Text("rev \(response.tree.revision)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            if showsPicker { scopePicker }
            Spacer()
            if promptUuid != nil, response.resolvedVia != "prompt" {
                // The fallback answered — offer a real prompt scope. This is
                // the reachable path for the sibling-code hints: the sheet
                // opens with the session-base codes visible for alignment.
                Button("Initialize Prompt Scope…") { showInit = true }
                    .help("Create a PROMPT-typed dope scope for this prompt (currently rendering the session-base fallback)")
            }
            if let onOpenDiagram, promptUuid == nil {
                Button {
                    onOpenDiagram(response.tree.body.code)
                } label: {
                    Label("Diagram", systemImage: "rectangle.3.group")
                }
                .help("Open this dope scope as an interactive diagram (non-persisted)")
            }
            Button {
                Task { await store.readRepo(key) }
            } label: {
                Label("Read Repo", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(store.repoBusy.contains(key))
            .help("Parse and validate the on-disk dope tree — reads only, never writes")
        }
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// Search over entity/field (and enum/option) names + codes, plus
    /// expand/collapse-all. While a search is active the tree force-expands
    /// to keep matches visible, so the broadcast buttons are disabled.
    private var treeControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search entities & fields", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 7))
            .frame(maxWidth: 340)
            // Authoritative over search: a query matching only base-domain
            // content never force-reveals — this button is the ONLY door.
            Button {
                showBaseDomains.toggle()
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .symbolVariant(showBaseDomains ? .fill : .none)
            }
            .buttonStyle(.bordered)
            .tint(showBaseDomains ? .accentColor : nil)
            .help(showBaseDomains
                ? "Hide base composable domains"
                : "Show base composable domains (hidden by default; view state only)")
            Button {
                expansion.broadcast(expanded: true)
            } label: {
                Label("Expand All", systemImage: "chevron.down.square")
            }
            .disabled(!trimmedQuery.isEmpty)
            .help("Expand every domain, entity, and enum")
            Button {
                expansion.broadcast(expanded: false)
            } label: {
                Label("Collapse All", systemImage: "chevron.right.square")
            }
            .disabled(!trimmedQuery.isEmpty)
            .help("Collapse every domain, entity, and enum")
            Spacer()
        }
    }

    @ViewBuilder
    private func repoResult(_ read: DopeReadRepoResponse) -> some View {
        let drifted = read.drift == true
        var lines: [String] {
            var out = [drifted
                ? "Repo drift: on-disk rev \(read.onDiskRevision) vs db rev \(read.dbRevision.map(String.init) ?? "—")."
                : "Repo in sync — on-disk rev \(read.onDiskRevision)."]
            out.append(contentsOf: read.warnings)
            return out
        }
        repoBanner(
            color: drifted || !read.warnings.isEmpty ? .orange : .green,
            icon: drifted ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
            lines: lines
        )
    }

    private func repoBanner(color: Color, icon: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { item in
                HStack(spacing: 8) {
                    if item.offset == 0 {
                        Image(systemName: icon).foregroundStyle(color)
                    } else {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Text(item.element).font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}

// MARK: - Read-only tree render

/// Expand/collapse-all broadcast: bumping `generation` makes every disclosure
/// row adopt `expanded` via `onChange`, after which rows toggle independently
/// again. Value-typed so it rides plain SwiftUI state — no shared model.
struct DopeExpansion: Equatable {
    private(set) var generation = 0
    private(set) var expanded = true

    mutating func broadcast(expanded: Bool) {
        generation += 1
        self.expanded = expanded
    }
}

/// Case-insensitive match over the names + codes dope surfaces to the user.
private func dopeMatches(_ query: String, _ candidates: String...) -> Bool {
    candidates.contains { $0.localizedCaseInsensitiveContains(query) }
}

private func entityMatches(_ entity: DopeEntityNode, _ query: String) -> Bool {
    dopeMatches(query, entity.body.name, entity.body.code)
        || entity.properties.contains { dopeMatches(query, $0.body.name, $0.body.code) }
}

private func enumMatches(_ enumNode: DopeEnumNode, _ query: String) -> Bool {
    dopeMatches(query, enumNode.body.name, enumNode.body.code)
        || enumNode.options.contains { dopeMatches(query, $0.body.name, $0.body.code) }
}

/// Plain nested disclosure render of the six-level tree:
/// scope → domain → { entity → property, enum → option }.
struct DopeTreeView: View {
    let tree: DopeScopeTree
    var query = ""
    var expansion = DopeExpansion()
    var showBaseDomains = false
    /// Only the REF is held; it is re-resolved against the CURRENT catalog on
    /// every present, so a live reload updates the open dialog instead of
    /// stranding a snapshot.
    @State private var inspection: EnumInspection?

    private struct EnumInspection: Identifiable, Hashable {
        let ref: String
        let originPropertyUuid: String?
        var id: String { ref }
    }

    private var visibleDomains: [DopePersistenceNode] {
        guard !query.isEmpty else { return tree.domains }
        return tree.domains.filter { domain in
            dopeMatches(query, domain.body.name, domain.body.code)
                || domain.entities.contains { entityMatches($0, query) }
                || domain.enums.contains { enumMatches($0, query) }
        }
    }

    /// Base domains are a separate class rendered ABOVE the model domains and
    /// hidden unless the toggle is on. The toggle is authoritative: the search
    /// filter runs within each partition and never force-reveals base content,
    /// so `renderedDomains` — not `visibleDomains` — drives the empty state.
    private var renderedDomains: [(domain: DopePersistenceNode, isBase: Bool)] {
        let base = showBaseDomains
            ? visibleDomains.filter(DopeBaseCatalog.isBaseDomain) : []
        let model = visibleDomains.filter { !DopeBaseCatalog.isBaseDomain($0) }
        return base.map { ($0, true) } + model.map { ($0, false) }
    }

    var body: some View {
        let catalog = DopeEnumCatalog(tree: tree)
        let baseCatalog = DopeBaseCatalog(tree: tree)
        let inspector = DopeEnumInspector(catalog: catalog) { ref, origin in
            inspection = EnumInspection(ref: ref, originPropertyUuid: origin)
        }
        Group {
            if tree.domains.isEmpty {
                Label("No domains yet — the bot models dope via the gm CLI.",
                      systemImage: "hourglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if renderedDomains.isEmpty {
                Label(query.isEmpty
                        ? "Only base domains here — reveal them with the layers toggle."
                        : "Nothing matches “\(query)”.",
                      systemImage: query.isEmpty ? "square.3.layers.3d" : "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(renderedDomains, id: \.domain.identity.uuid) { item in
                        DomainCard(domain: item.domain, isBase: item.isBase,
                                   query: query, expansion: expansion,
                                   inspector: inspector, baseCatalog: baseCatalog)
                    }
                }
            }
        }
        .sheet(item: $inspection) { selection in
            if let resolved = catalog.resolved(selection.ref) {
                DopeEnumSheet(info: resolved,
                              originPropertyUuid: selection.originPropertyUuid)
            } else {
                DopeEnumMissingSheet(ref: selection.ref)
            }
        }
    }
}

private struct DomainCard: View {
    let domain: DopePersistenceNode
    let isBase: Bool
    let query: String
    let expansion: DopeExpansion
    let inspector: DopeEnumInspector
    let baseCatalog: DopeBaseCatalog
    @State private var expanded = true

    /// A hit on the domain itself keeps all children; otherwise only matching
    /// branches survive (a matched entity still shows all its properties —
    /// that narrowing happens inside EntityRow on property-only hits).
    private var domainHit: Bool {
        query.isEmpty || dopeMatches(query, domain.body.name, domain.body.code)
    }
    private var visibleEntities: [DopeEntityNode] {
        domainHit ? domain.entities : domain.entities.filter { entityMatches($0, query) }
    }
    private var visibleEnums: [DopeEnumNode] {
        domainHit ? domain.enums : domain.enums.filter { enumMatches($0, query) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: query.isEmpty ? $expanded : .constant(true)) {
            VStack(alignment: .leading, spacing: 8) {
                if !domain.body.description.isEmpty {
                    Text(domain.body.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(visibleEntities, id: \.identity.uuid) { entity in
                    EntityRow(entity: entity, domainCode: domain.body.code,
                              query: query,
                              expansion: expansion, inspector: inspector,
                              baseCatalog: baseCatalog)
                }
                ForEach(visibleEnums, id: \.identity.uuid) { enumNode in
                    EnumRow(enumNode: enumNode, query: query, expansion: expansion)
                }
                if domain.entities.isEmpty && domain.enums.isEmpty {
                    Text("Empty domain.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Label(domain.body.name, systemImage: "square.grid.2x2")
                    .font(.subheadline.weight(.semibold))
                Text(domain.body.code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                if isBase {
                    Text("base")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.15), in: .capsule)
                }
                Spacer()
                Text("\(domain.entities.count) entities · \(domain.enums.count) enums")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 10))
        .onChange(of: expansion) { _, command in
            expanded = command.expanded
        }
    }
}

private struct EntityRow: View {
    let entity: DopeEntityNode
    /// The owning domain's code — held only so this row can format the
    /// `domain.entity` dot-path it copies (the node itself doesn't carry it).
    let domainCode: String
    let query: String
    let expansion: DopeExpansion
    let inspector: DopeEnumInspector
    let baseCatalog: DopeBaseCatalog
    @State private var expanded = false
    /// View state ONLY — the single per-entity reveal for base material
    /// (criterion D); resets per mount like everything else here.
    @State private var revealBaseFields = false

    /// Property-only hits narrow the child list; a hit on the entity itself
    /// (or no query) keeps every property.
    private var visibleProperties: [DopePropertyNode] {
        if query.isEmpty || dopeMatches(query, entity.body.name, entity.body.code) {
            return entity.properties
        }
        return entity.properties.filter { dopeMatches(query, $0.body.name, $0.body.code) }
    }

    /// Default render hides the materialized (base_origin_ref-tagged) rows;
    /// the reveal unions them back in, origin-marked.
    private var renderedProperties: [DopePropertyNode] {
        visibleProperties.filter { revealBaseFields || $0.body.baseOriginRef == nil }
    }

    /// Inherited (non-materialized) base fields, shadow-deduped by the
    /// catalog. Only computed when revealed — never synthesized by default.
    private var inheritedProperties: [DopeBaseCatalog.InheritedProperty] {
        revealBaseFields ? baseCatalog.inheritedProperties(for: entity) : []
    }

    private var hasBaseMaterial: Bool {
        entity.body.baseComposableRef != nil
            || entity.properties.contains { $0.body.baseOriginRef != nil }
    }

    /// `domain.entity` — the same greppable dot-path the daemon writes into
    /// `.doped.json` (kit formatter, never string-built here).
    private var entityRef: String {
        DopeCode.formatEntityRef(domain: domainCode, entity: entity.body.code)
    }

    private func propertyRef(_ property: DopePropertyNode) -> String {
        DopeCode.formatPropertyRef(domain: domainCode, entity: entity.body.code,
                                   property: property.body.code)
    }

    var body: some View {
        DisclosureGroup(isExpanded: query.isEmpty ? $expanded : .constant(true)) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(renderedProperties, id: \.identity.uuid) { property in
                    if let origin = property.body.baseOriginRef {
                        PropertyRow(property: property, inspector: inspector,
                                    ref: propertyRef(property),
                                    mode: .materialized(origin: origin))
                    } else {
                        PropertyRow(property: property, inspector: inspector,
                                    ref: propertyRef(property))
                    }
                }
                ForEach(inheritedProperties) { inherited in
                    // An inherited row is synthetic here — the field is
                    // declared on the base entity, so the ORIGIN path is the
                    // one that actually resolves.
                    PropertyRow(property: inherited.node, inspector: inspector,
                                ref: inherited.originRef,
                                mode: .inherited(origin: inherited.originRef))
                }
                if entity.properties.isEmpty && inheritedProperties.isEmpty {
                    Text("No properties.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if hasBaseMaterial {
                    Button {
                        revealBaseFields.toggle()
                    } label: {
                        Label(revealBaseFields ? "Hide base fields" : "Show base fields",
                              systemImage: revealBaseFields ? "eye.slash" : "eye")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .help("Base-composable fields: materialized rows tagged with their origin, inherited rows shown dimmed")
                }
            }
            .padding(.top, 4)
            .padding(.leading, 4)
        } label: {
            HStack(spacing: 6) {
                // Table name FIRST: `entity.body.code` IS the table name
                // (dope_persistence_entity is the table level — dope_persistence
                // above it is the domain grouping). The display name trails it
                // as secondary prose.
                Label(entity.body.code, systemImage: "tablecells")
                    .font(.callout.monospaced())
                Text(entity.body.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entity.body.entityType)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
                // Criterion C: the literal ref path, text only — the base's
                // properties are NEVER resolved into this entity's list.
                if let baseRef = entity.body.baseComposableRef {
                    Text(baseRef)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entity.properties.count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                DopeCopyButton(ref: entityRef)
            }
            // The chevron still owns expand/collapse; a click anywhere on the
            // label copies instead of toggling.
            .contentShape(.rect)
            .onTapGesture { copyDopeRef(entityRef) }
            .help("Click to copy \(entityRef)")
        }
        .onChange(of: expansion) { _, command in
            expanded = command.expanded
        }
    }
}

private struct PropertyRow: View {
    /// How this row relates to the base-composable machinery: a plain local
    /// row, a materialized local row (real, FK-referenceable, tagged with the
    /// base property it originates from), or an inherited base row synthesized
    /// into the list only while the entity's reveal is on.
    enum Mode: Equatable {
        case local
        case materialized(origin: String)
        case inherited(origin: String)
    }

    let property: DopePropertyNode
    let inspector: DopeEnumInspector
    /// `domain.entity.property` — the dot-path this row copies. Inherited rows
    /// are handed their ORIGIN path: the field is declared on the base entity
    /// and does not resolve under the hosting entity's code.
    let ref: String
    var mode: Mode = .local
    @State private var hovering = false

    /// Non-nil only for an enum property whose ref RESOLVES in this tree.
    private var enumNode: DopeEnumNode? {
        property.body.enumRef.flatMap { inspector.catalog.node(for: $0) }
    }

    var body: some View {
        HStack(spacing: 6) {
            // The row body is the copy target; enum inspection lives on the
            // enum chip inside it so both actions stay reachable.
            row(enumNode: enumNode)
                .onTapGesture { copyDopeRef(ref) }
                .help("Click to copy \(ref)")
            DopeCopyButton(ref: ref)
        }
        .onHover { hovering = $0 }
    }

    private func row(enumNode: DopeEnumNode?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(.tertiary)
            // Column name FIRST, and only the property's OWN code — never a
            // dot-path. The display name trails it as secondary prose.
            Text(property.body.code).font(.callout.monospaced())
            Text(property.body.name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(property.body.dataType)
                .font(.caption.monospaced())
                .foregroundStyle(.blue)
            if !property.body.nullable {
                Text("required").font(.caption2).foregroundStyle(.orange)
            }
            if property.body.isUnique {
                Text("unique").font(.caption2).foregroundStyle(.purple)
            }
            if let enumRef = property.body.enumRef {
                if let enumNode {
                    Button {
                        inspector.inspect(enumRef, property.identity.uuid)
                    } label: {
                        HStack(spacing: 6) {
                            Text("→ \(enumRef)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                            if !enumNode.options.isEmpty {
                                DopeEnumBadgeStrip(options: enumNode.options)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Inspect \(enumNode.body.name) — its options and every property using it")
                } else {
                    // Dangling ref: text only, exactly as before.
                    Text("→ \(enumRef)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            if let related = property.body.relationshipTargetRef {
                Text("→ \(related)").font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            switch mode {
            case .local:
                EmptyView()
            case .materialized(let origin):
                Text("⊙ \(origin)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.teal)
                    .help("Materialized from base property \(origin)")
            case .inherited(let origin):
                Text("inherited")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(origin)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        // Inherited rows are synthetic — the field lives on the base entity —
        // so the whole row dims to keep the effective shape legible without
        // reading as local schema.
        .opacity({ if case .inherited = mode { 0.55 } else { 1 } }())
        // Replaces the old trailing `Spacer()`: identical left-packed result,
        // but a Spacer is fully flexible and would compete with the badge
        // strip for the row's leftover width, starving it of badges.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .background(alignment: .center) {
            if hovering {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.quaternary.opacity(0.4))
                    .padding(.horizontal, -6)   // grows past the row's bounds
                    .padding(.vertical, -2)     // so row metrics are unchanged
            }
        }
    }
}

/// Copies `ref` to the general pasteboard. The one write this read-only
/// surface performs — nothing daemon-side is touched.
@MainActor
private func copyDopeRef(_ ref: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(ref, forType: .string)
}

/// Trailing copy affordance on entity + property rows: copies the dot-path and
/// flashes a checkmark so the copy is visibly acknowledged. View state only.
private struct DopeCopyButton: View {
    let ref: String
    @State private var copied = false

    var body: some View {
        Button {
            copyDopeRef(ref)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .frame(width: 16, height: 14)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Copy \(ref)")
    }
}

private struct EnumRow: View {
    let enumNode: DopeEnumNode
    let query: String
    let expansion: DopeExpansion
    @State private var expanded = false

    /// Option-only hits narrow the child list; a hit on the enum itself
    /// (or no query) keeps every option.
    private var visibleOptions: [DopeOptionNode] {
        if query.isEmpty || dopeMatches(query, enumNode.body.name, enumNode.body.code) {
            return enumNode.options
        }
        return enumNode.options.filter { dopeMatches(query, $0.body.name, $0.body.code) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: query.isEmpty ? $expanded : .constant(true)) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(visibleOptions, id: \.identity.uuid) { option in
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(.tertiary)
                        Text(option.body.name).font(.callout)
                        Text(option.body.code)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
                if enumNode.options.isEmpty {
                    Text("No options.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 4)
            .padding(.leading, 4)
        } label: {
            HStack(spacing: 6) {
                Label(enumNode.body.name, systemImage: "list.bullet.rectangle")
                    .font(.callout)
                Text("enum")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
                Spacer()
                Text("\(enumNode.options.count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .onChange(of: expansion) { _, command in
            expanded = command.expanded
        }
    }
}
