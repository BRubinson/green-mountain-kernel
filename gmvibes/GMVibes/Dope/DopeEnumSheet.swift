import SwiftUI
import GMCCDaemonKit

/// Read-only enum inspector: the enum's options up top, every property that
/// uses it below. Exists so an enum can be read WITHOUT scrolling to its
/// definition — it never writes, so there is no version threading here.
struct DopeEnumSheet: View {
    @Environment(\.dismiss) private var dismiss
    let info: DopeEnumCatalog.Resolved
    /// The property the user clicked, marked in the usage list so they can
    /// see where they came from.
    let originPropertyUuid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    optionsSection
                    usageSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 420)          // short enums get a compact sheet
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(info.node.body.name, systemImage: "list.bullet.rectangle")
                    .font(.title3.weight(.semibold))
                Text(info.ref)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Text(info.domainName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !info.node.body.description.isEmpty {
                Text(info.node.body.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Code / Name left, description right — three Grid columns so the
    // descriptions line up regardless of code length.
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Options", count: info.node.options.count)
            if info.node.options.isEmpty {
                Text("This enum has no options yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Code"); Text("Name"); Text("Description")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                        .gridCellColumns(3)
                    ForEach(info.node.options, id: \.identity.uuid) { option in
                        GridRow {
                            Text(option.body.code)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(option.body.name)
                                .font(.callout)
                            Text(option.body.description.isEmpty ? "—" : option.body.description)
                                .font(.callout)
                                .foregroundStyle(option.body.description.isEmpty
                                                 ? AnyShapeStyle(.tertiary)
                                                 : AnyShapeStyle(.secondary))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // Grouped by domain, tree order preserved (the daemon already sorts).
    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Used By", count: info.usages.count)
            if info.usages.isEmpty {
                Text("No properties reference this enum.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedUsages, id: \.domain) { group in
                    Text(group.domain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                    ForEach(group.usages) { usage in
                        HStack(spacing: 6) {
                            Image(systemName: "tablecells")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(usage.entityName).font(.callout)
                            Text(usage.propertyName)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if !usage.nullable {
                                Text("required").font(.caption2).foregroundStyle(.orange)
                            }
                            if usage.propertyUuid == originPropertyUuid {
                                Text("this property")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.blue.opacity(0.15), in: .capsule)
                            }
                            Spacer()
                            Text(usage.ref)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                        .padding(.leading, 6)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.subheadline.weight(.semibold))
            Text("\(count)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    private var groupedUsages: [(domain: String, usages: [DopeEnumCatalog.Usage])] {
        var order: [String] = []
        var buckets: [String: [DopeEnumCatalog.Usage]] = [:]
        for usage in info.usages {
            if buckets[usage.domainName] == nil { order.append(usage.domainName) }
            buckets[usage.domainName, default: []].append(usage)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}

/// A tree reload can delete the enum while its dialog is open — resolve
/// failure gets an honest card, never a blank sheet.
struct DopeEnumMissingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let ref: String

    var body: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                "Enum No Longer Present",
                systemImage: "questionmark.square.dashed",
                description: Text("`\(ref)` is not in the tree that is loaded now."))
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 420)
    }
}
