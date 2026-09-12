import XCTest
import GRDB
@testable import GMCCDaemonKit

/// Keeps the read-side Record structs honest against the live schema: for
/// every record, synthesize a full row from PRAGMA table_info of a freshly
/// migrated db and decode it. A record property with no matching column (or a
/// column type drift) fails here instead of at some later fetch site.
final class RecordSchemaTests: XCTestCase {

    func testRecordsDecodeFromMigratedSchema() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue)

        let decoders: [String: (Row) throws -> Any] = [
            "agent_briefing": { try AgentBriefingRecord(row: $0) },
            "architecture_general_change": { try ArchitectureGeneralChangeRecord(row: $0) },
            "architecture_persistence_change": { try ArchitecturePersistenceChangeRecord(row: $0) },
            "architecture_persistence_field_change": { try ArchitecturePersistenceFieldChangeRecord(row: $0) },
            "architecture_summary": { try ArchitectureSummaryRecord(row: $0) },
            "agent_briefing_dope_persistence": { try AgentBriefingDopePersistenceRecord(row: $0) },
            "agent_briefing_dope_kbite": { try AgentBriefingDopeKbiteRecord(row: $0) },
            "agent_session_file_change": { try AgentSessionFileChangeRecord(row: $0) },
            "architecture_option": { try ArchitectureOptionRecord(row: $0) },
            "bot_workflow": { try BotWorkflowRecord(row: $0) },
            "care_package": { try CarePackageRecord(row: $0) },
            "care_package_dope_ref": { try CarePackageDopeRefRecord(row: $0) },
            "care_package_kbite_ref": { try CarePackageKbiteRefRecord(row: $0) },
            "care_package_exploration_ref": { try CarePackageExplorationRefRecord(row: $0) },
            "clarification_summary": { try ClarificationSummaryRecord(row: $0) },
            "internal_clarification_note": { try InternalClarificationNoteRecord(row: $0) },
            "user_clarification_question": { try UserClarificationQuestionRecord(row: $0) },
            "user_clarification_option": { try UserClarificationOptionRecord(row: $0) },
            "user_clarification_answer": { try UserClarificationAnswerRecord(row: $0) },
            "daemon_config": { try DaemonConfigRecord(row: $0) },
            "daemon_event": { try DaemonEventRecord(row: $0) },
            "diagram": { try DiagramRecord(row: $0) },
            "diagram_connector": { try DiagramConnectorRecord(row: $0) },
            "diagram_dope_entity": { try DiagramDopeEntityRecord(row: $0) },
            "diagram_dope_scope_persistence_layer": { try DiagramDopeScopePersistenceLayerRecord(row: $0) },
            "diagram_drawing_layer": { try DiagramDrawingLayerRecord(row: $0) },
            "diagram_drawing_shape": { try DiagramDrawingShapeRecord(row: $0) },
            "diagram_drawing_stroke": { try DiagramDrawingStrokeRecord(row: $0) },
            "diagram_drawing_text": { try DiagramDrawingTextRecord(row: $0) },
            "diagram_element": { try DiagramElementRecord(row: $0) },
            "diagram_shape_vertex": { try DiagramShapeVertexRecord(row: $0) },
            "diagram_stroke_vertex": { try DiagramStrokeVertexRecord(row: $0) },
            "diagram_uml_node": { try DiagramUmlNodeRecord(row: $0) },
            "dope_cog": { try DopeCogRecord(row: $0) },
            "dope_cog_element": { try DopeCogElementRecord(row: $0) },
            "dope_cog_hull": { try DopeCogHullRecord(row: $0) },
            "dope_cog_persistence_owner": { try DopeCogPersistenceOwnerRecord(row: $0) },
            "dope_element_provenance": { try DopeElementProvenanceRecord(row: $0) },
            "dope_persistence": { try DopePersistenceRecord(row: $0) },
            "dope_persistence_entity": { try DopePersistenceEntityRecord(row: $0) },
            "dope_persistence_entity_property": { try DopePersistenceEntityPropertyRecord(row: $0) },
            "dope_persistence_enum": { try DopePersistenceEnumRecord(row: $0) },
            "dope_persistence_enum_option": { try DopePersistenceEnumOptionRecord(row: $0) },
            "dope_scope": { try DopeScopeRecord(row: $0) },
            "exploration_finding": { try ExplorationFindingRecord(row: $0) },
            "exploration_summary": { try ExplorationSummaryRecord(row: $0) },
            "file_change": { try FileChangeRecord(row: $0) },
            "file_change_range": { try FileChangeRangeRecord(row: $0) },
            "instance": { try InstanceRecord(row: $0) },
            "instance_active_kbite": { try InstanceActiveKbiteRecord(row: $0) },
            "kbite": { try KbiteRecord(row: $0) },
            "kbite_keyword_junction": { try KbiteKeywordJunctionRecord(row: $0) },
            "kbite_resource": { try KbiteResourceRecord(row: $0) },
            "kbite_resource_file": { try KbiteResourceFileRecord(row: $0) },
            "keyword": { try KeywordRecord(row: $0) },
            "project": { try ProjectRecord(row: $0) },
            "project_active_kbite": { try ProjectActiveKbiteRecord(row: $0) },
            "prompt": { try PromptRecord(row: $0) },
            "prompt_activation": { try PromptActivationRecord(row: $0) },
            "prompt_active_kbite": { try PromptActiveKbiteRecord(row: $0) },
            "prompt_artifact": { try PromptArtifactRecord(row: $0) },
            "prompt_qualified_diagram": { try PromptQualifiedDiagramRecord(row: $0) },
            "resource_file_keyword_junction": { try ResourceFileKeywordJunctionRecord(row: $0) },
            "review_finding": { try ReviewFindingRecord(row: $0) },
            "review_summary": { try ReviewSummaryRecord(row: $0) },
            "session": { try SessionRecord(row: $0) },
            "session_active_kbite": { try SessionActiveKbiteRecord(row: $0) },
            "session_file": { try SessionFileRecord(row: $0) }
        ]

        try queue.read { db in
            for (table, decode) in decoders.sorted(by: { $0.key < $1.key }) {
                let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                XCTAssertFalse(cols.isEmpty, "table \(table) missing from migrated schema")
                var dict: [String: (any DatabaseValueConvertible)?] = [:]
                for c in cols {
                    let name: String = c["name"]
                    let type: String = c["type"]
                    switch type.uppercased() {
                    case "INTEGER": dict[name] = Int64(0)
                    case "REAL": dict[name] = 0.0
                    case "BLOB": dict[name] = Data()
                    default: dict[name] = "x"
                    }
                }
                XCTAssertNoThrow(try decode(Row(dict)), "record for \(table) failed to decode a full schema row")

                // NULL pass: every nullable column carries NULL, so a
                // non-optional record property over a nullable column fails
                // HERE instead of at some later real fetch. INTEGER PRIMARY
                // KEY (rowid alias) is notnull=0 in table_info but can never
                // be NULL in a real row, so it keeps its value.
                var nullable: [String: (any DatabaseValueConvertible)?] = dict
                for c in cols {
                    let name: String = c["name"]
                    let notnull: Int64 = c["notnull"]
                    let pk: Int64 = c["pk"]
                    if notnull == 0 && pk == 0 {
                        nullable.updateValue(nil, forKey: name)
                    }
                }
                XCTAssertNoThrow(try decode(Row(nullable)), "record for \(table) failed to decode a NULL-heavy row (non-optional property over a nullable column?)")
            }
        }
    }
}
