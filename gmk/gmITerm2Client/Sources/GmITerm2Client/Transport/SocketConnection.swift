import Foundation

/// Raw POSIX unix domain socket connection to iTerm2's API server.
///
/// Lifted from `it2cli/Sources/it2/Transport/SocketConnection.swift`, with
/// `ITerm2Error` substituted for `IT2Error` throughout. The behaviour is
/// upstream's: AF_UNIX/SOCK_STREAM, a 30-second `SO_RCVTIMEO`, and
/// `send` / `recv(count:)` / `recvUntil(_:)` with a 64KB cap on the header read.
///
/// **NOT `Sendable`, ON PURPOSE.** This is an actor-isolated stored property
/// that never escapes its actor. Leaving it non-Sendable means Swift 6 makes
/// escaping it a COMPILE ERROR — which is the guard rail standing in for the
/// contract-test tier this repository deleted. Do not add `@unchecked Sendable`
/// to quiet a diagnostic; the diagnostic is the feature.
///
/// A note on the transport, because the 3.3-era security document says
/// otherwise: as of iTerm2 3.6 this is a UNIX DOMAIN SOCKET with the WebSocket
/// HTTP upgrade spoken over it. There is no TCP port 1912 and no localhost
/// listener. Firewall work planned off the old document is planned against a
/// transport that no longer applies.
final class SocketConnection {
    private var fd: Int32 = -1

    /// Connect to the iTerm2 API unix domain socket.
    static func connect() throws(ITerm2Error) -> SocketConnection {
        let path = Self.socketPath()
        let conn = SocketConnection()

        conn.fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard conn.fd >= 0 else {
            throw .transportFailed(
                reason: "Failed to create socket: \(String(cString: strerror(errno)))",
                errno: errno
            )
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        // `sun_path` is 104 bytes on macOS. This is the SAME constraint the
        // kernel's own run roots live under — it is why test run ids are kept
        // short — and it is upstream's guard, kept verbatim.
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(conn.fd)
            conn.fd = -1
            throw .transportFailed(reason: "Socket path too long: \(path)", errno: nil)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, pathBytes.count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(conn.fd, sockPtr, addrLen)
            }
        }

        guard result == 0 else {
            let code = errno
            let err = String(cString: strerror(code))
            Darwin.close(conn.fd)
            conn.fd = -1

            // ECONNREFUSED and ENOENT both mean exactly one thing: NOTHING IS
            // LISTENING. That is the same condition `ITerm2App.ensureRunning`
            // types as `.apiServerUnavailable`, and callers collapse it into
            // the "turn the Python API on" copy with its affordance. Reaching
            // the identical condition through `connect(2)` must not report a
            // raw strerror the user cannot act on — the enablement affordance
            // has to be reachable by EVERY route to "the server isn't there".
            //
            // ECONNREFUSED specifically is the STALE SOCKET case: iTerm2 never
            // unlinks the path on quit (it unlinks only just before binding),
            // so the file outlives the process that bound it.
            if code == ECONNREFUSED || code == ENOENT {
                throw .apiServerUnavailable(socketPath: path)
            }

            throw .transportFailed(
                reason: "Failed to connect to the iTerm2 socket at \(path): \(err)",
                errno: code
            )
        }

        // A 30-second read timeout, so a wedged server is a failure rather than
        // a hang. THIS is the blocking window the owning actor's custom
        // executor exists to keep off the cooperative thread pool.
        // THE RETURN IS CHECKED because this option is the only thing bounding
        // a blocking `recv`. If it silently failed, the socket would stay in
        // blocking mode with no timeout and a server that accepts but never
        // answers would park the actor's dedicated thread forever — every later
        // Play queued behind it, with no diagnostic anywhere. Unlikely on a
        // freshly connected AF_UNIX fd; one guard against the package's only
        // unbounded-hang state is worth it anyway.
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        guard setsockopt(conn.fd, SOL_SOCKET, SO_RCVTIMEO,
                         &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
            let code = errno
            let err = String(cString: strerror(code))
            Darwin.close(conn.fd)
            conn.fd = -1
            throw .transportFailed(
                reason: "Could not set the socket read timeout: \(err)",
                errno: code
            )
        }

        return conn
    }

    /// Is something ACTUALLY LISTENING on the API socket right now?
    ///
    /// THE FILE EXISTING IS NOT THE SAME QUESTION, and the difference is a bug
    /// that makes Play permanently inert. `iTermAPIServer.m` unlinks the path
    /// only immediately BEFORE binding and never on quit, so on any machine
    /// where iTerm2 has ever run with the Python API on, the socket file exists
    /// forever afterwards — running or not. A `fileExists` check therefore
    /// reports "the server is up" for a machine where iTerm2 is not even
    /// launched, and every caller downstream fails with ECONNREFUSED.
    ///
    /// A connect-and-close is the only honest test, and it is cheap: an
    /// AF_UNIX connect to a bound listener is an in-kernel operation with no
    /// round trip. Callers that need "is it there" must use THIS, not `stat`.
    static func isServerListening(path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, pathBytes.count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }
        return result == 0
    }

    /// Send raw bytes, looping until the whole buffer is away.
    func send(_ data: Data) throws(ITerm2Error) {
        var failure: ITerm2Error?
        data.withUnsafeBytes { buf in
            var sent = 0
            let total = buf.count
            guard let base = buf.baseAddress else { return }
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            while sent < total {
                let n = Darwin.send(fd, ptr + sent, total - sent, 0)
                guard n > 0 else {
                    failure = .transportFailed(
                        reason: "Socket send failed: \(String(cString: strerror(errno)))",
                        errno: errno
                    )
                    return
                }
                sent += n
            }
        }
        if let failure { throw failure }
    }

    /// Receive exactly `count` bytes.
    func recv(count: Int) throws(ITerm2Error) -> Data {
        guard count > 0 else { return Data() }
        var buffer = Data(count: count)
        var failure: ITerm2Error?
        buffer.withUnsafeMutableBytes { buf in
            var received = 0
            guard let base = buf.baseAddress else { return }
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            while received < count {
                let n = Darwin.recv(fd, ptr + received, count - received, 0)
                guard n > 0 else {
                    failure = n == 0
                        ? .transportFailed(reason: "Connection closed by iTerm2", errno: nil)
                        : .transportFailed(
                            reason: "Socket recv failed: \(String(cString: strerror(errno)))",
                            errno: errno
                          )
                    return
                }
                received += n
            }
        }
        if let failure { throw failure }
        return buffer
    }

    /// Read until `delimiter` is the tail of what has accumulated.
    ///
    /// Used for exactly one thing: the end of the HTTP upgrade response
    /// headers. The 64KB cap is upstream's and is what stops a server that
    /// never sends `\r\n\r\n` from growing this buffer without bound.
    func recvUntil(_ delimiter: Data) throws(ITerm2Error) -> Data {
        var accumulated = Data()
        accumulated.reserveCapacity(512)
        var chunk = Data(count: 256)
        while true {
            var readErrno: Int32 = 0
            let n = chunk.withUnsafeMutableBytes { buf -> Int in
                guard let base = buf.baseAddress else { return -1 }
                let result = Darwin.recv(fd, base, 256, 0)
                if result < 0 { readErrno = errno }
                return result
            }
            guard n > 0 else {
                if n == 0 {
                    throw .transportFailed(reason: "Connection closed by iTerm2", errno: nil)
                }
                throw .transportFailed(
                    reason: "Socket recv failed: \(String(cString: strerror(readErrno)))",
                    errno: readErrno
                )
            }
            accumulated.append(chunk.prefix(n))
            if accumulated.count >= delimiter.count,
               accumulated.suffix(delimiter.count) == delimiter {
                return accumulated
            }
            if accumulated.count > 65_536 {
                throw .transportFailed(reason: "Response header too large", errno: nil)
            }
        }
    }

    func disconnect() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    deinit {
        disconnect()
    }

    // MARK: - Path

    /// Where iTerm2 binds its API socket.
    ///
    /// Exposed (rather than private, as upstream has it) so `ITerm2App` can
    /// `stat` the socket to decide whether the server is up WITHOUT opening a
    /// connection — the warm path is one filesystem check, not a handshake.
    static func socketPath() -> String {
        let appSupport = NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true
        ).first ?? NSHomeDirectory() + "/Library/Application Support"
        let suite = ProcessInfo.processInfo.environment["IT2_SUITE"] ?? "iTerm2"
        return "\(appSupport)/\(suite)/private/socket"
    }
}
