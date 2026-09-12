import Foundation
import Network
import GMCCDaemonKit

/// What the connection should do after writing a handler's response.
enum PostAction {
    case none
    /// Stop the whole daemon after the response is flushed (gm daemon stop,
    /// or a protocol-mismatch self-exit).
    case shutdown
}

struct HandlerResult {
    /// Empty line = the handler already sent everything itself (SUBSCRIBE
    /// sends ack + replay directly); the connection skips the write.
    let line: Data
    let postAction: PostAction

    init(line: Data, postAction: PostAction = .none) {
        self.line = line
        self.postAction = postAction
    }
}

/// NWListener accept loop + NDJSON framing. All state is confined to `queue`.
///
/// Concurrency invariant (load-bearing): every dispatch turn, every db write,
/// and every event-sink firing happens synchronously on this ONE serial queue.
/// That is what makes SUBSCRIBE's replay-then-register step gapless and
/// duplicate-free — no commit can interleave with it.
final class Server: @unchecked Sendable {
    private let listener: NWListener
    private let store: Store
    private let queue = DispatchQueue(label: "gmcc.daemon.server")
    private let startedAt = Store.isoNow()
    private let startedDate = Date()
    private var connections: [ObjectIdentifier: ClientConnection] = [:]
    private var subscribers: [ObjectIdentifier] = []
    /// Non-nil only inside performShutdown: broadcast tracks the DAEMON_STOP
    /// goodbye sends so exit(0) waits for delivery instead of racing it.
    private var goodbyeGroup: DispatchGroup?
    /// A3/A8: owns both filesystem watchers and the one recompute path.
    /// Built in start() (needs a fully initialised self), rebuilt via the
    /// post-commit event sink on CONFIG_SET / CREATE_INSTANCE.
    private var supervisor: WatcherSupervisor?
    private var rebuildPending = false
    /// A8 dedupe: instanceUuid → "state|branch" last emitted. Server-queue-
    /// confined; only a genuine head change broadcasts.
    private var lastCheckoutState: [String: String] = [:]

    init(store: Store) throws {
        self.store = store
        // A leftover socket inode from a previous run makes bind fail with
        // "Address already in use" — always unlink first.
        unlink(Paths.socket.path)
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.unix(path: Paths.socket.path)
        self.listener = try NWListener(using: params)
        // Post-commit fan-out: EVERY daemon_event kind streams to subscribers.
        // NOTE ON QUEUES: GRDB fires afterNextTransaction(onCommit:) on the
        // DATABASE's serialized queue, not this one — mutual exclusion holds
        // only because the server-queue turn that issued the write is blocked
        // inside dbQueue.write for the duration. Do NOT add a
        // dispatchPrecondition(.onQueue(queue)) here; it would trap.
        store.eventSink = { [weak self] event in
            self?.broadcast(event.notification)
            self?.watchedStateMayHaveChanged(event.kind)
        }
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let client = ClientConnection(connection: connection, server: self)
            self.queue.async {
                self.connections[ObjectIdentifier(client)] = client
                client.start(on: self.queue)
            }
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                FileHandle.standardError.write(Data("[gmcc_daemon] listener failed: \(error)\n".utf8))
                exit(1)
            }
        }
        listener.start(queue: queue)
        // A3/A8: watcher stack — deliver closures hop onto the server queue
        // per the lane contract; the supervisor's initial rebuild starts both
        // watchers from committed config + instance rows.
        let memory = MemoryWatcher { [weak self] storagePath in
            self?.promptMemoryChanged(storagePath: storagePath)
        }
        let checkout = CheckoutWatcher { [weak self] instanceUuid, repoRoot in
            self?.checkoutChanged(instanceUuid: instanceUuid, repoRoot: repoRoot)
        }
        supervisor = WatcherSupervisor(store: store, memory: memory, checkout: checkout)
        queue.async { self.supervisor?.rebuild() }
    }

    /// The sink fires on the DATABASE's queue while the issuing write turn is
    /// still unwinding — never read the db here; hop onto the server queue.
    /// Two committed kinds signal the watched set may have changed: the config
    /// write and the instance creation. Coalesced so a burst produces one
    /// recompute; both downstream pushes are idempotent anyway.
    private func watchedStateMayHaveChanged(_ kind: String) {
        guard kind == DaemonEventKind.configSet.rawValue
            || kind == DaemonEventKind.createInstance.rawValue else { return }
        queue.async {
            guard !self.rebuildPending else { return }
            self.rebuildPending = true
            self.queue.async {
                self.rebuildPending = false
                self.supervisor?.rebuild()
            }
        }
    }

    /// A8 delivery — the exact shape of promptMemoryChanged: hops onto the
    /// server queue, resolves the head state there (the same resolver the
    /// poll messages use, so push and poll can never disagree), dedupes
    /// against the last-emitted cache, and broadcasts an EPHEMERAL
    /// notification (id 0, no daemon_event row — a replayed stale branch
    /// presented as current would be worse than no event).
    func checkoutChanged(instanceUuid: String, repoRoot: String) {
        queue.async {
            let (state, code, branch) = Store.headSummary(repoRoot: repoRoot)
            let fingerprint = "\(state)|\(branch ?? "")"
            guard self.lastCheckoutState[instanceUuid] != fingerprint else { return }
            self.lastCheckoutState[instanceUuid] = fingerprint
            var payload: [String: Any] = ["instance_uuid": instanceUuid, "head_state": state]
            payload["current_branch"] = branch ?? NSNull()
            payload["current_session_code"] = code ?? NSNull()
            self.broadcast(EventNotification(
                id: 0,
                kind: DaemonEventKind.checkoutChange.rawValue,
                subjectUuid: instanceUuid,
                payload: Store.jsonPayload(payload),
                createdAt: Store.isoNow()))
        }
    }

    func remove(_ client: ClientConnection) {
        queue.async {
            let key = ObjectIdentifier(client)
            self.connections.removeValue(forKey: key)
            self.subscribers.removeAll { $0 == key }
        }
    }

    /// Item 8 delivery: called by MemoryWatcher's `deliver` closure (which
    /// runs on the lane) — hops onto the server queue, resolves the prompt by
    /// its storage path there, and broadcasts an EPHEMERAL notification.
    /// id 0 marks it as never-a-replay-cursor; no daemon_event row is written,
    /// so the lane's no-db-writes contract holds and the event-sink ordering
    /// invariant is untouched.
    func promptMemoryChanged(storagePath: String) {
        queue.async {
            guard let promptUuid = try? self.store.promptUuid(byStoragePath: storagePath) else {
                return
            }
            self.broadcast(EventNotification(
                id: 0,
                kind: DaemonEventKind.promptMemoryChange.rawValue,
                subjectUuid: promptUuid,
                payload: "{\"ckfs_relative_storage_path\":\(Self.jsonString(storagePath))}",
                createdAt: Store.isoNow()))
        }
    }

    /// JSON-encode one string safely (paths can carry quotes/backslashes).
    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode([value]),
              let text = String(data: data, encoding: .utf8),
              text.count >= 2 else { return "\"\"" }
        return String(text.dropFirst().dropLast())
    }

    /// Push an EVENT line to every subscriber.
    func broadcast(_ notification: EventNotification) {
        let envelope = ResponseEnvelope<EventNotification>(
            type: .event, requestId: "", ok: true, payload: notification)
        guard let line = try? NDJSON.encodeLine(envelope) else { return }
        let group = goodbyeGroup
        for key in subscribers {
            if let group {
                group.enter()
                connections[key]?.send(line) { group.leave() }
            } else {
                connections[key]?.send(line)
            }
        }
    }

    /// SHUTDOWN contract: drain in-flight work, checkpoint the WAL, remove
    /// pidfile + socket, exit 0. Always hops onto the server queue so signal
    /// handlers (main queue) and connection callbacks take the same clean
    /// path, and the DAEMON_STOP goodbye event broadcasts to subscribers
    /// before EOF. "Drain" is structural: this runs as one serial-queue turn,
    /// so every previously received line has already completed.
    func shutdown() {
        queue.async { self.performShutdown() }
    }

    private func performShutdown() {
        listener.cancel()
        // The DAEMON_STOP goodbye is subscribers' clean-termination signal —
        // gate exit(0) on its send completions (with a timeout fallback)
        // instead of racing the async sends.
        let group = DispatchGroup()
        goodbyeGroup = group
        try? store.recordDaemonStop()   // sink → subscribers see DAEMON_STOP, then EOF
        goodbyeGroup = nil
        try? store.checkpointTruncate()
        try? store.closeDatabase()
        unlink(Paths.socket.path)
        unlink(Paths.pidfile.path)
        // Completions fire on this queue, so notify (never wait) here.
        group.notify(queue: queue) { exit(0) }
        queue.asyncAfter(deadline: .now() + 1.0) { exit(0) }
    }

    // MARK: - Dispatch

    /// Route one decoded NDJSON line. Handshake enforcement happens before
    /// payload decoding and is DIRECTIONAL: a newer client means THIS daemon
    /// is the stale binary — reply, then self-exit so the client's retry
    /// autostarts the fresh build. An older client (a pinned-Kit GMVibes) is
    /// rejected but the daemon stays up — it must never be kill-loopable.
    func dispatch(line: Data, from client: ClientConnection) -> HandlerResult {
        // Version-FIRST: the pre-head keeps `type` raw so a newer client
        // invoking a message name this build doesn't know still reaches the
        // mismatch branch (and its directional self-exit) instead of dying as
        // an undecodable envelope.
        let rawHead: RawEnvelopeHead
        do {
            rawHead = try NDJSON.decode(RawEnvelopeHead.self, from: line)
        } catch {
            return errorResult(
                type: .error, requestId: "",
                payload: ErrorPayload(code: .badRequest, message: "undecodable envelope: \(error)"))
        }

        guard rawHead.protocolVersion == GMCCWireProtocol.version else {
            let clientNewer = rawHead.protocolVersion > GMCCWireProtocol.version
            let message = clientNewer
                ? "daemon speaks v\(GMCCWireProtocol.version), client spoke newer v\(rawHead.protocolVersion) — daemon exiting for restart"
                : "daemon speaks v\(GMCCWireProtocol.version), client spoke older v\(rawHead.protocolVersion) — rejected, daemon stays up"
            let result = errorResult(
                type: rawHead.type ?? .error, requestId: rawHead.requestId ?? "",
                payload: ErrorPayload(
                    code: .protocolMismatch, message: message,
                    daemonProtocolVersion: GMCCWireProtocol.version))
            return HandlerResult(line: result.line, postAction: clientNewer ? .shutdown : .none)
        }

        guard let resolvedType = rawHead.type else {
            return errorResult(
                type: .error, requestId: rawHead.requestId ?? "",
                payload: ErrorPayload(
                    code: .unknownType,
                    message: "unknown message type \(rawHead.typeRaw) at matching protocol v\(GMCCWireProtocol.version)"))
        }
        let head = EnvelopeHead(
            protocolVersion: rawHead.protocolVersion,
            type: resolvedType,
            requestId: rawHead.requestId ?? "")

        do {
            switch head.type {
            case .hello:
                if let hello = try? NDJSON.decode(RequestEnvelope<Hello>.self, from: line) {
                    print("[\(Store.isoNow())] client connected: \(hello.payload.clientName) pid \(hello.payload.pid)")
                    fflush(stdout)
                }
                let ack = HelloAck(daemonPid: getpid(), protocolVersion: GMCCWireProtocol.version)
                let envelope = ResponseEnvelope<HelloAck>(
                    type: .hello, requestId: head.requestId, ok: true, payload: ack)
                return HandlerResult(line: try NDJSON.encodeLine(envelope))

            case .ping:
                return try PingHandler.handle(head: head, startedAt: startedAt, startedDate: startedDate)
            case .status:
                return try StatusHandler.handle(
                    head: head, store: store, startedAt: startedAt, startedDate: startedDate)
            case .shutdown:
                return try ShutdownHandler.handle(head: head)
            case .backup:
                return try BackupHandler.handle(line: line, head: head, store: store)

            case .subscribe:
                return try handleSubscribe(line: line, head: head, client: client)

            case .contextEnsure:
                return try ContextEnsureHandler.handle(line: line, head: head, store: store)
            case .contextGet:
                return try ContextGetHandler.handle(line: line, head: head, store: store)

            case .projectList:
                return try ProjectListHandler.handle(line: line, head: head, store: store)
            case .projectUpdate:
                return try ProjectUpdateHandler.handle(line: line, head: head, store: store)
            case .instanceList:
                return try InstanceListHandler.handle(line: line, head: head, store: store)
            case .sessionList:
                return try SessionListHandler.handle(line: line, head: head, store: store)
            case .catalogSearch:
                return try CatalogSearchHandler.handle(line: line, head: head, store: store)
            case .search:
                return try SearchHandler.handle(line: line, head: head, store: store)

            case .sessionGet:
                return try SessionGetHandler.handle(line: line, head: head, store: store)
            case .sessionUpdate:
                return try SessionUpdateHandler.handle(line: line, head: head, store: store)

            case .promptCreate:
                return try PromptCreateHandler.handle(line: line, head: head, store: store)
            case .promptList:
                return try PromptListHandler.handle(line: line, head: head, store: store)
            case .promptGet:
                return try PromptGetHandler.handle(line: line, head: head, store: store)
            case .promptUpdateContent:
                return try PromptUpdateContentHandler.handle(line: line, head: head, store: store)
            case .promptSetStatus:
                return try PromptSetStatusHandler.handle(line: line, head: head, store: store)
            case .promptStart:
                return try PromptStartHandler.handle(line: line, head: head, store: store)
            case .promptResume:
                return try PromptResumeHandler.handle(line: line, head: head, store: store)
            case .botNext:
                return try BotNextHandler.handle(line: line, head: head, store: store)
            case .botGet:
                return try BotGetHandler.handle(line: line, head: head, store: store)
            case .agentRegister:
                return try AgentRegisterHandler.handle(line: line, head: head, store: store)

            case .artifactAdd:
                return try ArtifactAddHandler.handle(line: line, head: head, store: store)
            case .artifactList:
                return try ArtifactListHandler.handle(line: line, head: head, store: store)

            case .promptDiagramQualify:
                return try PromptDiagramQualifyHandler.handle(line: line, head: head, store: store)
            case .promptDiagramGet:
                return try PromptDiagramGetHandler.handle(line: line, head: head, store: store)
            case .promptDiagramList:
                return try PromptDiagramListHandler.handle(line: line, head: head, store: store)

            case .fileChangeAdd:
                return try FileChangeHandler.handle(line: line, head: head, store: store)
            case .fileChangeList:
                return try FileChangeListHandler.handle(line: line, head: head, store: store)

            case .kbiteList:
                return try KbiteListHandler.handle(line: line, head: head, store: store)
            case .kbiteAdd:
                return try KbiteAddHandler.handle(line: line, head: head, store: store)
            case .kbiteRemove:
                return try KbiteRemoveHandler.handle(line: line, head: head, store: store)
            case .kbiteMawOpen:
                return try KbiteMawOpenHandler.handle(line: line, head: head)
            case .kbiteDigest:
                return try KbiteDigestHandler.handle(line: line, head: head, store: store)
            case .kbiteGet:
                return try KbiteGetHandler.handle(line: line, head: head, store: store)
            case .kbiteFileGet:
                return try KbiteFileGetHandler.handle(line: line, head: head, store: store)
            case .kbiteSearch:
                return try KbiteSearchHandler.handle(line: line, head: head, store: store)
            case .kbiteKeywordTag:
                return try KbiteKeywordTagHandler.handle(line: line, head: head, store: store)
            case .kbiteExport:
                return try KbiteExportHandler.handle(line: line, head: head, store: store)
            case .kbiteImport:
                return try KbiteImportHandler.handle(line: line, head: head, store: store)
            case .kbiteDelete:
                return try KbiteDeleteHandler.handle(line: line, head: head, store: store)

            case .clarifyOpen:
                return try ClarifyOpenHandler.handle(line: line, head: head, store: store)
            case .clarifyQuestionAdd:
                return try ClarifyQuestionAddHandler.handle(line: line, head: head, store: store)
            case .clarifyNoteAdd:
                return try ClarifyNoteAddHandler.handle(line: line, head: head, store: store)
            case .clarifySeal:
                return try ClarifySealHandler.handle(line: line, head: head, store: store)
            case .clarifyAnswer:
                return try ClarifyAnswerHandler.handle(line: line, head: head, store: store)
            case .clarifyReopen:
                return try ClarifyReopenHandler.handle(line: line, head: head, store: store)
            case .clarifyFinalize:
                return try ClarifyFinalizeHandler.handle(line: line, head: head, store: store)
            case .clarifyGet:
                return try ClarifyGetHandler.handle(line: line, head: head, store: store)

            case .carePackageOpen:
                return try CarePackageOpenHandler.handle(line: line, head: head, store: store)
            case .carePackageRefAdd:
                return try CarePackageRefAddHandler.handle(line: line, head: head, store: store)
            case .carePackageComplete:
                return try CarePackageCompleteHandler.handle(line: line, head: head, store: store)
            case .carePackageGet:
                return try CarePackageGetHandler.handle(line: line, head: head, store: store)

            case .archOpen:
                return try ArchOpenHandler.handle(line: line, head: head, store: store)
            case .archSummarize:
                return try ArchSummarizeHandler.handle(line: line, head: head, store: store)
            case .archPersistAdd:
                return try ArchPersistAddHandler.handle(line: line, head: head, store: store)
            case .archFieldAdd:
                return try ArchFieldAddHandler.handle(line: line, head: head, store: store)
            case .archGeneralAdd:
                return try ArchGeneralAddHandler.handle(line: line, head: head, store: store)
            case .archPropose:
                return try ArchProposeHandler.handle(line: line, head: head, store: store)
            case .archApprove:
                return try ArchApproveHandler.handle(line: line, head: head, store: store)
            case .archRevise:
                return try ArchReviseHandler.handle(line: line, head: head, store: store)
            case .archGet:
                return try ArchGetHandler.handle(line: line, head: head, store: store)
            case .archOptionAdd:
                return try ArchOptionAddHandler.handle(line: line, head: head, store: store)
            case .archDecide:
                return try ArchDecideHandler.handle(line: line, head: head, store: store)

            case .exploreOpen:
                return try ExploreOpenHandler.handle(line: line, head: head, store: store)
            case .exploreKeyFileAdd:
                return try ExploreKeyFileAddHandler.handle(line: line, head: head, store: store)
            case .exploreFindingAdd:
                return try ExploreFindingAddHandler.handle(line: line, head: head, store: store)
            case .exploreRank:
                return try ExploreRankHandler.handle(line: line, head: head, store: store)
            case .exploreComplete:
                return try ExploreCompleteHandler.handle(line: line, head: head, store: store)
            case .exploreReopen:
                return try ExploreReopenHandler.handle(line: line, head: head, store: store)
            case .exploreGet:
                return try ExploreGetHandler.handle(line: line, head: head, store: store)

            case .reviewOpen:
                return try ReviewOpenHandler.handle(line: line, head: head, store: store)
            case .reviewFindingAdd:
                return try ReviewFindingAddHandler.handle(line: line, head: head, store: store)
            case .reviewRank:
                return try ReviewRankHandler.handle(line: line, head: head, store: store)
            case .reviewResolve:
                return try ReviewResolveHandler.handle(line: line, head: head, store: store)
            case .reviewComplete:
                return try ReviewCompleteHandler.handle(line: line, head: head, store: store)
            case .reviewReopen:
                return try ReviewReopenHandler.handle(line: line, head: head, store: store)
            case .reviewGet:
                return try ReviewGetHandler.handle(line: line, head: head, store: store)

            case .briefingOpen:
                return try BriefingOpenHandler.handle(line: line, head: head, store: store)
            case .briefingComplete:
                return try BriefingCompleteHandler.handle(line: line, head: head, store: store)
            case .briefingGet:
                return try BriefingGetHandler.handle(line: line, head: head, store: store)
            case .briefingList:
                return try BriefingListHandler.handle(line: line, head: head, store: store)
            case .briefingStub:
                return try BriefingStubHandler.handle(line: line, head: head, store: store)

            case .dopeInit:
                return try DopeInitHandler.handle(line: line, head: head, store: store)
            case .dopeList:
                return try DopeListHandler.handle(line: line, head: head, store: store)
            case .dopeGet:
                return try DopeGetHandler.handle(line: line, head: head, store: store)
            case .dopePromote:
                return try DopePromoteHandler.handle(line: line, head: head, store: store)
            case .dopeCogAdd:
                return try DopeCogAddHandler.handle(line: line, head: head, store: store)
            case .dopeCogUpdate:
                return try DopeCogUpdateHandler.handle(line: line, head: head, store: store)
            case .dopeCogDelete:
                return try DopeCogDeleteHandler.handle(line: line, head: head, store: store)
            case .dopeCogGet:
                return try DopeCogGetHandler.handle(line: line, head: head, store: store)
            case .dopeCogElementAdd:
                return try DopeCogElementAddHandler.handle(line: line, head: head, store: store)
            case .dopeCogElementUpdate:
                return try DopeCogElementUpdateHandler.handle(line: line, head: head, store: store)
            case .dopeCogElementDelete:
                return try DopeCogElementDeleteHandler.handle(line: line, head: head, store: store)
            case .dopeSearch:
                return try DopeSearchHandler.handle(line: line, head: head, store: store)
            case .dopeNodeAdd:
                return try DopeNodeAddHandler.handle(line: line, head: head, store: store)
            case .dopeNodeUpdate:
                return try DopeNodeUpdateHandler.handle(line: line, head: head, store: store)
            case .dopeNodeDelete:
                return try DopeNodeDeleteHandler.handle(line: line, head: head, store: store)
            case .dopeReadRepo:
                return try DopeReadRepoHandler.handle(line: line, head: head, store: store)
            case .dopeMergePlan:
                return try DopeMergePlanHandler.handle(line: line, head: head, store: store)
            case .dopeResolve:
                return try DopeResolveHandler.handle(line: line, head: head, store: store)
            case .dopeWriteRepo:
                return try DopeWriteRepoHandler.handle(line: line, head: head, store: store)
            case .dopeIngest:
                return try DopeIngestHandler.handle(line: line, head: head, store: store)

            case .diagramInit:
                return try DiagramInitHandler.handle(line: line, head: head, store: store)
            case .diagramList:
                return try DiagramListHandler.handle(line: line, head: head, store: store)
            case .diagramGet:
                return try DiagramGetHandler.handle(line: line, head: head, store: store)
            case .diagramNodeAdd:
                return try DiagramNodeAddHandler.handle(line: line, head: head, store: store)
            case .diagramNodeUpdate:
                return try DiagramNodeUpdateHandler.handle(line: line, head: head, store: store)
            case .diagramNodeDelete:
                return try DiagramNodeDeleteHandler.handle(line: line, head: head, store: store)
            case .diagramBatchApply:
                return try DiagramBatchApplyHandler.handle(line: line, head: head, store: store)
            case .diagramSearch:
                return try DiagramSearchHandler.handle(line: line, head: head, store: store)
            case .diagramDelete:
                return try DiagramDeleteHandler.handle(line: line, head: head, store: store)
            case .diagramWriteRepo:
                return try DiagramWriteRepoHandler.handle(line: line, head: head, store: store)
            case .diagramIngest:
                return try DiagramIngestHandler.handle(line: line, head: head, store: store)

            case .sessionResolve:
                return try SessionResolveHandler.handle(line: line, head: head, store: store)
            case .instanceCurrentSession:
                return try InstanceCurrentSessionHandler.handle(line: line, head: head, store: store)

            case .pathsGet:
                return try PathsGetHandler.handle(line: line, head: head, store: store)
            case .configSet:
                return try ConfigSetHandler.handle(line: line, head: head, store: store)

            case .eventList:
                return try EventListHandler.handle(line: line, head: head, store: store)

            case .event, .error:
                return errorResult(
                    type: head.type, requestId: head.requestId,
                    payload: ErrorPayload(
                        code: .unknownType, message: "\(head.type.rawValue) is daemon → client only"))
            }
        } catch let error as StoreError {
            return errorResult(type: head.type, requestId: head.requestId, payload: error.errorPayload)
        } catch let error as DecodingError {
            return errorResult(
                type: head.type, requestId: head.requestId,
                payload: ErrorPayload(code: .badRequest, message: "undecodable payload: \(error)"))
        } catch {
            return errorResult(
                type: head.type, requestId: head.requestId,
                payload: ErrorPayload(code: .dbError, message: "\(error)"))
        }
    }

    /// SUBSCRIBE — replay → ack-ordering is: ack (with the replay horizon),
    /// then replayed EVENT lines (ids ≤ horizon), then live events. The whole
    /// step runs inside this single dispatch turn on the serial queue, and
    /// commits only happen in other turns on the same queue, so an event is
    /// either ≤ the horizon (replayed) or broadcast live after registration —
    /// gap and duplicate are structurally impossible.
    private func handleSubscribe(line: Data, head: EnvelopeHead, client: ClientConnection) throws -> HandlerResult {
        // Strict decode: a malformed since_id must be BAD_REQUEST, not a
        // silent live-only subscription that loses the caller's replay.
        let sinceId = try decodePayload(Subscribe.self, from: line).sinceId
        let replayed: [EventNotification]
        if let sinceId {
            // Cap at 10k rows; the ack's last_event_id lets a client detect a
            // capped replay (last replayed id < last_event_id) and re-subscribe.
            replayed = try store.listEvents(EventListRequest(sinceId: sinceId, limit: 10_000)).events
        } else {
            replayed = []
        }
        let ack = SubscribeAck(lastEventId: try store.lastEventId(), replayCount: replayed.count)
        let ackEnvelope = ResponseEnvelope<SubscribeAck>(
            type: .subscribe, requestId: head.requestId, ok: true, payload: ack)
        client.send(try NDJSON.encodeLine(ackEnvelope))
        for event in replayed {
            let envelope = ResponseEnvelope<EventNotification>(
                type: .event, requestId: "", ok: true, payload: event)
            if let eventLine = try? NDJSON.encodeLine(envelope) {
                client.send(eventLine)
            }
        }
        // Register directly — we are on the server queue; deferring via async
        // would open a window for another turn's commit to slip between
        // replay and registration. Deduped: a repeat SUBSCRIBE must not make
        // the connection receive every event twice.
        let key = ObjectIdentifier(client)
        if !subscribers.contains(key) {
            subscribers.append(key)
        }
        return HandlerResult(line: Data())
    }

    func errorResult(type: MessageType, requestId: String, payload: ErrorPayload) -> HandlerResult {
        let envelope = ResponseEnvelope<EmptyPayload>(
            type: type, requestId: requestId, ok: false, error: payload)
        // Encoding a payload-less envelope of concrete types cannot realistically
        // fail; the fallback is still a decodable error line rather than a
        // bare newline the client would report as a contextless wire error.
        let fallback = Data(
            #"{"protocol_version":\#(GMCCWireProtocol.version),"type":"ERROR","request_id":"","ok":false,"error":{"code":"INTERNAL_ERROR","message":"error-envelope encoding failed"}}"#
                .utf8) + Data([0x0A])
        let line = (try? NDJSON.encodeLine(envelope)) ?? fallback
        return HandlerResult(line: line)
    }
}

/// One accepted socket connection: buffers bytes, splits on \n, hands each
/// line to the server's dispatcher, writes the response back.
final class ClientConnection: @unchecked Sendable {
    private let connection: NWConnection
    private weak var server: Server?
    private var buffer = Data()

    init(connection: NWConnection, server: Server) {
        self.connection = connection
        self.server = server
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.teardown()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveLoop()
    }

    func send(_ data: Data, completion: (() -> Void)? = nil) {
        connection.send(content: data, completion: .contentProcessed { _ in completion?() })
    }

    /// A client that streams bytes without ever sending a newline must not
    /// grow daemon memory without bound.
    private static let maxBufferedBytes = 10 * 1024 * 1024

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drainLines()
                if self.buffer.count > Self.maxBufferedBytes {
                    self.teardown()
                    return
                }
            }
            if isComplete || error != nil {
                self.teardown()
                return
            }
            self.receiveLoop()
        }
    }

    private func drainLines() {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            guard !line.isEmpty, let server else { continue }
            let result = server.dispatch(line: line, from: self)
            switch result.postAction {
            case .none:
                if !result.line.isEmpty {
                    send(result.line)
                }
            case .shutdown:
                connection.send(content: result.line, completion: .contentProcessed { _ in
                    server.shutdown()
                })
            }
        }
    }

    private func teardown() {
        connection.cancel()
        server?.remove(self)
    }
}
