import Foundation
import GRDB

/// The enrolled persistence surface: every record that decodes a table, every
/// association, and every composite request.
///
/// `SchemaEnrollmentTests` walks these lists against the live schema, so a type
/// missing from here is a type nothing checks. Sorted by domain, then table.
enum SchemaEnrollment {

    struct RecordEntry: Sendable {
        let table: String
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
        RecordEntry(table: R.databaseTableName) { _ = try R(row: $0) }
    }

    /// A join association: `origin` is the table carrying the foreign key and
    /// `destination` the table it points at, which is the direction
    /// `foreign_key_list` reports. A `belongsTo` reads forwards, a `hasOne`
    /// backwards.
    private static func join<A: Association>(
        _ association: A,
        key: String,
        from origin: String,
        to destination: String,
        columns: [String]? = nil
    ) -> AssociationEntry where A.OriginRowDecoder: TableRecord {
        AssociationEntry(
            label: "\(A.OriginRowDecoder.self).\(key)",
            origin: origin,
            destination: destination,
            originColumns: columns,
            decodedKey: key,
            isPrefetch: false
        ) { db in
            try A.OriginRowDecoder.all()
                .including(optional: association)
                .makePreparedRequest(db)
                .statement.sql
        }
    }

    /// A `hasMany`, whose children arrive in a second statement. For a
    /// `through` form the recorded hop is the last one: pivot to destination.
    private static func prefetch<A: AssociationToMany>(
        _ association: A,
        key: String,
        from origin: String,
        to destination: String,
        columns: [String]? = nil
    ) -> AssociationEntry where A.OriginRowDecoder: TableRecord {
        AssociationEntry(
            label: "\(A.OriginRowDecoder.self).\(key)",
            origin: origin,
            destination: destination,
            originColumns: columns,
            decodedKey: key,
            isPrefetch: true
        ) { db in
            try A.OriginRowDecoder.all()
                .including(all: association)
                .makePreparedRequest(db)
                .statement.sql
        }
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
        mirror(ClaudeSessionBindingRecord.self),
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
    ]

    /// One entry per `static let` association declared on a record.
    static let associations: [AssociationEntry] = [
        prefetch(
            AgentBriefingRecord.dopeRefs,
            key: "dopeRefs",
            from: "agent_briefing_dope_persistence",
            to: "agent_briefing"
        ),
        prefetch(
            AgentBriefingRecord.kbiteRefs,
            key: "kbiteRefs",
            from: "agent_briefing_dope_kbite",
            to: "agent_briefing"
        ),
        prefetch(
            AgentBriefingRecord.fileChangeRefs,
            key: "fileChangeRefs",
            from: "agent_session_file_change",
            to: "agent_briefing"
        ),
        join(
            AgentBriefingDopeKbiteRecord.briefing,
            key: "briefing",
            from: "agent_briefing_dope_kbite",
            to: "agent_briefing"
        ),
        join(
            AgentBriefingDopePersistenceRecord.briefing,
            key: "briefing",
            from: "agent_briefing_dope_persistence",
            to: "agent_briefing"
        ),
        join(
            AgentSessionFileChangeRecord.briefing,
            key: "briefing",
            from: "agent_session_file_change",
            to: "agent_briefing"
        ),
        join(
            ArchitectureGeneralChangeRecord.summary,
            key: "summary",
            from: "architecture_general_change",
            to: "architecture_summary"
        ),
        join(ArchitectureOptionRecord.summary, key: "summary", from: "architecture_option", to: "architecture_summary"),
        prefetch(
            ArchitecturePersistenceChangeRecord.fields,
            key: "fields",
            from: "architecture_persistence_field_change",
            to: "architecture_persistence_change"
        ),
        join(
            ArchitecturePersistenceChangeRecord.summary,
            key: "summary",
            from: "architecture_persistence_change",
            to: "architecture_summary"
        ),
        join(
            ArchitecturePersistenceFieldChangeRecord.change,
            key: "change",
            from: "architecture_persistence_field_change",
            to: "architecture_persistence_change"
        ),
        prefetch(
            ArchitectureSummaryRecord.options,
            key: "options",
            from: "architecture_option",
            to: "architecture_summary"
        ),
        prefetch(
            ArchitectureSummaryRecord.persistenceChanges,
            key: "persistenceChanges",
            from: "architecture_persistence_change",
            to: "architecture_summary"
        ),
        prefetch(
            ArchitectureSummaryRecord.generalChanges,
            key: "generalChanges",
            from: "architecture_general_change",
            to: "architecture_summary"
        ),
        prefetch(CarePackageRecord.dopeRefs, key: "dopeRefs", from: "care_package_dope_ref", to: "care_package"),
        prefetch(CarePackageRecord.kbiteRefs, key: "kbiteRefs", from: "care_package_kbite_ref", to: "care_package"),
        prefetch(
            CarePackageRecord.explorationRefs,
            key: "explorationRefs",
            from: "care_package_exploration_ref",
            to: "care_package"
        ),
        join(
            CarePackageDopeRefRecord.carePackage,
            key: "carePackage",
            from: "care_package_dope_ref",
            to: "care_package"
        ),
        join(
            CarePackageExplorationRefRecord.carePackage,
            key: "carePackage",
            from: "care_package_exploration_ref",
            to: "care_package"
        ),
        join(
            CarePackageKbiteRefRecord.carePackage,
            key: "carePackage",
            from: "care_package_kbite_ref",
            to: "care_package"
        ),
        prefetch(
            ClarificationSummaryRecord.questions,
            key: "questions",
            from: "user_clarification_question",
            to: "clarification_summary"
        ),
        prefetch(
            ClarificationSummaryRecord.notes,
            key: "notes",
            from: "internal_clarification_note",
            to: "clarification_summary"
        ),
        join(
            ClarificationSummaryRecord.carePackage,
            key: "carePackage",
            from: "care_package",
            to: "clarification_summary"
        ),
        join(ClaudeSessionBindingRecord.session, key: "session", from: "claude_session_binding", to: "session"),
        join(ExplorationFindingRecord.summary, key: "summary", from: "exploration_finding", to: "exploration_summary"),
        prefetch(
            ExplorationSummaryRecord.findings,
            key: "findings",
            from: "exploration_finding",
            to: "exploration_summary"
        ),
        join(FileChangeRecord.sessionFile, key: "sessionFile", from: "file_change", to: "session_file"),
        prefetch(FileChangeRecord.ranges, key: "ranges", from: "file_change_range", to: "file_change"),
        join(FileChangeRecord.session, key: "session", from: "file_change", to: "session"),
        join(FileChangeRangeRecord.fileChange, key: "fileChange", from: "file_change_range", to: "file_change"),
        join(
            InternalClarificationNoteRecord.summary,
            key: "summary",
            from: "internal_clarification_note",
            to: "clarification_summary"
        ),
        join(PromptActivationRecord.session, key: "session", from: "prompt_activation", to: "session"),
        join(PromptActivationRecord.prompt, key: "prompt", from: "prompt_activation", to: "prompt"),
        join(PromptArtifactRecord.prompt, key: "prompt", from: "prompt_artifact", to: "prompt"),
        join(PromptQualifiedDiagramRecord.prompt, key: "prompt", from: "prompt_qualified_diagram", to: "prompt"),
        join(PromptQualifiedDiagramRecord.diagram, key: "diagram", from: "prompt_qualified_diagram", to: "diagram"),
        join(ReviewFindingRecord.summary, key: "summary", from: "review_finding", to: "review_summary"),
        prefetch(ReviewSummaryRecord.findings, key: "findings", from: "review_finding", to: "review_summary"),
        join(SessionFileRecord.session, key: "session", from: "session_file", to: "session"),
        prefetch(SessionFileRecord.fileChanges, key: "fileChanges", from: "file_change", to: "session_file"),
        join(
            UserClarificationAnswerRecord.question,
            key: "question",
            from: "user_clarification_answer",
            to: "user_clarification_question"
        ),
        join(
            UserClarificationAnswerRecord.option,
            key: "option",
            from: "user_clarification_answer",
            to: "user_clarification_option"
        ),
        join(
            UserClarificationOptionRecord.question,
            key: "question",
            from: "user_clarification_option",
            to: "user_clarification_question"
        ),
        prefetch(
            UserClarificationQuestionRecord.options,
            key: "options",
            from: "user_clarification_option",
            to: "user_clarification_question"
        ),
        prefetch(
            UserClarificationQuestionRecord.answers,
            key: "answers",
            from: "user_clarification_answer",
            to: "user_clarification_question"
        ),
        join(
            UserClarificationQuestionRecord.summary,
            key: "summary",
            from: "user_clarification_question",
            to: "clarification_summary"
        ),

        join(DiagramRecord.session, key: "session", from: "diagram", to: "session"),
        join(DiagramRecord.project, key: "project", from: "diagram", to: "project"),
        join(DiagramRecord.prompt, key: "prompt", from: "diagram", to: "prompt"),
        prefetch(DiagramRecord.elements, key: "elements", from: "diagram_element", to: "diagram"),
        join(
            DiagramConnectorRecord.element,
            key: "element",
            from: "diagram_connector",
            to: "diagram_element",
            columns: ["element_uuid"]
        ),
        join(
            DiagramConnectorRecord.targetElement,
            key: "targetElement",
            from: "diagram_connector",
            to: "diagram_element",
            columns: ["target_element_uuid"]
        ),
        join(DiagramDopeEntityRecord.element, key: "element", from: "diagram_dope_entity", to: "diagram_element"),
        join(
            DiagramDopeScopePersistenceLayerRecord.element,
            key: "element",
            from: "diagram_dope_scope_persistence_layer",
            to: "diagram_element"
        ),
        join(DiagramDrawingLayerRecord.element, key: "element", from: "diagram_drawing_layer", to: "diagram_element"),
        join(DiagramDrawingShapeRecord.element, key: "element", from: "diagram_drawing_shape", to: "diagram_element"),
        prefetch(
            DiagramDrawingShapeRecord.vertices,
            key: "vertices",
            from: "diagram_shape_vertex",
            to: "diagram_drawing_shape"
        ),
        join(DiagramDrawingStrokeRecord.element, key: "element", from: "diagram_drawing_stroke", to: "diagram_element"),
        prefetch(
            DiagramDrawingStrokeRecord.vertices,
            key: "vertices",
            from: "diagram_stroke_vertex",
            to: "diagram_drawing_stroke"
        ),
        join(DiagramDrawingTextRecord.element, key: "element", from: "diagram_drawing_text", to: "diagram_element"),
        join(DiagramElementRecord.diagram, key: "diagram", from: "diagram_element", to: "diagram"),
        join(DiagramElementRecord.parent, key: "parent", from: "diagram_element", to: "diagram_element"),
        prefetch(DiagramElementRecord.children, key: "children", from: "diagram_element", to: "diagram_element"),
        join(DiagramShapeVertexRecord.shape, key: "shape", from: "diagram_shape_vertex", to: "diagram_drawing_shape"),
        join(
            DiagramStrokeVertexRecord.stroke,
            key: "stroke",
            from: "diagram_stroke_vertex",
            to: "diagram_drawing_stroke"
        ),
        join(DiagramUmlNodeRecord.element, key: "element", from: "diagram_uml_node", to: "diagram_element"),

        join(DopeCogRecord.scope, key: "scope", from: "dope_cog", to: "dope_scope"),
        prefetch(DopeCogRecord.elements, key: "elements", from: "dope_cog_element", to: "dope_cog"),
        join(DopeCogElementRecord.cog, key: "cog", from: "dope_cog_element", to: "dope_cog"),
        join(DopeCogElementRecord.parent, key: "parent", from: "dope_cog_element", to: "dope_cog_element"),
        prefetch(DopeCogElementRecord.children, key: "children", from: "dope_cog_element", to: "dope_cog_element"),
        join(DopeCogElementRecord.hull, key: "hull", from: "dope_cog_hull", to: "dope_cog_element"),
        join(
            DopeCogElementRecord.persistenceOwner,
            key: "persistenceOwner",
            from: "dope_cog_persistence_owner",
            to: "dope_cog_element"
        ),
        join(DopeCogHullRecord.element, key: "element", from: "dope_cog_hull", to: "dope_cog_element"),
        join(
            DopeCogPersistenceOwnerRecord.element,
            key: "element",
            from: "dope_cog_persistence_owner",
            to: "dope_cog_element"
        ),
        join(DopeElementProvenanceRecord.scope, key: "scope", from: "dope_element_provenance", to: "dope_scope"),
        join(DopePersistenceRecord.scope, key: "scope", from: "dope_persistence", to: "dope_scope"),
        prefetch(
            DopePersistenceRecord.entities,
            key: "entities",
            from: "dope_persistence_entity",
            to: "dope_persistence"
        ),
        prefetch(DopePersistenceRecord.enums, key: "enums", from: "dope_persistence_enum", to: "dope_persistence"),
        join(
            DopePersistenceEntityRecord.dopePersistence,
            key: "dopePersistence",
            from: "dope_persistence_entity",
            to: "dope_persistence"
        ),
        prefetch(
            DopePersistenceEntityRecord.properties,
            key: "properties",
            from: "dope_persistence_entity_property",
            to: "dope_persistence_entity"
        ),
        join(
            DopePersistenceEntityRecord.baseComposable,
            key: "baseComposable",
            from: "dope_persistence_entity",
            to: "dope_persistence_entity"
        ),
        join(
            DopePersistenceEntityPropertyRecord.entity,
            key: "entity",
            from: "dope_persistence_entity_property",
            to: "dope_persistence_entity"
        ),
        join(
            DopePersistenceEntityPropertyRecord.dopeEnum,
            key: "dopeEnum",
            from: "dope_persistence_entity_property",
            to: "dope_persistence_enum"
        ),
        join(
            DopePersistenceEntityPropertyRecord.relationshipTarget,
            key: "relationshipTarget",
            from: "dope_persistence_entity_property",
            to: "dope_persistence_entity_property",
            columns: ["relationship_target_uuid"]
        ),
        join(
            DopePersistenceEntityPropertyRecord.baseOriginProperty,
            key: "baseOriginProperty",
            from: "dope_persistence_entity_property",
            to: "dope_persistence_entity_property",
            columns: ["base_origin_property_uuid"]
        ),
        join(
            DopePersistenceEnumRecord.dopePersistence,
            key: "dopePersistence",
            from: "dope_persistence_enum",
            to: "dope_persistence"
        ),
        prefetch(
            DopePersistenceEnumRecord.options,
            key: "options",
            from: "dope_persistence_enum_option",
            to: "dope_persistence_enum"
        ),
        join(
            DopePersistenceEnumOptionRecord.dopeEnum,
            key: "dopeEnum",
            from: "dope_persistence_enum_option",
            to: "dope_persistence_enum"
        ),
        join(DopeScopeRecord.project, key: "project", from: "dope_scope", to: "project"),
        join(DopeScopeRecord.instance, key: "instance", from: "dope_scope", to: "instance"),
        join(DopeScopeRecord.session, key: "session", from: "dope_scope", to: "session"),
        join(DopeScopeRecord.prompt, key: "prompt", from: "dope_scope", to: "prompt"),
        prefetch(DopeScopeRecord.persistences, key: "persistences", from: "dope_persistence", to: "dope_scope"),
        prefetch(DopeScopeRecord.cogs, key: "cogs", from: "dope_cog", to: "dope_scope"),
        prefetch(DopeScopeRecord.provenance, key: "provenance", from: "dope_element_provenance", to: "dope_scope"),

        join(InstanceActiveKbiteRecord.kbite, key: "kbite", from: "instance_active_kbite", to: "kbite"),
        join(InstanceActiveKbiteRecord.instance, key: "instance", from: "instance_active_kbite", to: "instance"),
        prefetch(KbiteRecord.resources, key: "resources", from: "kbite_resource", to: "kbite"),
        prefetch(KbiteRecord.keywordJunctions, key: "keywordJunctions", from: "kbite_keyword_junction", to: "kbite"),
        prefetch(KbiteRecord.keywords, key: "keywords", from: "kbite_keyword_junction", to: "keyword"),
        prefetch(KbiteRecord.projectActivations, key: "projectActivations", from: "project_active_kbite", to: "kbite"),
        prefetch(
            KbiteRecord.instanceActivations,
            key: "instanceActivations",
            from: "instance_active_kbite",
            to: "kbite"
        ),
        prefetch(KbiteRecord.sessionActivations, key: "sessionActivations", from: "session_active_kbite", to: "kbite"),
        prefetch(KbiteRecord.promptActivations, key: "promptActivations", from: "prompt_active_kbite", to: "kbite"),
        join(KbiteKeywordJunctionRecord.kbite, key: "kbite", from: "kbite_keyword_junction", to: "kbite"),
        join(KbiteKeywordJunctionRecord.keyword, key: "keyword", from: "kbite_keyword_junction", to: "keyword"),
        join(KbiteResourceRecord.kbite, key: "kbite", from: "kbite_resource", to: "kbite"),
        prefetch(KbiteResourceRecord.files, key: "files", from: "kbite_resource_file", to: "kbite_resource"),
        join(KbiteResourceFileRecord.resource, key: "resource", from: "kbite_resource_file", to: "kbite_resource"),
        prefetch(
            KbiteResourceFileRecord.keywordJunctions,
            key: "keywordJunctions",
            from: "resource_file_keyword_junction",
            to: "kbite_resource_file"
        ),
        prefetch(
            KbiteResourceFileRecord.keywords,
            key: "keywords",
            from: "resource_file_keyword_junction",
            to: "keyword"
        ),
        join(ProjectActiveKbiteRecord.kbite, key: "kbite", from: "project_active_kbite", to: "kbite"),
        join(ProjectActiveKbiteRecord.project, key: "project", from: "project_active_kbite", to: "project"),
        join(PromptActiveKbiteRecord.kbite, key: "kbite", from: "prompt_active_kbite", to: "kbite"),
        join(PromptActiveKbiteRecord.prompt, key: "prompt", from: "prompt_active_kbite", to: "prompt"),
        join(
            ResourceFileKeywordJunctionRecord.file,
            key: "file",
            from: "resource_file_keyword_junction",
            to: "kbite_resource_file"
        ),
        join(
            ResourceFileKeywordJunctionRecord.keyword,
            key: "keyword",
            from: "resource_file_keyword_junction",
            to: "keyword"
        ),
        join(SessionActiveKbiteRecord.kbite, key: "kbite", from: "session_active_kbite", to: "kbite"),
        join(SessionActiveKbiteRecord.session, key: "session", from: "session_active_kbite", to: "session"),

        join(ProjectTestLockRecord.project, key: "project", from: "project_test_lock", to: "project"),
        join(ProjectTestLockRecord.heldByRun, key: "heldByRun", from: "project_test_lock", to: "test_run"),
        join(ProjectTestLockRecord.targetInstance, key: "targetInstance", from: "project_test_lock", to: "instance"),
        join(TestRunRecord.project, key: "project", from: "test_run", to: "project"),
        join(TestRunRecord.instance, key: "instance", from: "test_run", to: "instance"),
        join(TestRunRecord.session, key: "session", from: "test_run", to: "session"),
        join(TestRunRecord.lock, key: "lock", from: "project_test_lock", to: "test_run"),

        join(InstanceRecord.project, key: "project", from: "instance", to: "project"),
        prefetch(InstanceRecord.sessions, key: "sessions", from: "session", to: "instance"),
        prefetch(InstanceRecord.activeKbites, key: "activeKbites", from: "instance_active_kbite", to: "kbite"),
        prefetch(ProjectRecord.instances, key: "instances", from: "instance", to: "project"),
        prefetch(ProjectRecord.activeKbites, key: "activeKbites", from: "project_active_kbite", to: "kbite"),
        prefetch(ProjectRecord.diagrams, key: "diagrams", from: "diagram", to: "project"),
        prefetch(ProjectRecord.dopeScopes, key: "dopeScopes", from: "dope_scope", to: "project"),
        join(PromptRecord.session, key: "session", from: "prompt", to: "session"),
        prefetch(PromptRecord.artifacts, key: "artifacts", from: "prompt_artifact", to: "prompt"),
        prefetch(PromptRecord.activations, key: "activations", from: "prompt_activation", to: "prompt"),
        prefetch(
            PromptRecord.qualifiedDiagrams,
            key: "qualifiedDiagrams",
            from: "prompt_qualified_diagram",
            to: "prompt"
        ),
        prefetch(PromptRecord.activeKbites, key: "activeKbites", from: "prompt_active_kbite", to: "kbite"),
        prefetch(PromptRecord.briefings, key: "briefings", from: "agent_briefing", to: "prompt"),
        prefetch(
            PromptRecord.clarificationSummaries,
            key: "clarificationSummaries",
            from: "clarification_summary",
            to: "prompt"
        ),
        prefetch(
            PromptRecord.architectureSummaries,
            key: "architectureSummaries",
            from: "architecture_summary",
            to: "prompt"
        ),
        prefetch(
            PromptRecord.explorationSummaries,
            key: "explorationSummaries",
            from: "exploration_summary",
            to: "prompt"
        ),
        prefetch(PromptRecord.reviewSummaries, key: "reviewSummaries", from: "review_summary", to: "prompt"),
        join(SessionRecord.instance, key: "instance", from: "session", to: "instance"),
        prefetch(SessionRecord.prompts, key: "prompts", from: "prompt", to: "session"),
        prefetch(SessionRecord.activations, key: "activations", from: "prompt_activation", to: "session"),
        prefetch(SessionRecord.files, key: "files", from: "session_file", to: "session"),
        prefetch(SessionRecord.fileChanges, key: "fileChanges", from: "file_change", to: "session"),
        prefetch(SessionRecord.activeKbites, key: "activeKbites", from: "session_active_kbite", to: "kbite"),
        prefetch(SessionRecord.briefings, key: "briefings", from: "agent_briefing", to: "session"),
        prefetch(
            SessionRecord.claudeBindings,
            key: "claudeBindings",
            from: "claude_session_binding",
            to: "session"
        ),
    ]

    /// A composite's canonical request, compiled the way a multi-row fetch
    /// compiles it: `forSingleResult: false`, so a prefetch plans its children.
    private static func composite<C: FetchableRecord>(
        _: C.Type,
        _ label: String,
        request: @escaping @Sendable () -> QueryInterfaceRequest<C>
    ) -> CompositeEntry {
        CompositeEntry(label: label) { db in
            try request().makePreparedRequest(db, forSingleResult: false).statement.sql
        }
    }

    /// A composite whose request decodes a bare scalar rather than a record.
    private static func scalarComposite<V: DatabaseValueConvertible>(
        _ label: String,
        request: @escaping @Sendable () -> QueryInterfaceRequest<V>
    ) -> CompositeEntry {
        CompositeEntry(label: label) { db in
            try request().makePreparedRequest(db, forSingleResult: false).statement.sql
        }
    }

    /// One entry per composite, preparing that composite's canonical request.
    static let composites: [CompositeEntry] = [
        composite(AgentBriefingWithRefs.self, "AgentBriefingWithRefs") { AgentBriefingWithRefs.request() },
        composite(ArchitectureCounts.self, "ArchitectureCounts") { ArchitectureCounts.request(summaryUuid: "a") },
        composite(ArchPersistenceChangeWithFields.self, "ArchPersistenceChangeWithFields") {
            ArchPersistenceChangeWithFields.request()
        },
        composite(CarePackageWithRefs.self, "CarePackageWithRefs") { CarePackageWithRefs.request() },
        composite(ClarificationQuestionWithOptions.self, "ClarificationQuestionWithOptions") {
            ClarificationQuestionWithOptions.request()
        },
        composite(FileChangeWithRanges.self, "FileChangeWithRanges") {
            FileChangeWithRanges.request(relativePath: nil)
        },
        composite(FileChangeWithSessionFile.self, "FileChangeWithSessionFile") {
            FileChangeWithSessionFile.request(toolUseId: "t", sessionUuid: "s", relativePath: "p")
        },
        composite(ReviewSummaryWithFindings.self, "ReviewSummaryWithFindings") { ReviewSummaryWithFindings.request() },
        composite(TouchedPathSummary.self, "TouchedPathSummary") { TouchedPathSummary.request(promptUuid: "p") },

        composite(DiagramOwnerChain.self, "DiagramOwnerChain.forSession") { DiagramOwnerChain.forSession("s") },
        composite(DiagramOwnerChain.self, "DiagramOwnerChain.forPrompt") { DiagramOwnerChain.forPrompt("p") },
        composite(DiagramWithOwner.self, "DiagramWithOwner") { DiagramWithOwner.request() },

        composite(DopeCogWithElements.self, "DopeCogWithElements") { DopeCogWithElements.request() },
        composite(DopeDomainChildPath.self, "DopeDomainChildPath.entities") { DopeDomainChildPath.entities() },
        composite(DopeDomainChildPath.self, "DopeDomainChildPath.enums") { DopeDomainChildPath.enums() },
        composite(DopeDomainChildPath.self, "DopeDomainChildPath.entitiesComposingInside") {
            DopeDomainChildPath.entitiesComposingInside(persistenceUuid: "d")
        },
        composite(DopeDomainGrandchildPath.self, "DopeDomainGrandchildPath.properties") {
            DopeDomainGrandchildPath.properties()
        },
        composite(DopeDomainGrandchildPath.self, "DopeDomainGrandchildPath.options") {
            DopeDomainGrandchildPath.options()
        },
        composite(DopeDomainGrandchildPath.self, "DopeDomainGrandchildPath.propertiesReaching(relationshipTarget)") {
            DopeDomainGrandchildPath.propertiesReaching(
                entityUuid: "e",
                through: DopePersistenceEntityPropertyRecord.relationshipTarget
            )
        },
        composite(DopeDomainGrandchildPath.self, "DopeDomainGrandchildPath.propertiesReaching(baseOriginProperty)") {
            DopeDomainGrandchildPath.propertiesReaching(
                entityUuid: "e",
                through: DopePersistenceEntityPropertyRecord.baseOriginProperty
            )
        },
        composite(DopeDomainGrandchildPath.self, "DopeDomainGrandchildPath.propertiesReachingInto") {
            DopeDomainGrandchildPath.propertiesReachingInto(persistenceUuid: "d")
        },
        composite(DopeDomainGrandchildPath.self, "DopeDomainGrandchildPath.propertiesOriginatingInside") {
            DopeDomainGrandchildPath.propertiesOriginatingInside(persistenceUuid: "d")
        },
        composite(DopeMaterializedOrigin.self, "DopeMaterializedOrigin") {
            DopeMaterializedOrigin.request(entityUuid: "e")
        },
        composite(DopePersistenceCascadeCounts.self, "DopePersistenceCascadeCounts") {
            DopePersistenceCascadeCounts.request(persistenceUuid: "d")
        },
        composite(DopePropertyOrigin.self, "DopePropertyOrigin") { DopePropertyOrigin.request(propertyUuid: "p") },
        composite(DopeScopeLineage.self, "DopeScopeLineage.forSession") { DopeScopeLineage.forSession("s") },
        composite(DopeScopePersistenceCount.self, "DopeScopePersistenceCount") {
            DopeScopePersistenceCount.request(scopeUuid: "s")
        },

        composite(KbiteCounts.self, "KbiteCounts") { KbiteCounts.request(kbiteUuid: "k") },
        scalarComposite("KbiteFileKeywords") { KbiteFileKeywords.request(fileUuid: "f") },
        composite(KbiteResourceWithFiles.self, "KbiteResourceWithFiles") { KbiteResourceWithFiles.request() },
        composite(KbiteWithResources.self, "KbiteWithResources") { KbiteWithResources.request(code: "c") },

        composite(ArchitectureReport.self, "ArchitectureReport") { ArchitectureReport.request(sessionUuid: nil) },
        composite(ArchitectureReport.self, "ArchitectureReport(sessionUuid:)") {
            ArchitectureReport.request(sessionUuid: "s")
        },
        composite(ClarificationReport.self, "ClarificationReport") { ClarificationReport.request(sessionUuid: nil) },
        composite(ClarificationReport.self, "ClarificationReport(sessionUuid:)") {
            ClarificationReport.request(sessionUuid: "s")
        },
        composite(ExplorationReport.self, "ExplorationReport") { ExplorationReport.request(sessionUuid: nil) },
        composite(ExplorationReport.self, "ExplorationReport(sessionUuid:)") {
            ExplorationReport.request(sessionUuid: "s")
        },
        composite(ReviewReport.self, "ReviewReport") { ReviewReport.request(sessionUuid: nil) },
        composite(ReviewReport.self, "ReviewReport(sessionUuid:)") { ReviewReport.request(sessionUuid: "s") },
        composite(ChangeRollup.self, "ChangeRollup(sessionUuid:)") { ChangeRollup.request(sessionUuid: "s") },
        composite(ChangeRollup.self, "ChangeRollup(promptUuid:)") { ChangeRollup.request(promptUuid: "p") },
        composite(PromptChangeRollup.self, "PromptChangeRollup") { PromptChangeRollup.request(sessionUuid: "s") },
        composite(PromptSummary.self, "PromptSummary") { PromptSummary.request(sessionUuid: nil) },
        composite(PromptSummary.self, "PromptSummary(sessionUuid:)") { PromptSummary.request(sessionUuid: "s") },
        composite(SessionLineage.self, "SessionLineage") { SessionLineage.request(sessionUuid: "s") },
        composite(SessionSummary.self, "SessionSummary") { SessionSummary.request() },
        composite(SessionSummary.self, "SessionSummary(instance:projectUuid:)") {
            SessionSummary.request(instance: TableAlias<InstanceRecord>(), projectUuid: "p")
        },
        composite(SessionWithActivations.self, "SessionWithActivations") { SessionWithActivations.request() },
    ]
}
