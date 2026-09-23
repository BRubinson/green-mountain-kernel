import Foundation

// The m0025 bot workflow machine + the architecture option pen.

/// PROMPT_START — enter the machine from draft (creates the workflow row).
enum PromptStartHandler {
    /// Handles a prompt start request to create a new workflow row.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    /// - Returns: A handler result with the response.
    /// - Throws: Any error from decoding the request or persisting the workflow.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptStartRequest.self, from: line)
        return try okResult(.promptStart, head, try store.promptStart(request))
    }
}

/// PROMPT_RESUME — adopt existing evidence (fetch-or-create the row).
enum PromptResumeHandler {
    /// Handles a prompt resume request to adopt or create a workflow row.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    /// - Returns: A handler result with the response.
    /// - Throws: Any error from decoding the request or persisting the workflow.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptResumeRequest.self, from: line)
        return try okResult(.promptResume, head, try store.promptResume(request))
    }
}

/// BOT_NEXT — derive the phase, serve instructions + uuids + gate blockers.
enum BotNextHandler {
    /// Handles a bot next request to derive the current phase and gate status.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    /// - Returns: A handler result with the phase, instructions, UUIDs and gate blockers.
    /// - Throws: Any error from decoding the request or reading the workflow state.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(BotNextRequest.self, from: line)
        return try okResult(.botNext, head, try store.botNext(request))
    }
}

/// BOT_GET — the raw workflow row.
enum BotGetHandler {
    /// Handles a bot get request to retrieve the workflow row.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    /// - Returns: A handler result with the workflow row.
    /// - Throws: Any error from decoding the request or reading the workflow.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(BotGetRequest.self, from: line)
        return try okResult(.botGet, head, try store.botGet(request))
    }
}

/// AGENT_REGISTER — the spawner's authority write for one agent_id.
enum AgentRegisterHandler {
    /// Handles an agent register request to record an agent spawn.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    /// - Returns: A handler result with the registered agent record.
    /// - Throws: Any error from decoding the request or persisting the agent registration.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(AgentRegisterRequest.self, from: line)
        return try okResult(.agentRegister, head, try store.agentRegister(request))
    }
}

/// ARCH_OPTION_ADD — the first architect pen verb (one option per persona).
enum ArchOptionAddHandler {
    /// Handles an architecture option add request.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    /// - Returns: A handler result with the added architecture option.
    /// - Throws: Any error from decoding the request or persisting the option.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchOptionAddRequest.self, from: line)
        return try okResult(.archOptionAdd, head, try store.archOptionAdd(request))
    }
}

/// ARCH_DECIDE — select one option, reject siblings, record the rationale.
enum ArchDecideHandler {
    /// Handles an architecture decide request to select an option.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    /// - Returns: A handler result with the decision outcome.
    /// - Throws: Any error from decoding the request or persisting the decision.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchDecideRequest.self, from: line)
        return try okResult(.archDecide, head, try store.archDecide(request))
    }
}
