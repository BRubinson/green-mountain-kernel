import Foundation

final class SocketConnection {
    private var fd: Int32 = -1

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

            if code == ECONNREFUSED || code == ENOENT {
                throw .apiServerUnavailable(socketPath: path)
            }

            throw .transportFailed(
                reason: "Failed to connect to the iTerm2 socket at \(path): \(err)",
                errno: code
            )
        }

        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        guard
            setsockopt(
                conn.fd,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &timeout,
                socklen_t(MemoryLayout<timeval>.size)
            ) == 0
        else {
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
                    failure =
                        n == 0
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
                accumulated.suffix(delimiter.count) == delimiter
            {
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

    static func socketPath() -> String {
        let appSupport =
            NSSearchPathForDirectoriesInDomains(
                .applicationSupportDirectory,
                .userDomainMask,
                true
            )
            .first ?? NSHomeDirectory() + "/Library/Application Support"
        let suite = ProcessInfo.processInfo.environment["IT2_SUITE"] ?? "iTerm2"
        return "\(appSupport)/\(suite)/private/socket"
    }
}
