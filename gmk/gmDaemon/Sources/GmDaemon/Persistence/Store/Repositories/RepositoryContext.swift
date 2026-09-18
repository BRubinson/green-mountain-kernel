import Foundation
import GRDB
import GmDaemonSdk

/// Everything a repository is allowed to hold: the ambient transaction's
/// `Database`, and the shared write primitives.
/// Deliberately NOT a Store. No `dbQueue` is reachable from here and no public
/// verb, so nesting a transaction is not expressible — and GRDB 7 TRAPS on a
/// re-entrant `dbQueue.write`, killing the daemon rather than returning an
/// error. The sibling accessors below make a cross-domain call a CALL rather
/// than a construction, naming the owning repository directly.
/// `EventRepository` does not conform: it holds only `db` and needs no core.
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
    var testRun: TestRunRepository { .init(db: db, core: core) }
}
