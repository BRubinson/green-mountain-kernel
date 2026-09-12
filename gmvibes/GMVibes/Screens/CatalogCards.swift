import SwiftUI
import GMCCDaemonKit

// Shared drill-down leaves for the landing / project / instance surfaces:
// one instance row with its inline session blocks, and the compact session
// block itself. The active (checked-out) session keeps the recents-strip
// idiom — green outline + dot — as the ONE active indicator everywhere.

enum CatalogDates {
    private static let iso = ISO8601DateFormatter()
    nonisolated static func relative(_ raw: String) -> String {
        guard let date = iso.date(from: raw) else { return "—" }
        return date.formatted(.relative(presentation: .named))
    }
}

/// One compact inline session block (landing rows / project page).
struct SessionBlockCard: View {
    let stub: SessionStub
    let active: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stub.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack {
                    Text(CatalogDates.relative(stub.lastActivityAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    // Hidden (not removed) so state changes never shift layout.
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                        .opacity(active ? 1 : 0)
                }
            }
            .padding(10)
            .frame(width: 150, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .stateBorder(.green, active: active, cornerRadius: 12)
        .help(active ? "Checked out on this instance's repo" : stub.name)
    }
}

/// One instance row plus its inline session blocks. The row navigates to the
/// instance; each block navigates to its session.
struct InstanceSessionBlock: View {
    let instance: InstanceRow
    let sessions: [SessionStub]
    /// Pre-limit count (FilteredCatalog.totalSessions) for the "N sessions"
    /// affordance beside a limited list.
    let totalSessions: Int
    let activeSessionUuid: String?
    let onOpenInstance: () -> Void
    let onOpenSession: (SessionStub) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpenInstance) {
                HStack(spacing: 10) {
                    Image(systemName: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(instance.name)
                        .font(.subheadline.weight(.medium))
                    if !instance.absoluteFileSystemPath.isEmpty {
                        Text(instance.absoluteFileSystemPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text("\(totalSessions) session\(totalSessions == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !sessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sessions, id: \.uuid) { stub in
                            SessionBlockCard(
                                stub: stub,
                                active: stub.uuid == activeSessionUuid,
                                onOpen: { onOpenSession(stub) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
