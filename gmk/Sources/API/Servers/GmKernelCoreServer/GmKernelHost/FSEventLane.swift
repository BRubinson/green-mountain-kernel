import Foundation
import CoreServices

/// The ONE watcher-lifecycle primitive shared by MemoryWatcher and
/// CheckoutFSEventLane.
///
/// FSEventStreamCreate takes a fixed path array at construction; any change to
/// the watched set stops and recreates the stream. One implementation keeps
/// re-rooting and instance-set churn from diverging. Lane contract: no Store,
/// no Server, no database writes; all state confined to `queue`.
final class FSEventLane: @unchecked Sendable {
    /// SAFETY CAP: beyond this the path set is truncated (logged), so a
    /// runaway instance table degrades honestly instead of wedging the daemon.
    private static let maxPaths = 256

    private let queue: DispatchQueue
    private let latency: CFTimeInterval
    private var handler: (@Sendable ([String]) -> Void)?
    private var stream: FSEventStreamRef?
    private var current: [String] = []

    /// Initializes a filesystem event watcher lane.
    ///
    /// - Parameters:
    ///   - label: The dispatch queue label for internal events.
    ///   - latency: The debounce interval for file system events, in seconds.
    init(label: String, latency: CFTimeInterval) {
        self.queue = DispatchQueue(label: label, qos: .utility)
        self.latency = latency
    }

    /// Sets the event handler for filesystem changes.
    ///
    /// Call once before the first setPaths. The handler runs on the lane queue
    /// and receives the paths that changed, invoked by the owning watcher's filter.
    ///
    /// - Parameter handler: A sendable closure receiving changed path arrays.
    func setHandler(_ handler: @escaping @Sendable ([String]) -> Void) {
        queue.async { self.handler = handler }
    }

    /// Dispatches work onto the lane queue.
    ///
    /// Allows watchers to confine filter state and stream operations to the
    /// same serialization discipline the lane uses internally.
    ///
    /// - Parameter work: A sendable closure to execute on the lane queue.
    func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Updates the set of watched filesystem paths.
    ///
    /// The re-rooting primitive. Idempotent: a no-op when the sorted, deduplicated
    /// set is unchanged, which makes rebuilding on every instance creation free when
    /// nothing actually changed. Pass empty paths to stop watching; no stream is held.
    ///
    /// - Parameter paths: The file paths to watch for changes.
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

    /// Stops watching the filesystem and releases the event stream.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    func stop() {
        queue.async {
            self.teardownOnQueue()
            self.current = []
        }
    }

    /// Stops and releases the FSEventStream on the lane queue.
    ///
    /// Must only be called from within a queue.async block to maintain thread safety.
    private func teardownOnQueue() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
