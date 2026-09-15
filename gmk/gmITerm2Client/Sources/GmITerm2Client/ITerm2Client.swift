import Foundation
import SwiftProtobuf

/// The one multiplexed connection to iTerm2's API server.
///
/// There is deliberately no AppKit import in this file. The AppKit half lives in
/// `ITerm2App`, and keeping the two apart is what lets this type be an actor on
/// a private queue instead of something that has to be on the main one.
///
/// `shared` owns ONE connection, never one per pane. Per-pane connections would
/// mean N cookie subprocesses, N Apple events and N iTerm2 client approvals for
/// a verb that is a single round trip.
///
/// `KernelOwnership.Token` is deliberately NOT extended to cover this. That
/// token governs `gm.db` and exists to make a second writer unconstructible; a
/// terminal connection is not a second writer and dragging the token out here
/// would blur what it means.
public actor ITerm2Client {
    public static let shared = ITerm2Client()

    // MARK: - THE CUSTOM EXECUTOR
    //
    // THIS IS THE SINGLE MOST IMPORTANT LINE IN THE PACKAGE. Do not remove it
    // to "simplify the actor".
    //
    // A PLAIN ACTOR RUNS ON THE COOPERATIVE THREAD POOL, which has roughly one
    // thread per core and is built on the assumption that NO THREAD EVER
    // BLOCKS. `SocketConnection.recv` blocks, under a 30-second `SO_RCVTIMEO`.
    // Parking a cooperative thread for thirty seconds can STARVE EVERY OTHER
    // ASYNC IN THE APP — SwiftUI's own included — and the symptom is a frozen
    // window, not an error anybody can trace back to here.
    //
    // Binding the actor to a dedicated `DispatchSerialQueue` puts the blocking
    // I/O on a thread of its own while keeping actor mutual exclusion intact.
    // That exclusion is not just a safety property either: it is what makes
    // `APIClient.send`'s id-discarding loop correct, because exactly one
    // request is ever in flight.
    //
    // `DispatchSerialQueue: SerialExecutor` requires macOS 14. This package's
    // floor is 27.
    private let queue = DispatchSerialQueue(label: "com.gmvibes.iterm2")

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private var client: APIClient?

    private init() {}

    // MARK: - The one verb

    /// Open a NEW iTerm2 window and return what was created.
    ///
    /// One `CreateTabRequest`, one round trip. Slice 1 sends exactly this and
    /// nothing else — no `SetProfilePropertyRequest`, no `SendTextRequest`.
    public func createWindow(_ request: PaneLaunchRequest) async throws(ITerm2Error) -> PaneSession {
        do {
            return try await attemptCreate(request, profileName: request.profileName)
        } catch .transportFailed(let reason, let code) {
            // A mid-flight transport failure usually means iTerm2 restarted or
            // the socket went away under us. Tear the connection down,
            // reconnect ONCE, and retry. NO RECONNECT LOOP: if the second
            // attempt also fails, the problem is not transient and retrying
            // forever only delays telling the user.
            //
            // THIS CATCHES `.transportFailed` AND DELIBERATELY NOT
            // `.responseLost`. `.transportFailed` means the request never got
            // away, so re-sending it is safe. `.responseLost` means iTerm2 may
            // already have OPENED THE WINDOW and only the reply went missing —
            // and `CreateTabRequest` is not idempotent, so retrying it would
            // give the user two windows and two `claude` sessions on one
            // prompt. That case propagates untouched, on purpose: an unopened
            // window the user can retry by hand beats two they did not ask for.
            teardown()
            do {
                return try await attemptCreate(request, profileName: request.profileName)
            } catch {
                _ = (reason, code)
                throw error
            }
        }
    }

    /// Drop the connection. Safe to call when there is none.
    public func disconnect() {
        teardown()
    }

    // MARK: - Private

    private func teardown() {
        client?.disconnect()
        client = nil
    }

    private func connectIfNeeded() throws(ITerm2Error) -> APIClient {
        if let client { return client }
        let fresh = try APIClient.connect()
        client = fresh
        return fresh
    }

    private func attemptCreate(
        _ request: PaneLaunchRequest,
        profileName: String?
    ) async throws(ITerm2Error) -> PaneSession {
        let response = try send(request, profileName: profileName)

        switch response.status {
        case .ok:
            return PaneSession(
                windowId: response.windowID,
                tabId: response.tabID,
                sessionId: response.sessionID,
                usedDefaultProfile: profileName == nil
            )

        case .invalidProfileName:
            // The named profile is not there — most often because a Dynamic
            // Profile was just written and iTerm2 has not reloaded it yet.
            // Give it a beat and ask again with the SAME name.
            try await sleep(milliseconds: 500)
            let retry = try send(request, profileName: profileName)
            if retry.status == .ok {
                return PaneSession(
                    windowId: retry.windowID,
                    tabId: retry.tabID,
                    sessionId: retry.sessionID,
                    usedDefaultProfile: profileName == nil
                )
            }
            // Still not there. THE ONE DEGRADED RUNG, and it degrades
            // COSMETICS rather than correctness: same directory, same command,
            // default profile, wrong colours — and `usedDefaultProfile` says so
            // out loud so the caller can tell the user rather than quietly
            // pretending it got what it asked for. There is deliberately no
            // rung below this: a window WITHOUT the command would look like
            // success while the prompt never runs.
            guard profileName != nil else {
                throw .launchRejected(status: "\(retry.status)")
            }
            let fallback = try send(request, profileName: nil)
            guard fallback.status == .ok else {
                throw .launchRejected(status: "\(fallback.status)")
            }
            return PaneSession(
                windowId: fallback.windowID,
                tabId: fallback.tabID,
                sessionId: fallback.sessionID,
                usedDefaultProfile: true
            )

        default:
            throw .launchRejected(status: "\(response.status)")
        }
    }

    private func send(
        _ request: PaneLaunchRequest,
        profileName: String?
    ) throws(ITerm2Error) -> Iterm2_CreateTabResponse {
        let api = try connectIfNeeded()

        var create = Iterm2_CreateTabRequest()
        if let profileName { create.profileName = profileName }
        // `window_id` LEFT UNSET => a NEW WINDOW. `select_tab` LEFT UNSET =>
        // iTerm2's default, which selects the new tab and orders its window
        // front within iTerm2. Neither is an omission.
        //
        // The command rides in `custom_profile_properties`. NEVER the `command`
        // field 4, which upstream marks `[deprecated=true]` with the note
        // "Use custom_profile_properties instead".
        create.customProfileProperties = request.profileProperties.map { property in
            var p = Iterm2_ProfileProperty()
            p.key = property.key
            p.jsonValue = property.jsonValue
            return p
        }

        var message = Iterm2_ClientOriginatedMessage()
        message.createTabRequest = create

        let response = try api.send(message)
        guard case .createTabResponse(let create)? = response.submessage else {
            throw .serverError("iTerm2 answered a CreateTabRequest with something else")
        }
        return create
    }

    /// `Task.sleep` with the cancellation error mapped into our closed set —
    /// typed throws leaves no room for a stray `CancellationError`.
    private func sleep(milliseconds: Int) async throws(ITerm2Error) {
        do {
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
        } catch {
            throw .cancelled
        }
    }
}
