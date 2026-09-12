import Foundation
import GMCCDaemonKit

// The m0025 clarification split + care package handlers.

/// CLARIFY_QUESTION_ADD — insert a user question (+option children) while the summary is building.
enum ClarifyQuestionAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyQuestionAddRequest.self, from: line)
        return try okResult(.clarifyQuestionAdd, head, try store.clarifyQuestionAdd(request))
    }
}

/// CLARIFY_NOTE_ADD — insert an internal clarification note (any summary state).
enum ClarifyNoteAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyNoteAddRequest.self, from: line)
        return try okResult(.clarifyNoteAdd, head, try store.clarifyNoteAdd(request))
    }
}

/// CARE_PACKAGE_OPEN — create-or-return the package on a clarification summary.
enum CarePackageOpenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(CarePackageOpenRequest.self, from: line)
        return try okResult(.carePackageOpen, head, try store.carePackageOpen(request))
    }
}

/// CARE_PACKAGE_REF_ADD — add one dope/kbite/exploration ref while building.
enum CarePackageRefAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(CarePackageRefAddRequest.self, from: line)
        return try okResult(.carePackageRefAdd, head, try store.carePackageRefAdd(request))
    }
}

/// CARE_PACKAGE_COMPLETE — building → ready; carries the clarified intent.
enum CarePackageCompleteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(CarePackageCompleteRequest.self, from: line)
        return try okResult(.carePackageComplete, head, try store.carePackageComplete(request))
    }
}

/// CARE_PACKAGE_GET — the package by prompt.
enum CarePackageGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(CarePackageGetRequest.self, from: line)
        return try okResult(.carePackageGet, head, try store.carePackageGet(request))
    }
}
