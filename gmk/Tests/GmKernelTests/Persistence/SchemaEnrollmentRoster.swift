import Foundation
import GRDB

/// The enrolled persistence surface: every record that decodes a table, every
/// association, and every composite request.
///
/// `SchemaEnrollmentTests` walks these lists against the live schema, so a type
/// missing from here is a type nothing checks. Sorted by domain, then table.
enum SchemaEnrollment {

    /// How an entry reaches the database.
    enum Kind {
        /// One record per table, decoded from `SELECT *`.
        case mirror
        /// A record decoded from a join or a prefetch rather than one table.
        case composed
        /// A typed decoder for a projected result set, keyed to no table.
        case projection
    }

    struct RecordEntry: Sendable {
        let table: String
        let kind: Kind
        let decode: @Sendable (Row) throws -> Void
    }

    struct AssociationEntry: Sendable {
        let label: String
        let origin: String
        let destination: String
        /// The origin columns of an explicit `ForeignKey`; nil when GRDB infers.
        let originColumns: [String]?
        /// The `forKey` value, which must equal the decoding property's name.
        let decodedKey: String
        /// True for `including(all:)`, whose children arrive in a second
        /// statement and so leave the destination out of the prepared SQL.
        let isPrefetch: Bool
        let prepare: @Sendable (Database) throws -> String
    }

    struct CompositeEntry: Sendable {
        let label: String
        let prepare: @Sendable (Database) throws -> String
    }

    /// A record whose table name comes from the record itself: a name that has
    /// drifted from the schema fails at `columns(in:)` rather than decoding.
    private static func mirror<R: BaseRecordFields>(_: R.Type) -> RecordEntry {
        RecordEntry(table: R.databaseTableName, kind: .mirror) { _ = try R(row: $0) }
    }

    /// A projection names the table it reads over; its shape is the query's.
    private static func projection<R: SnakeCaseDecoded>(_: R.Type, over table: String) -> RecordEntry {
        RecordEntry(table: table, kind: .projection) { _ = try R(row: $0) }
    }

    static let records: [RecordEntry] = [
        mirror(AgentBriefingRecord.self),
        mirror(AgentBriefingDopeKbiteRecord.self),
        mirror(AgentBriefingDopePersistenceRecord.self),
        mirror(AgentRegistrationRecord.self),
        mirror(AgentSessionFileChangeRecord.self),
        mirror(ArchitectureGeneralChangeRecord.self),
        mirror(ArchitectureOptionRecord.self),
        mirror(ArchitecturePersistenceChangeRecord.self),
        mirror(ArchitecturePersistenceFieldChangeRecord.self),
        mirror(ArchitectureSummaryRecord.self),
        mirror(BotWorkflowRecord.self),
        mirror(CarePackageRecord.self),
        mirror(CarePackageDopeRefRecord.self),
        mirror(CarePackageExplorationRefRecord.self),
        mirror(CarePackageKbiteRefRecord.self),
        mirror(ClarificationSummaryRecord.self),
        mirror(ExplorationFindingRecord.self),
        mirror(ExplorationSummaryRecord.self),
        mirror(FileChangeRecord.self),
        mirror(FileChangeRangeRecord.self),
        mirror(InternalClarificationNoteRecord.self),
        mirror(PromptActivationRecord.self),
        mirror(PromptArtifactRecord.self),
        mirror(PromptQualifiedDiagramRecord.self),
        mirror(ReviewFindingRecord.self),
        mirror(ReviewSummaryRecord.self),
        mirror(SessionFileRecord.self),
        mirror(UserClarificationAnswerRecord.self),
        mirror(UserClarificationOptionRecord.self),
        mirror(UserClarificationQuestionRecord.self),

        mirror(DiagramRecord.self),
        mirror(DiagramConnectorRecord.self),
        mirror(DiagramDopeEntityRecord.self),
        mirror(DiagramDopeScopePersistenceLayerRecord.self),
        mirror(DiagramDrawingLayerRecord.self),
        mirror(DiagramDrawingShapeRecord.self),
        mirror(DiagramDrawingStrokeRecord.self),
        mirror(DiagramDrawingTextRecord.self),
        mirror(DiagramElementRecord.self),
        mirror(DiagramShapeVertexRecord.self),
        mirror(DiagramStrokeVertexRecord.self),
        mirror(DiagramUmlNodeRecord.self),

        mirror(DopeCogRecord.self),
        mirror(DopeCogElementRecord.self),
        mirror(DopeCogHullRecord.self),
        mirror(DopeCogPersistenceOwnerRecord.self),
        mirror(DopeElementProvenanceRecord.self),
        mirror(DopePersistenceRecord.self),
        mirror(DopePersistenceEntityRecord.self),
        mirror(DopePersistenceEntityPropertyRecord.self),
        mirror(DopePersistenceEnumRecord.self),
        mirror(DopePersistenceEnumOptionRecord.self),
        mirror(DopeScopeRecord.self),

        mirror(InstanceActiveKbiteRecord.self),
        mirror(KbiteRecord.self),
        mirror(KbiteKeywordJunctionRecord.self),
        mirror(KbiteResourceRecord.self),
        mirror(KbiteResourceFileRecord.self),
        mirror(KeywordRecord.self),
        mirror(ProjectActiveKbiteRecord.self),
        mirror(PromptActiveKbiteRecord.self),
        mirror(ResourceFileKeywordJunctionRecord.self),
        mirror(SessionActiveKbiteRecord.self),

        mirror(DaemonConfigRecord.self),
        mirror(DaemonEventRecord.self),
        mirror(ProjectTestLockRecord.self),
        mirror(TestRunRecord.self),

        mirror(InstanceRecord.self),
        mirror(ProjectRecord.self),
        mirror(PromptRecord.self),
        mirror(SessionRecord.self),

        projection(KbiteResourceFileStubRecord.self, over: "kbite_resource_file"),
        projection(SessionStubRecord.self, over: "session"),
    ]

    /// One entry per `static let` association declared on a record.
    static let associations: [AssociationEntry] = []

    /// One entry per composite, preparing that composite's canonical request.
    static let composites: [CompositeEntry] = []
}
