import Foundation

/// NDJSON unix-socket REQUEST/RESPONSE client used by gm_hook, gm_mcp AND
/// GMVibes, over blocking POSIX socket I/O and short-lived exchanges.
///
/// An internal lock serializes concurrent request() callers so the shared fd
/// and read buffer can never interleave frames. Connect-or-autostart: a dead
/// socket spawns the headless kernel, which the pidfile flock makes
/// idempotent. Event streaming lives in DaemonEventSubscription, which owns
/// its own connection, so a streaming connection cannot issue requests.
final class DaemonClient: @unchecked Sendable {
    private let socketPath: String
    private let daemonBinaryPath: String
    private let clientName: String
    private let autostartEnabled: Bool
    private let lock = NSLock()

    private var fd: Int32 = -1
    private var readBuffer = Data()

    /// Creates a client bound to a daemon socket.
    ///
    /// - Parameters:
    ///   - socketPath: Unix socket path; defaults to the standard location.
    ///   - daemonBinaryPath: Path to the daemon executable to spawn if needed.
    ///   - clientName: Name sent in the hello handshake; defaults to `"gm"`.
    ///   - autostart: Whether to spawn the daemon if the socket is unreachable.
    init(
        socketPath: String = Paths.socket.path,
        daemonBinaryPath: String = Paths.binDaemon.path,
        clientName: String = "gm",
        autostart: Bool = true
    ) {
        self.socketPath = socketPath
        self.daemonBinaryPath = daemonBinaryPath
        self.clientName = clientName
        self.autostartEnabled = autostart
    }

    deinit {
        close()
    }

    /// Closes the daemon socket and discards the read buffer.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
    }

    /// Closes the socket and read buffer when the lock is already held.
    private func closeLocked() {
        if fd >= 0 {
            // shutdown() before close(): on Darwin, close() alone does not
            // reliably wake another thread blocked in read(2) on this socket
            // (a cancelled quiet event subscription would strand its worker);
            // shutdown delivers EOF to any blocked reader first.
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
            fd = -1
        }
        readBuffer.removeAll()
    }

    // MARK: - Public API

    /// Connects to the daemon, autostarting if needed, and exchanges hello.
    ///
    /// Mismatch handling is directional: retry-with-autostart only when the daemon reported an older version
    /// than ours (the freshly built binary wins); when the daemon is newer, a respawn cycle is doomed — surface
    /// the mismatch immediately.
    ///
    /// - Returns: The hello acknowledgment from the daemon.
    /// - Throws: `DaemonClientError` on connection, wire, or handshake failure.
    func connect() throws -> HelloAck {
        lock.lock()
        defer { lock.unlock() }
        return try connectLocked()
    }

    /// Connects when the lock is already held, retrying with autostart if needed.
    ///
    /// - Returns: The hello acknowledgment from the daemon.
    /// - Throws: `DaemonClientError` on connection, wire, or handshake failure.
    private func connectLocked() throws -> HelloAck {
        do {
            return try connectOnce()
        } catch DaemonClientError.protocolMismatch(let message, let daemonVersion) {
            closeLocked()
            if let daemonVersion, daemonVersion >= GmWireProtocol.version {
                throw DaemonClientError.protocolMismatch(message: message, daemonVersion: daemonVersion)
            }
            try autostart()
            return try connectOnce()
        }
    }

    /// Sends a request and returns the response, connecting lazily.
    ///
    /// Concurrent callers serialize on the internal lock. On wire failure, retries once
    /// after reconnecting, as the daemon may have restarted under a long-lived client.
    ///
    /// - Parameters:
    ///   - type: Message type identifier.
    ///   - payload: Encoded message payload.
    ///   - responseType: Response type for generic type parameter inference.
    /// - Returns: The decoded response payload.
    /// - Throws: `DaemonClientError` on connection, wire, or protocol mismatch.
    func request<Req: Codable & Sendable, Resp: Codable & Sendable>(
        type: MessageType,
        payload: Req,
        responseType: Resp.Type  // swiftlint:disable:this unused_parameter
    ) throws -> Resp {
        lock.lock()
        defer { lock.unlock() }
        if fd < 0 { _ = try connectLocked() }
        let envelope = RequestEnvelope(type: type, payload: payload)
        let response: ResponseEnvelope<Resp>
        do {
            response = try roundTrip(envelope)
        } catch let error as DaemonClientError {
            // A wire failure usually means the daemon restarted under us
            // (EPIPE/EOF on a stale fd). A one-shot invocation never noticed;
            // long-lived clients (gm_mcp, GMVibes) were permanently
            // bricked. Reset the socket and retry ONCE — the hello
            // handshake re-runs and the directional version logic still
            // applies; a second failure propagates.
            guard case .wire = error else { throw error }
            closeLocked()
            _ = try connectLocked()
            response = try roundTrip(envelope)
        }
        if let error = response.error {
            if error.code == .protocolMismatch {
                throw DaemonClientError.protocolMismatch(
                    message: error.message,
                    daemonVersion: error.daemonProtocolVersion
                )
            }
            throw DaemonClientError.server(error)
        }
        guard let payload = response.payload else {
            throw DaemonClientError.wire("response for \(type.rawValue) carried no payload")
        }
        return payload
    }

    // MARK: - Connection plumbing

    /// Opens a new socket, exchanges hello, and returns the acknowledgment.
    ///
    /// - Returns: The hello acknowledgment from the daemon.
    /// - Throws: `DaemonClientError` on socket open, wire, or handshake failure.
    private func connectOnce() throws -> HelloAck {
        if fd < 0 {
            try openSocket()
        }
        let hello = RequestEnvelope(type: .hello, payload: Hello(clientName: clientName, pid: getpid()))
        let response: ResponseEnvelope<HelloAck> = try roundTrip(hello)
        if let error = response.error {
            if error.code == .protocolMismatch {
                throw DaemonClientError.protocolMismatch(
                    message: error.message,
                    daemonVersion: error.daemonProtocolVersion
                )
            }
            throw DaemonClientError.server(error)
        }
        guard let ack = response.payload else {
            throw DaemonClientError.wire("hello ack carried no payload")
        }
        return ack
    }

    /// Dials the socket or spawns the daemon if autostart is enabled.
    ///
    /// - Throws: `DaemonClientError.unreachable` if the socket is dead and autostart is disabled.
    private func openSocket() throws {
        if let connected = try? dial() {
            fd = connected
            return
        }
        guard autostartEnabled else {
            throw DaemonClientError.unreachable("daemon socket dead at \(socketPath) and autostart disabled")
        }
        try autostart()
    }

    /// Spawns the daemon and retries connection with exponential backoff.
    ///
    /// The spawn happens inside the retry loop: a spawn that races a dying daemon's pidfile
    /// flock exits 0 by design, so only re-spawning (idempotent under the flock) survives the
    /// rebuild cycle. Retries up to 10 times with delays from 100 ms to 1 s.
    ///
    /// - Throws: `DaemonClientError.unreachable` when the binary is missing or all retries fail.
    private func autostart() throws {
        guard FileManager.default.isExecutableFile(atPath: daemonBinaryPath) else {
            throw DaemonClientError.unreachable(
                "daemon binary missing at \(daemonBinaryPath) — run install_gm.sh"
            )
        }
        var delay: UInt32 = 100_000  // µs
        for _ in 0..<10 {
            guard spawnDaemon() else {
                throw DaemonClientError.unreachable(
                    "posix_spawn(\(daemonBinaryPath)) failed: \(String(cString: strerror(errno)))"
                )
            }
            usleep(delay)
            if let connected = try? dial() {
                fd = connected
                return
            }
            delay = min(delay * 2, 1_000_000)
        }
        throw DaemonClientError.unreachable("daemon did not come up at \(socketPath) after autostart")
    }

    /// Spawns the headless daemon process with explicit personality argument.
    ///
    /// Uses `posix_spawn` with the daemon personality to bypass LaunchServices instance-per-bundle
    /// enforcement. Running on a GUI binary would create a second writer. Passes `GM_FS_ROOT`
    /// to ensure the spawned daemon uses the same root as the current process.
    ///
    /// - Returns: `true` when the spawn succeeds, `false` on `posix_spawn` failure.
    private func spawnDaemon() -> Bool {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        // Detach into its own session so the daemon outlives the CLI cleanly.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [
            strdup(daemonBinaryPath), strdup("daemon"), nil,
        ]
        defer { argv.forEach { free($0) } }

        // THE CHILD'S ROOT IS SET EXPLICITLY, ALWAYS — production included.
        //
        // An app resolves its root from its BUNDLE and a LaunchServices-launched
        // process carries no GM_FS_ROOT at all, so passing `environ` through
        // would point the spawned writer at a different database from the one
        // its parent reads. `Paths.root` is whatever this process actually
        // resolved — bundle key, env, or default — and an explicit value cannot
        // be redirected by a stray export in the launching shell.
        var env = ProcessInfo.processInfo.environment
        env["GM_FS_ROOT"] = Paths.root.path
        let envp: [UnsafeMutablePointer<CChar>?] =
            env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { free($0) } }

        let rc = posix_spawn(&pid, daemonBinaryPath, nil, &attr, argv, envp)
        posix_spawnattr_destroy(&attr)
        return rc == 0
    }

    /// Creates a connected unix-domain socket bound to the daemon path.
    ///
    /// Sets `SO_NOSIGPIPE` to avoid SIGPIPE on writes to stale sockets.
    ///
    /// - Returns: A connected socket file descriptor.
    /// - Throws: `DaemonClientError.unreachable` on socket creation or connection failure.
    private func dial() throws -> Int32 {
        let sock = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw DaemonClientError.unreachable("socket() failed: \(String(cString: strerror(errno)))")
        }
        // Daemon restarts are routine (directional self-exit after rebuilds);
        // without SO_NOSIGPIPE, writing to the stale fd delivers SIGPIPE and
        // kills the whole process (GMVibes!) instead of surfacing EPIPE
        // through the .wire error path.
        var one: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(sock)
            throw DaemonClientError.unreachable("socket path too long: \(socketPath)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBytes { src in
                dest.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(dest.count)))
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(sock, sa, size)
            }
        }
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(sock)
            throw DaemonClientError.unreachable("connect(\(socketPath)) failed: \(message)")
        }
        return sock
    }

    // MARK: - NDJSON I/O (internal: DaemonEventSubscription reads raw lines)

    /// Sends a request envelope and reads the response envelope.
    ///
    /// - Parameter envelope: The request envelope to encode and send.
    /// - Returns: The decoded response envelope.
    /// - Throws: `DaemonClientError.wire` on encoding, write, read, or decode failure.
    func roundTrip<Req: Codable & Sendable, Resp: Codable & Sendable>(
        _ envelope: RequestEnvelope<Req>
    ) throws -> ResponseEnvelope<Resp> {
        let line: Data
        do {
            line = try NDJSON.encodeLine(envelope)
        } catch {
            throw DaemonClientError.wire("encode failed: \(error)")
        }
        try writeAll(line)
        let responseLine = try readLine()
        do {
            return try NDJSON.decode(ResponseEnvelope<Resp>.self, from: responseLine)
        } catch {
            throw DaemonClientError.wire("decode failed: \(error)")
        }
    }

    /// Writes data to the socket, retrying until all bytes are sent.
    ///
    /// - Parameter data: The data to write.
    /// - Throws: `DaemonClientError.wire` on write failure or broken pipe.
    private func writeAll(_ data: Data) throws {
        var remaining = data
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { buf in
                Darwin.write(fd, buf.baseAddress, buf.count)
            }
            guard written > 0 else {
                throw DaemonClientError.wire("write failed: \(String(cString: strerror(errno)))")
            }
            remaining = remaining.dropFirst(written)
        }
    }

    /// Reads a line from the socket, buffering and searching for newline.
    ///
    /// Buffers data across multiple reads and returns when a `0x0A` byte is found,
    /// excluding the newline from the result.
    ///
    /// - Returns: Data up to but not including the newline.
    /// - Throws: `DaemonClientError.wire` on read failure or connection closure.
    func readLine() throws -> Data {
        while true {
            if let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
                let line = readBuffer.subdata(in: readBuffer.startIndex..<newlineIndex)
                readBuffer.removeSubrange(readBuffer.startIndex...newlineIndex)
                return line
            }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count > 0 {
                readBuffer.append(contentsOf: chunk[0..<count])
            } else if count == 0 {
                throw DaemonClientError.wire("connection closed by daemon")
            } else {
                throw DaemonClientError.wire("read failed: \(String(cString: strerror(errno)))")
            }
        }
    }
}
