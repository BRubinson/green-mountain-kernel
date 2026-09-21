import Foundation
import CoreServices

/// The ONE watcher-lifecycle primitive shared by MemoryWatcher and
/// CheckoutFSEventLane. FSEventStreamCreate takes a fixed path array at
/// construction, so any change to the watched set means stopping and recreating
/// the stream; one implementation keeps re-rooting and instance-set churn from
/// diverging.
///
/// Lane contract: HOLDS NO Store AND NO Server, so it structurally cannot write
/// to the db. All state is confined to `queue`, where the handler also fires.
final class FSEventLane: @unchecked Sendable {
    /// SAFETY CAP: beyond this the path set is truncated (logged), so a
    /// runaway instance table degrades honestly instead of wedging the daemon.
    private static let maxPaths = 256

    private let queue: DispatchQueue
    private let latency: CFTimeInterval
    private var handler: (@Sendable ([String]) -> Void)?
    private var stream: FSEventStreamRef?
    private var current: [String] = []

    init(label: String, latency: CFTimeInterval) {
        self.queue = DispatchQueue(label: label, qos: .utility)
        self.latency = latency
    }

    /// Set once, before the first setPaths — the owning watcher's filter,
    /// invoked on the lane queue.
    func setHandler(_ handler: @escaping @Sendable ([String]) -> Void) {
        queue.async { self.handler = handler }
    }

    /// Hop arbitrary work onto the lane — watchers confine their filter state
    /// here, the same discipline the stream field itself follows.
    func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// THE re-rooting primitive. Idempotent: a no-op when the (sorted,
    /// deduped) set is unchanged — which is what makes rebuilding on every
    /// instance creation free when nothing actually changed. Empty paths =
    /// stopped, no stream held.
    func setPaths(_ paths: [String]) {
        queue.async {
            var next = Array(Set(paths)).sorted()
            if next.count > Self.maxPaths {
                FileHandle.standardError.write(
                    Data(
                        "[gm_daemon] FSEventLane: \(next.count) paths exceeds cap \(Self.maxPaths) — truncating\n".utf8
                    )
                )
                next = Array(next.prefix(Self.maxPaths))
            }
            guard next != self.current else { return }
            self.teardownOnQueue()
            self.current = next
            guard !next.isEmpty else { return }
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
                guard let info else { return }
                let lane = Unmanaged<FSEventLane>.fromOpaque(info).takeUnretainedValue()
                guard
                    let paths = Unmanaged<CFArray>
                        .fromOpaque(
                            UnsafeRawPointer(eventPaths)
                        )
                        .takeUnretainedValue() as? [String]
                else { return }
                lane.handler?(Array(paths.prefix(count)))
            }
            guard
                let stream = FSEventStreamCreate(
                    kCFAllocatorDefault,
                    callback,
                    &context,
                    next as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    self.latency,  // the debounce window
                    // UseCFTypes is LOAD-BEARING: without it eventPaths is a
                    // char ** and the CFArray cast in the callback reads path
                    // bytes as an objc pointer — a SIGSEGV on the first event.
                    FSEventStreamCreateFlags(
                        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                    )
                )
            else {
                FileHandle.standardError.write(
                    Data(
                        "[gm_daemon] FSEventLane: FSEventStreamCreate failed for \(next)\n".utf8
                    )
                )
                self.current = []
                return
            }
            FSEventStreamSetDispatchQueue(stream, self.queue)
            guard FSEventStreamStart(stream) else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.current = []
                return
            }
            self.stream = stream
        }
    }

    func stop() {
        queue.async {
            self.teardownOnQueue()
            self.current = []
        }
    }

    private func teardownOnQueue() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
