import SwiftUI

/// The machine's name and code, as recorded at first boot.
struct MachineSection: View {
    @Environment(MachineHostService.self) private var host

    var body: some View {
        Section("Machine") {
            if let machine = host.snapshot?.machine {
                LabeledContent("Name", value: machine.name)
                LabeledContent("Code", value: machine.code).monospaced()
                LabeledContent("Root", value: host.rootPath).truncationMode(.middle)
            } else {
                Text("Not recorded yet").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Displays

/// Every display the machine has ever seen: built-in first, then connected, then by name.
struct DisplaysSection: View {
    @Environment(MachineHostService.self) private var host

    var body: some View {
        Section("Displays") {
            if displays.isEmpty {
                Text("No displays recorded yet").foregroundStyle(.secondary)
            }
            ForEach(displays, id: \.uuid) { display in
                DisplayRowView(display: display)
            }
        }
    }

    /// The recorded displays in screen order.
    private var displays: [DisplayRow] {
        (host.snapshot?.displays ?? []).sorted { rank($0) < rank($1) }
    }

    /// The sort key of a display: built-in, then connected, then name.
    ///
    /// - Parameter display: A display row.
    /// - Returns: The key; smaller sorts first.
    private func rank(_ display: DisplayRow) -> (Int, Int, String) {
        (display.isBuiltin ? 0 : 1, display.isConnected ? 0 : 1, display.name)
    }
}

/// One display: its symbol, name and badges over a line of hardware specs.
struct DisplayRowView: View {
    let display: DisplayRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(display.isConnected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(display.name).fontWeight(.medium)
                    if display.isBuiltin { Badge(text: "Built-in", tint: .secondary) }
                }
                Text(DisplaySpec.summary(display))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ConnectionIndicator(
                isConnected: display.isConnected,
                firstSeenAt: display.createdAt,
                lastSeenAt: display.lastSeenAt
            )
        }
        .padding(.vertical, 2)
        .opacity(display.isConnected ? 1 : 0.6)
    }
}

/// A coloured dot and the words for a display's connection, with when it was first and last seen.
struct ConnectionIndicator: View {
    let isConnected: Bool
    let firstSeenAt: String
    let lastSeenAt: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isConnected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(isConnected ? "Connected" : "Disconnected").font(.caption)
            }
            if !isConnected, let seen = DisplaySpec.seen(lastSeenAt) {
                Text("Last seen \(seen)").font(.caption2).foregroundStyle(.tertiary)
            }
            if let first = DisplaySpec.seen(firstSeenAt) {
                Text("First seen \(first)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

/// The words for a display's recorded hardware specs.
enum DisplaySpec {
    /// Resolution, scale, diagonal and refresh joined into one line.
    ///
    /// For example `3024 × 1964 · @2x · 14.2″ · 120 Hz`.
    ///
    /// - Parameter display: A display row.
    /// - Returns: The line; a spec never read shows as `unknown`.
    static func summary(_ display: DisplayRow) -> String {
        [resolution(display), scale(display.backingScale), diagonal(display), refresh(display.refreshHz)]
            .joined(separator: " · ")
    }

    /// The native pixel resolution.
    ///
    /// - Parameter display: A display row.
    /// - Returns: `width × height`, or `Resolution unknown`.
    static func resolution(_ display: DisplayRow) -> String {
        guard let width = display.pixelWidth, let height = display.pixelHeight else { return "Resolution unknown" }
        return "\(width) × \(height)"
    }

    /// The backing scale as a Retina factor.
    ///
    /// - Parameter scale: Pixels per point.
    /// - Returns: `@2x`, `@1.5x`, or `Scale unknown`.
    static func scale(_ scale: Double?) -> String {
        guard let scale, scale > 0 else { return "Scale unknown" }
        return "@\(scale.formatted(.number.precision(.fractionLength(0...1))))x"
    }

    /// The diagonal in inches, from the physical width and height in millimetres.
    ///
    /// - Parameter display: A display row.
    /// - Returns: e.g. `27.0″`, or `Size unknown` when the panel reports no size.
    static func diagonal(_ display: DisplayRow) -> String {
        guard let width = display.physicalWidthMm, let height = display.physicalHeightMm, width > 0, height > 0 else {
            return "Size unknown"
        }
        let inches = (width * width + height * height).squareRoot() / 25.4
        return "\(inches.formatted(.number.precision(.fractionLength(1))))″"
    }

    /// The refresh rate in hertz.
    ///
    /// - Parameter hertz: The rate, or nil when unread.
    /// - Returns: e.g. `120 Hz`, or `Refresh unknown`.
    static func refresh(_ hertz: Double?) -> String {
        guard let hertz, hertz > 0 else { return "Refresh unknown" }
        return "\(hertz.formatted(.number.precision(.fractionLength(0...2)))) Hz"
    }

    /// A stored ISO-8601 timestamp as a relative date.
    ///
    /// - Parameter timestamp: The stored text, or nil.
    /// - Returns: e.g. `2 days ago`, or nil when absent or unparseable.
    static func seen(_ timestamp: String?) -> String? {
        guard let timestamp, let date = try? Date(timestamp, strategy: .iso8601) else { return nil }
        return date.formatted(.relative(presentation: .named))
    }
}

// MARK: - Workstations

/// Every workstation, one per display set ever connected; picking one shows its grid below.
struct WorkstationsSection: View {
    @Environment(MachineHostService.self) private var host
    /// The workstation the grid shows.
    @Binding var selection: String?

    var body: some View {
        Section {
            if workstations.isEmpty {
                Text("A workstation is recorded the first time a set of displays is connected")
                    .foregroundStyle(.secondary)
            }
            ForEach(workstations, id: \.uuid) { workstation in
                WorkstationRowView(
                    workstation: workstation,
                    members: Workstations.members(of: workstation.uuid, in: host.snapshot),
                    isActive: workstation.uuid == host.snapshot?.activeWorkstationUuid,
                    isSelected: workstation.uuid == selection
                ) { selection = workstation.uuid }
            }
        } header: {
            Text("Workstations")
        } footer: {
            Text("The active workstation follows the connected displays. Select one to arrange its workspaces.")
        }
    }

    /// The workstations, the active one first, then by name.
    private var workstations: [WorkstationRow] {
        let active = host.snapshot?.activeWorkstationUuid
        return (host.snapshot?.workstations ?? [])
            .sorted {
                ($0.uuid == active ? 0 : 1, $0.name) < ($1.uuid == active ? 0 : 1, $1.name)
            }
    }
}

/// One workstation: a selection mark, its editable name, an Active badge and its displays in position order.
struct WorkstationRowView: View {
    @Environment(MachineHostService.self) private var host
    let workstation: WorkstationRow
    let members: [DisplayRow]
    let isActive: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var name = ""
    /// The name last sent to the store, until the snapshot carries it back.
    @State private var submitted: String?
    @State private var confirmingForget = false
    @FocusState private var editing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .fontWeight(.medium)
                        .focused($editing)
                        .onSubmit { rename() }
                    if isActive { Badge(text: "Active", tint: .green) }
                }
                memberLine.font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Forget Workstation…", role: .destructive) { confirmingForget = true }
                .disabled(isActive)
        }
        .confirmationDialog(
            "Forget “\(workstation.name)”?",
            isPresented: $confirmingForget,
            titleVisibility: .visible
        ) {
            Button("Forget", role: .destructive) { Task { await host.forget(workstation: workstation) } }
        } message: {
            Text(
                "Its name and workspace placement are discarded. "
                    + "Connecting these displays again records a new workstation."
            )
        }
        .onAppear { name = workstation.name }
        .onChange(of: workstation.name) { _, stored in
            submitted = nil
            if !editing { name = stored }
        }
        .onChange(of: editing) { _, focused in if !focused { rename() } }
    }

    /// The member displays joined with `+`, the seed display (position 0) marked with a star.
    private var memberLine: Text {
        members.enumerated()
            .reduce(Text("")) { line, entry in
                let separator = entry.offset == 0 ? Text("") : Text("  +  ")
                let seed = entry.offset == 0 ? Text(Image(systemName: "star.fill")) + Text(" ") : Text("")
                return line + separator + seed + Text(entry.element.name)
            }
    }

    /// Saves the edited name once, when it is not blank and differs from the stored or pending one.
    ///
    /// Submit and blur both call this; the pending name stops the second call writing at a stale version.
    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            name = submitted ?? workstation.name
            return
        }
        guard trimmed != (submitted ?? workstation.name) else { return }
        submitted = trimmed
        Task { await host.rename(workstation: workstation, name: trimmed) }
    }
}

/// Lookups over a snapshot's workstation rows.
enum Workstations {
    /// The displays of a workstation in position order.
    ///
    /// - Parameters:
    ///   - workstationUuid: The workstation.
    ///   - snapshot: The snapshot, or nil before the first load.
    /// - Returns: The member display rows, position 0 first.
    static func members(of workstationUuid: String, in snapshot: MachineHostSnapshotRow?) -> [DisplayRow] {
        guard let snapshot else { return [] }
        let displays = Dictionary(snapshot.displays.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        return snapshot.workstationDisplays
            .filter { $0.workstationUuid == workstationUuid }
            .sorted { $0.position < $1.position }
            .compactMap { displays[$0.displayUuid] }
    }

    /// A workstation's placement rows, keyed by workspace code.
    ///
    /// - Parameters:
    ///   - workstationUuid: The workstation.
    ///   - snapshot: The snapshot, or nil before the first load.
    /// - Returns: One row per placed code.
    static func placement(
        of workstationUuid: String,
        in snapshot: MachineHostSnapshotRow?
    ) -> [String: WorkstationWorkspaceRow] {
        let rows = (snapshot?.workstationWorkspaces ?? []).filter { $0.workstationUuid == workstationUuid }
        return Dictionary(rows.map { ($0.workspaceCode, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Workspace grid

/// The selected workstation's workspaces: one column per display, holding the codes placed there.
struct WorkspaceGridSection: View {
    @Environment(MachineHostService.self) private var host
    /// The workstation to show.
    let workstationUuid: String?

    var body: some View {
        Section {
            if let workstationUuid, !members.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(members, id: \.uuid) { display in
                        DisplayColumnView(
                            display: display,
                            workstationUuid: workstationUuid,
                            members: members,
                            placement: placement
                        )
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Select a workstation").foregroundStyle(.secondary)
            }
        } header: {
            Text(title)
        } footer: {
            Text(
                "Click a workspace to show it on its display. Right-click to move it to another display; "
                    + "a display always keeps at least one workspace."
            )
        }
    }

    /// The selected workstation's member displays in position order.
    private var members: [DisplayRow] {
        workstationUuid.map { Workstations.members(of: $0, in: host.snapshot) } ?? []
    }

    /// The selected workstation's placement rows by code.
    private var placement: [String: WorkstationWorkspaceRow] {
        workstationUuid.map { Workstations.placement(of: $0, in: host.snapshot) } ?? [:]
    }

    /// The section header, naming the workstation shown.
    private var title: String {
        let name = host.snapshot?.workstations.first { $0.uuid == workstationUuid }?.name
        return name.map { "Workspaces on \($0)" } ?? "Workspaces"
    }
}

/// One display's column in the grid: a header and the chips of the codes placed on it.
struct DisplayColumnView: View {
    @Environment(MachineHostService.self) private var host
    let display: DisplayRow
    let workstationUuid: String
    /// Every member display of the workstation, in position order.
    let members: [DisplayRow]
    let placement: [String: WorkstationWorkspaceRow]

    private let columns = [GridItem(.adaptive(minimum: 34, maximum: 44), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(display.name, systemImage: display.isBuiltin ? "laptopcomputer" : "display")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(display.isConnected ? .primary : .secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(codes, id: \.self) { code in
                    WorkspaceChip(code: code, isActive: placement[code]?.isActive == true)
                        .onTapGesture {
                            Task { await host.setActive(code: code, on: display.uuid, in: workstationUuid) }
                        }
                        .contextMenu { menu(for: code) }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: .rect(cornerRadius: 8))
    }

    /// The codes placed on this display, in table order.
    private var codes: [String] {
        MachineHostPlacement.WorkspaceCodes.all.filter { placement[$0]?.displayUuid == display.uuid }
    }

    /// The chip's menu: show it here, or move it to another member display.
    ///
    /// A move that would leave this display with no workspace is disabled.
    ///
    /// - Parameter code: The chip's workspace code.
    /// - Returns: The menu items.
    @ViewBuilder
    private func menu(for code: String) -> some View {
        Button("Show on \(display.name)") {
            Task { await host.setActive(code: code, on: display.uuid, in: workstationUuid) }
        }
        .disabled(placement[code]?.isActive == true)
        if members.count > 1 { Divider() }
        ForEach(members.filter { $0.uuid != display.uuid }, id: \.uuid) { target in
            Button("Move to \(target.name)") {
                Task { await host.assign(code: code, to: target.uuid, in: workstationUuid) }
            }
            .disabled(host.assignRefusal(code: code, to: target.uuid, in: workstationUuid) != nil)
        }
    }
}

/// One workspace code as a rounded key cap; the active one is filled with the accent colour.
struct WorkspaceChip: View {
    let code: String
    let isActive: Bool

    var body: some View {
        Text(code)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .frame(minWidth: 34, minHeight: 28)
            .foregroundStyle(isActive ? Color.white : .primary)
            .background(
                isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                in: .rect(cornerRadius: 6)
            )
            .contentShape(.rect(cornerRadius: 6))
            .help(isActive ? "Workspace \(code), showing" : "Show workspace \(code)")
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Windows by app

/// One app in the rules list: its windows as the mirror last recorded them and its rule, if any.
struct AppRuleEntry: Identifiable, Hashable {
    /// The bundle identifier, which is the row's identity.
    var id: String { bundleId }
    /// The app's bundle identifier.
    let bundleId: String
    /// The app's display name.
    let name: String
    /// The app's live windows that tile.
    let tiled: Int
    /// The app's live windows that float, minimized and hidden ones included.
    let floating: Int
    /// True when a live process of the app is recorded.
    let isRunning: Bool
    /// The app's rule, or nil when the classifier decides.
    let rule: WindowRuleDisposition?
}

/// Folds a snapshot's processes, windows and rules into the rules list.
enum AppRules {
    /// One entry per running app with a window or a rule, plus one per rule whose app is not running.
    ///
    /// - Parameter snapshot: The snapshot, or nil before the first load.
    /// - Returns: The entries, sorted by name.
    static func entries(in snapshot: MachineHostSnapshotRow?) -> [AppRuleEntry] {
        guard let snapshot else { return [] }
        let rules = Dictionary(snapshot.windowRules.map { ($0.bundleId, $0) }, uniquingKeysWith: { first, _ in first })
        var bundleOf: [String: String] = [:]
        var names: [String: String] = [:]
        for process in snapshot.appProcesses where process.deletedOn == nil {
            guard let bundleId = process.bundleId else { continue }
            bundleOf[process.uuid] = bundleId
            names[bundleId] = names[bundleId] ?? process.name
        }
        var counts: [String: (tiled: Int, floating: Int)] = [:]
        for window in snapshot.managedWindows where window.deletedOn == nil {
            guard let bundleId = bundleOf[window.appProcessUuid] else { continue }
            var count = counts[bundleId] ?? (0, 0)
            if window.isFloating { count.floating += 1 } else { count.tiled += 1 }
            counts[bundleId] = count
        }
        var entries: [AppRuleEntry] = names.compactMap { bundleId, name in
            let count = counts[bundleId] ?? (0, 0)
            guard count.tiled + count.floating > 0 || rules[bundleId] != nil else { return nil }
            return AppRuleEntry(
                bundleId: bundleId,
                name: name,
                tiled: count.tiled,
                floating: count.floating,
                isRunning: true,
                rule: rules[bundleId]?.disposition
            )
        }
        for rule in snapshot.windowRules where names[rule.bundleId] == nil {
            entries.append(
                AppRuleEntry(
                    bundleId: rule.bundleId,
                    name: rule.appName,
                    tiled: 0,
                    floating: 0,
                    isRunning: false,
                    rule: rule.disposition
                )
            )
        }
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Every app with windows or a remembered rule, each with a Default, Tile or Float choice.
struct AppRulesSection: View {
    @Environment(MachineHostService.self) private var host

    var body: some View {
        Section {
            if entries.isEmpty {
                Text("No app windows observed").foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                AppRuleRowView(entry: entry)
            }
        } header: {
            Text("Windows by app")
        } footer: {
            Text(
                "Tile gives every window of the app a column. Float keeps them above the tiles where you leave "
                    + "them. Default lets the window manager decide. Rules are remembered on this Mac."
            )
        }
    }

    /// The rules list for the current snapshot.
    private var entries: [AppRuleEntry] {
        AppRules.entries(in: host.snapshot)
    }
}

/// One app: its name, bundle id and window counts, and a segmented Default, Tile or Float picker.
struct AppRuleRowView: View {
    @Environment(MachineHostService.self) private var host
    let entry: AppRuleEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).fontWeight(.medium)
                Text(caption)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Picker("Rule for \(entry.name)", selection: rule) {
                Text("Default").tag(WindowRuleDisposition?.none)
                Text("Tile").tag(WindowRuleDisposition?.some(.tile))
                Text("Float").tag(WindowRuleDisposition?.some(.float))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
        }
        .padding(.vertical, 2)
        .opacity(entry.isRunning ? 1 : 0.6)
    }

    /// The bundle id with the window counts, or with `not running`.
    private var caption: String {
        guard entry.isRunning else { return "\(entry.bundleId) · not running" }
        return "\(entry.bundleId) · \(entry.tiled) tiled · \(entry.floating) floating"
    }

    /// The rule as the picker's selection; a pick writes it through the host.
    private var rule: Binding<WindowRuleDisposition?> {
        Binding(
            get: { entry.rule },
            set: { disposition in
                let entry = entry
                Task {
                    await host.setWindowRule(bundleId: entry.bundleId, appName: entry.name, disposition: disposition)
                }
            }
        )
    }
}

// MARK: - Key legend

/// The fixed hotkeys, read-only, with any chord another app already holds called out.
struct KeyLegendSection: View {
    @Environment(MachineHostService.self) private var host

    var body: some View {
        Section {
            ForEach(KeyLegend.rows(KeyCodeTable.bindings), id: \.chord) { row in
                LabeledContent {
                    Text(row.chord).monospaced().foregroundStyle(.primary)
                } label: {
                    Text(row.meaning)
                }
            }
            if !host.conflictedChords.isEmpty {
                Label(KeyLegend.conflictLine(host.conflictedChords), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Keys")
        } footer: {
            Text("Workspace keys are 1–9, Q W E R T Y and A S D F G H.")
        }
    }
}

/// Folds the static bindings into legend rows; `KeyCodeTable` owns every chord and action label.
enum KeyLegend {
    /// One legend line.
    struct Row: Hashable {
        /// The chord or chord family, e.g. `⌥1 … ⌥H`.
        let chord: String
        /// What it does.
        let meaning: String
    }

    /// The legend rows for `bindings` in table order, each workspace action folded into one family row.
    ///
    /// - Parameter bindings: The static hotkey table.
    /// - Returns: The rows.
    static func rows(_ bindings: [HotkeyBinding]) -> [Row] {
        var rows: [Row] = []
        var families: Set<HotkeyAction> = []
        for binding in bindings {
            switch binding.action {
            case .focusWorkspace, .moveToWorkspace:
                guard families.insert(binding.action).inserted else { continue }
                rows.append(family(binding.action, in: bindings))
            default:
                rows.append(
                    Row(chord: KeyCodeTable.chordLabel(for: binding), meaning: KeyCodeTable.meaning(for: binding))
                )
            }
        }
        return rows
    }

    /// The one row standing for every binding of a workspace action: its modifiers over the code span.
    ///
    /// - Parameters:
    ///   - action: `focusWorkspace` or `moveToWorkspace`.
    ///   - bindings: The static hotkey table.
    /// - Returns: The row, e.g. `⌥ 1…H` / `Show workspace`.
    static func family(_ action: HotkeyAction, in bindings: [HotkeyBinding]) -> Row {
        let members = bindings.filter { $0.action == action }
        guard let first = members.first, let last = members.last else { return Row(chord: "", meaning: "") }
        let span = "\(first.workspaceCode ?? "")…\(last.workspaceCode ?? "")"
        return Row(
            chord: "\(KeyCodeTable.glyphs(for: first.modifiers)) \(span)",
            meaning: KeyCodeTable.meaning(for: first)
        )
    }

    /// The conflict warning naming each chord another app holds.
    ///
    /// - Parameter conflicts: The chords Carbon refused.
    /// - Returns: The line.
    static func conflictLine(_ conflicts: [HotkeyBinding]) -> String {
        let chords = conflicts.map(KeyCodeTable.chordLabel(for:)).joined(separator: ", ")
        return conflicts.count == 1
            ? "\(chords) is held by another app and does nothing here"
            : "\(chords) are held by other apps and do nothing here"
    }
}

// MARK: - Shared

/// A small capsule tag, e.g. `Built-in` or `Active`.
struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: .capsule)
    }
}
