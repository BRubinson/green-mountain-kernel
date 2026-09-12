import SwiftUI
import GMCCDaemonKit

/// The Lucidchart-style browse surface both diagram pages share: a searchable
/// LazyVGrid of thumbnail-first cards over DIAGRAM_SEARCH (empty query =
/// recency browse, typed query = FTS, debounced). The host owns creation and
/// per-tier row actions; this view owns fetch, live refresh, and the grid.
struct DiagramGalleryView<CardMenu: View>: View {
    @Environment(DaemonConnectionModel.self) private var daemon
    @Environment(DiagramCatalogStore.self) private var diagrams
    let scope: DiagramCatalogStore.GalleryScope
    let onOpen: (DiagramRow) -> Void
    @ViewBuilder let cardMenu: (DiagramRow) -> CardMenu

    @State private var query = ""

    private var rows: [DiagramRow] { diagrams.gallery(scope) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
        }
        .task(id: daemon.generation) {
            let stream = daemon.hub.stream(for: .diagramList(scope.streamKey))
            await diagrams.searchGallery(scope, query: query)
            for await _ in stream {
                // Re-runs the LAST query — a "deleted" event drops its card
                // here, since the re-fetch simply no longer returns the row.
                await diagrams.refreshGallery(scope)
            }
        }
        .task(id: query) {
            // ~250ms debounce: FTS per keystroke would queue N searches on
            // the serial daemon queue for one final answer.
            guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
            await diagrams.searchGallery(scope, query: query)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search diagrams", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let error = diagrams.galleryErrors[scope] {
            ContentUnavailableView("Diagrams Unavailable", systemImage: "bolt.slash",
                                   description: Text(error))
        } else if rows.isEmpty {
            if diagrams.galleryLoaded(scope) {
                ContentUnavailableView(
                    query.isEmpty ? "No Diagrams Yet" : "No Matches",
                    systemImage: query.isEmpty
                        ? "point.3.connected.trianglepath.dotted" : "magnifyingglass",
                    description: Text(query.isEmpty
                        ? "Diagrams you create appear here."
                        : "Nothing matches “\(query)”."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280),
                                             spacing: 12)],
                          spacing: 12) {
                    ForEach(rows, id: \.uuid) { row in
                        DiagramGalleryCard(row: row, onOpen: { onOpen(row) }) {
                            cardMenu(row)
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}

/// One card: LIVE scaled thumbnail (a real DiagramCanvasView over the cached
/// resolve, never a screenshot), name, code, tier badge, and — for PUBLIC
/// rows — the accented visibility badge.
private struct DiagramGalleryCard<Menu: View>: View {
    @Environment(DiagramCatalogStore.self) private var diagrams
    let row: DiagramRow
    let onOpen: () -> Void
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                thumbnail
                HStack(spacing: 6) {
                    Text(row.name).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    tierBadge
                    if row.visibility == DiagramVisibility.public.rawValue {
                        badge("PUBLIC", tint: Color.accentColor)
                    }
                }
                Text(row.code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contextMenu { menu() }
        // Revision-keyed: a commit anywhere re-fetches exactly this card.
        .task(id: "\(row.uuid):\(row.revision)") {
            await diagrams.loadThumbnail(for: row)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
            if let resolved = diagrams.thumbnail(for: row) {
                DiagramThumbnailView(resolved: resolved)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(.separator.opacity(0.5), lineWidth: 1))
    }

    private var tierBadge: some View {
        badge(row.tier, tint: .secondary)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// A resolve scaled to fit its container — the live-view thumbnail. Hit
/// testing is off wholesale: the card's button owns the click.
private struct DiagramThumbnailView: View {
    let resolved: ResolvedDiagram

    var body: some View {
        GeometryReader { proxy in
            let canvas = DiagramCanvasView(resolved: resolved)
            let size = canvas.totalSize
            let scale = min(proxy.size.width / max(size.width, 1),
                            proxy.size.height / max(size.height, 1), 1)
            canvas
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
