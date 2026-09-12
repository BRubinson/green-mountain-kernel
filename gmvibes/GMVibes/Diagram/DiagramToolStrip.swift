import SwiftUI
import GMCCDaemonKit

/// The diagram screen's chrome (toolbar `primaryAction` slot): tool picker,
/// search over entities AND fields with viewport jump, the domain multi-pill
/// filter, Organize, and Fit.
struct DiagramToolStrip: View {
    let workspace: DiagramWorkspace
    let viewState: DiagramViewState
    let onCenter: (CGPoint) -> Void
    let onFit: () -> Void
    let onOrganize: () -> Void
    let onCopy: () -> Void
    let onInsertNode: (DiagramNodeKind) -> Void
    let onAddDopeScope: () -> Void

    var body: some View {
        // Tool picker: only `select` can drag nodes; freehand draws on the
        // drawing layer (trackpad pan works in every tool via the bridge).
        Picker("Tool", selection: Binding(
            get: { viewState.tool },
            set: { viewState.tool = $0 }
        )) {
            ForEach(DiagramTool.allCases) { tool in
                Image(systemName: tool.symbol).tag(tool).help(tool.help)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)

        // The UML shape vocabulary — inserts land at the viewport center on
        // the drawing layer, replacing the retired rect/line/text tools.
        Menu {
            ForEach(DiagramNodeKind.allCases, id: \.rawValue) { kind in
                Button {
                    onInsertNode(kind)
                } label: {
                    Label(Self.nodeLabel(kind), systemImage: Self.nodeSymbol(kind))
                }
            }
        } label: {
            Label("Insert Node", systemImage: "plus.square.on.square")
        }
        .help("Insert a UML node at the center of the view")

        Button {
            onAddDopeScope()
        } label: {
            Label("Add Dope Scope", systemImage: "rectangle.stack.badge.plus")
        }
        .help("Add entities from the bound dope scope to the canvas")

        domainPills

        DiagramSearchField(workspace: workspace, viewState: viewState,
                           onCenter: onCenter)

        Button {
            onOrganize()
        } label: {
            Label("Organize", systemImage: "wand.and.sparkles")
        }
        .help("Organize cards by FK closeness (deterministic, keeps A* corridors open)")

        Button {
            onFit()
        } label: {
            Label("Fit", systemImage: "arrow.down.left.and.arrow.up.right")
        }
        .help("Fit the whole diagram in the window")

        Button {
            onCopy()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .help("Copy the rendered diagram to the clipboard")
    }

    /// Multi-select domain pills. RENDER-TIME filtering (see
    /// DiagramDomainFilter): toggling hides cards in the resolved output and
    /// never touches the tree, so a pill click costs no write and no re-mint.
    @ViewBuilder
    private var domainPills: some View {
        if let dope = workspace.dope, dope.tree.domains.count > 1 {
            Menu {
                ForEach(dope.tree.domains, id: \.identity.uuid) { domain in
                    let code = domain.body.code
                    let active = workspace.domainFilter.isEmpty
                        || workspace.domainFilter.contains(code)
                    Button {
                        toggle(code, allCodes: dope.tree.domains.map(\.body.code))
                    } label: {
                        Label(domain.body.name,
                              systemImage: active ? "checkmark.circle.fill" : "circle")
                    }
                }
                if !workspace.domainFilter.isEmpty {
                    Divider()
                    Button("Show All Domains") { workspace.setDomainFilter([]) }
                }
            } label: {
                Label(workspace.domainFilter.isEmpty
                        ? "Domains"
                        : "Domains (\(workspace.domainFilter.count))",
                      systemImage: "square.stack.3d.up")
            }
            .help("Filter the diagram to selected domains")
        }
    }

    static func nodeLabel(_ kind: DiagramNodeKind) -> String {
        switch kind {
        case .dbCylinder: "Database"
        case .roundedRect: "Rounded Rectangle"
        case .triangle: "Triangle"
        case .rhombus: "Rhombus"
        case .diamond: "Diamond"
        case .circle: "Circle"
        }
    }

    static func nodeSymbol(_ kind: DiagramNodeKind) -> String {
        switch kind {
        case .dbCylinder: "cylinder"
        case .roundedRect: "rectangle.roundedtop"
        case .triangle: "triangle"
        case .rhombus: "rhombus"
        case .diamond: "diamond"
        case .circle: "circle"
        }
    }

    private func toggle(_ code: String, allCodes: [String]) {
        var filter = workspace.domainFilter.isEmpty
            ? Set(allCodes) : workspace.domainFilter
        if filter.contains(code) { filter.remove(code) } else { filter.insert(code) }
        // Everything selected == no filter.
        workspace.setDomainFilter(filter.count == allCodes.count ? [] : filter)
    }
}

/// Search entities AND fields: a pure query over the loaded DopeScopeTree.
/// Picking a result centers the viewport on the card (entity hit) or the
/// exact property row (field hit, via the resolver's own row-Y formula) and
/// selects the card so the outline + FK edge accent come free.
private struct DiagramSearchField: View {
    let workspace: DiagramWorkspace
    let viewState: DiagramViewState
    let onCenter: (CGPoint) -> Void

    struct Hit: Identifiable {
        let id = UUID()
        let entityCode: String
        let label: String
        let rowIndex: Int?
    }

    var body: some View {
        TextField("Search entities & fields", text: Binding(
            get: { viewState.searchText },
            set: { viewState.searchText = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .frame(width: 180)
        // Return jumps to the best hit; the menu offers the full list.
        .onSubmit {
            if let first = hits.first { jump(to: first) }
        }

        Menu {
            let hits = self.hits
            if hits.isEmpty {
                Text(viewState.searchText.isEmpty
                        ? "Type in the search field first" : "No matches")
            }
            ForEach(hits) { hit in
                Button(hit.label) { jump(to: hit) }
            }
        } label: {
            Label("Matches", systemImage: "magnifyingglass")
        }
        .help("Search results — picking one centers the viewport on the entity or field row")
    }

    /// Entities and properties by name/code, case-insensitive. Ghost cards
    /// (codes matching nothing) never come from here — the query runs over
    /// the DOPE tree, not the diagram.
    private var hits: [Hit] {
        let query = viewState.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let dope = workspace.dope else { return [] }
        var result: [Hit] = []
        // Respect the active pill filter: a hidden domain's entities have no
        // cards, so a hit there would silently no-op on jump.
        let filter = workspace.domainFilter
        for domain in dope.tree.domains
        where filter.isEmpty || filter.contains(domain.body.code) {
            for entity in domain.entities {
                let entityCode = "\(domain.body.code).\(entity.body.code)"
                if matches(query, entity.body.name) || matches(query, entity.body.code) {
                    result.append(Hit(entityCode: entityCode,
                                      label: "\(entity.body.name)  ·  \(entityCode)",
                                      rowIndex: nil))
                }
                // rowIndex maps 1:1 to DRAWN rows for OWN properties (the
                // composed-base union only appends after them).
                for (index, property) in entity.properties.enumerated()
                where matches(query, property.body.name) || matches(query, property.body.code) {
                    result.append(Hit(entityCode: entityCode,
                                      label: "\(property.body.code)  ·  \(entityCode)",
                                      rowIndex: index))
                }
            }
            if result.count > 20 { break }
        }
        return Array(result.prefix(20))
    }

    private func matches(_ query: String, _ candidate: String) -> Bool {
        candidate.range(of: query, options: .caseInsensitive) != nil
    }

    private func jump(to hit: Hit) {
        // Resolve the entity code to its REAL card. Duplicate-code cards are
        // legal; first-in-paint-order wins (deterministic).
        guard let element = cardElement(entityCode: hit.entityCode) else { return }
        viewState.selection = DiagramSelectionState(
            selectedElementUuid: element.uuid,
            highlightedElementUuids: [element.uuid])
        if let rowIndex = hit.rowIndex {
            let y = element.rowCenterY(rowIndex,
                                       environment: workspace.resolved.environment)
            onCenter(CGPoint(x: element.frame.midX, y: y))
        } else {
            onCenter(CGPoint(x: element.frame.midX, y: element.frame.midY))
        }
    }

    private func cardElement(entityCode: String) -> ResolvedElement? {
        func walk(_ element: ResolvedElement) -> ResolvedElement? {
            if case .entityCard(let model) = element.kind,
               model.entityCode == entityCode {
                return element
            }
            for child in element.children {
                if let found = walk(child) { return found }
            }
            return nil
        }
        for top in workspace.resolved.topLevel {
            if let found = walk(top) { return found }
        }
        return nil
    }
}
