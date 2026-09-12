import Foundation
import GRDB

/// Everything a repository is allowed to hold: the ambient transaction's
/// `Database`, and the shared write primitives.
///
/// Deliberately NOT a Store. There is no `dbQueue` reachable from here and no
/// public verb, so nesting a transaction is not expressible — and GRDB 7 TRAPS
/// on re-entrant `dbQueue.write` (DatabaseQueue.swift, "Database methods are
/// not reentrant"), killing the daemon process rather than returning an error.
/// Before this protocol, nothing but a doc comment repeated in 27 repositories
/// stood between any of them and that trap.
///
/// The sibling accessors below exist so a cross-domain call is a CALL rather
/// than a construction. Previously `DiagramRepository` reaching dope logic went
/// DiagramRepository → Store (thin forward) → new DopeRepository → body, with
/// Store acting as a service locator in the middle of a call that had nothing
/// to do with it. Now it names the owner directly, which is also more honest:
/// `clarification.touchSessionForPrompt(...)` tells you the body lives in
/// ClarificationRepository, which the old `store.` spelling actively hid.
///
/// Adding a repository is one line here rather than a new spelling at N call
/// sites. `EventRepository` deliberately does not conform — it holds only `db`
/// and needs no core.
protocol RepositoryContext {
    var db: Database { get }
    var core: StoreCore { get }
}

extension RepositoryContext {
    var agentRegistration: AgentRegistrationRepository { .init(db: db, core: core) }
    var architecture: ArchitectureRepository { .init(db: db, core: core) }
    var artifact: ArtifactRepository { .init(db: db, core: core) }
    var briefing: BriefingRepository { .init(db: db, core: core) }
    var catalogSearch: CatalogSearchRepository { .init(db: db, core: core) }
    var clarification: ClarificationRepository { .init(db: db, core: core) }
    var claudeSessionBinding: ClaudeSessionBindingRepository { .init(db: db, core: core) }
    var config: ConfigRepository { .init(db: db, core: core) }
    var context: ContextRepository { .init(db: db, core: core) }
    var diagram: DiagramRepository { .init(db: db, core: core) }
    var diagramStudio: DiagramStudioRepository { .init(db: db, core: core) }
    var dopeCog: DopeCogRepository { .init(db: db, core: core) }
    var dopePromote: DopePromoteRepository { .init(db: db, core: core) }
    var dopeProvenance: DopeProvenanceRepository { .init(db: db, core: core) }
    var dope: DopeRepository { .init(db: db, core: core) }
    var dopeSearch: DopeSearchRepository { .init(db: db, core: core) }
    var exploration: ExplorationRepository { .init(db: db, core: core) }
    var fileChange: FileChangeRepository { .init(db: db, core: core) }
    var findingRank: FindingRankRepository { .init(db: db, core: core) }
    var gitState: GitStateRepository { .init(db: db, core: core) }
    var kbiteArchive: KbiteArchiveRepository { .init(db: db, core: core) }
    var kbite: KbiteRepository { .init(db: db, core: core) }
    var kbiteResource: KbiteResourceRepository { .init(db: db, core: core) }
    var listing: ListingRepository { .init(db: db, core: core) }
    var project: ProjectRepository { .init(db: db, core: core) }
    var promptDiagram: PromptDiagramRepository { .init(db: db, core: core) }
    var prompt: PromptRepository { .init(db: db, core: core) }
    var review: ReviewRepository { .init(db: db, core: core) }
    var search: SearchRepository { .init(db: db, core: core) }
    var session: SessionRepository { .init(db: db, core: core) }
}
