import Foundation
import GMCCDaemonKit

// The m0025 bot workflow machine + the architecture option pen.

/// PROMPT_START — enter the machine from draft (creates the workflow row).
enum PromptStartHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptStartRequest.self, from: line)
        return try okResult(.promptStart, head, try store.promptStart(request))
    }
}

/// PROMPT_RESUME — adopt existing evidence (fetch-or-create the row).
enum PromptResumeHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptResumeRequest.self, from: line)
        return try okResult(.promptResume, head, try store.promptResume(request))
    }
}

/// BOT_NEXT — derive the phase, serve instructions + uuids + gate blockers.
enum BotNextHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(BotNextRequest.self, from: line)
        return try okResult(.botNext, head, try store.botNext(request))
    }
}

/// BOT_GET — the raw workflow row.
enum BotGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(BotGetRequest.self, from: line)
        return try okResult(.botGet, head, try store.botGet(request))
    }
}

/// AGENT_REGISTER — the spawner's authority write for one agent_id.
enum AgentRegisterHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(AgentRegisterRequest.self, from: line)
        return try okResult(.agentRegister, head, try store.agentRegister(request))
    }
}

/// ARCH_OPTION_ADD — the first architect pen verb (one option per persona).
enum ArchOptionAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchOptionAddRequest.self, from: line)
        return try okResult(.archOptionAdd, head, try store.archOptionAdd(request))
    }
}

/// ARCH_DECIDE — select one option, reject siblings, record the rationale.
enum ArchDecideHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchDecideRequest.self, from: line)
        return try okResult(.archDecide, head, try store.archDecide(request))
    }
}
