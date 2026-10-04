import Foundation

/// Total projection between wire tree (identity-bearing) and on-disk document
/// bundle (identity-free).
///
/// References are dot-path codes in both representations; uuid↔code resolution
/// happens in Store+Dope hydration/ingest. This projection is pure structure:
/// drop identity outbound. No inverse fabricates identity (ingest mints fresh
/// rows; every child uuid changes, the locked no-smart-diff consequence).
enum DopeProjection {

    /// Projects a dope scope tree into a document bundle.
    ///
    /// The `cogs` parameter is defaulted because only the repo write path has
    /// access to the scope's cog rows.
    ///
    /// - Parameters:
    ///   - tree: The dope scope tree to project.
    ///   - cogs: The cog nodes for the scope, defaulting to an empty array.
    /// - Returns: The document bundle for the tree.
    static func documents(
        from tree: DopeScopeTree,
        cogs: [DopeCogNode] = []
    ) -> DopeDocumentBundle {
        let liveCogs = cogs.filter { $0.deletedOn == nil }
            .sorted { ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code) }
        // scope_type is deliberately absent: only a SESSION_INSTANCE tree is
        // writable, so persisting it would store a constant.
        let main = DopeScopeDocument(
            version: tree.revision,
            scope: tree.body,
            persistence: Dictionary(
                uniqueKeysWithValues: tree.domains.map {
                    ($0.body.code, DopeScopeDocument.expectedFile(forPersistenceCode: $0.body.code))
                }
            ),
            cogs: Dictionary(
                uniqueKeysWithValues: liveCogs.map {
                    ($0.code, DopeScopeDocument.expectedCogFile(forCogCode: $0.code))
                }
            )
        )
        let files = tree.domains.map { domain in
            DopePersistenceFileDocument(
                version: tree.revision,
                body: domain.body,
                entities: domain.entities.map { entity in
                    DopeEntityDocument(
                        body: entity.body,
                        properties: entity.properties.map { DopePropertyDocument(body: $0.body) }
                    )
                },
                enums: domain.enums.map { en in
                    DopeEnumDocument(
                        body: en.body,
                        options: en.options.map { DopeOptionDocument(body: $0.body) }
                    )
                }
            )
        }
        return DopeDocumentBundle(
            main: main,
            domainFiles: files,
            cogFiles: liveCogs.map(DopeCogProjection.document(from:))
        )
    }
}
