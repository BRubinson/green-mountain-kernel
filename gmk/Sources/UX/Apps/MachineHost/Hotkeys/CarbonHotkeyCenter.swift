import Carbon.HIToolbox
import Foundation

/// Global hotkeys through Carbon's `RegisterEventHotKey`, which needs no Accessibility or Input Monitoring grant.
///
/// The event handler runs on the main thread and only hands the fired binding to the sink; it never touches
/// the Store.
@MainActor
final class CarbonHotkeyCenter {
    /// The four-character signature stamped on every hotkey this app registers ("GMHK").
    private static let signature: OSType = 0x474D_484B

    /// Where fired hotkeys go.
    private let sink: WMEventSink
    /// The installed `kEventHotKeyPressed` handler, once installed.
    private var handler: EventHandlerRef?
    /// The registered hotkeys by the id Carbon hands back.
    private var bindings: [UInt32: HotkeyBinding] = [:]
    /// The Carbon references to unregister.
    private var refs: [EventHotKeyRef] = []

    /// Creates a center that sends fired hotkeys to `sink`; nothing is installed until `register`.
    ///
    /// - Parameter sink: Where `WMEvent.hotkey` events go.
    init(sink: @escaping WMEventSink) {
        self.sink = sink
    }

    /// Registers `bindings`, replacing any registered before.
    ///
    /// A chord another app already holds fails alone; the rest still register.
    ///
    /// - Parameter bindings: The chords to register.
    /// - Returns: The status of every binding that failed, keyed by binding; `eventHotKeyExistsErr` is a conflict.
    @discardableResult
    func register(_ bindings: [HotkeyBinding]) -> [HotkeyBinding: OSStatus] {
        unregisterAll()
        installHandlerIfNeeded()
        var failures: [HotkeyBinding: OSStatus] = [:]
        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            guard status == noErr, let ref else {
                failures[binding] = status
                continue
            }
            refs.append(ref)
            self.bindings[id] = binding
        }
        return failures
    }

    /// Unregisters every hotkey; the handler stays installed for the next `register`.
    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        bindings = [:]
    }

    /// Sends the binding Carbon fired to the sink.
    ///
    /// - Parameter id: The id from the fired `EventHotKeyID`.
    fileprivate func fire(id: UInt32) {
        guard let binding = bindings[id] else { return }
        sink(.hotkey(binding))
    }

    /// Installs the `kEventHotKeyPressed` handler on the application target, once.
    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &spec, refcon, &handler)
    }
}

/// The Carbon handler: reads the fired hotkey id and routes it to the `CarbonHotkeyCenter` in `userData`.
private let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotkey = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkey
    )
    guard status == noErr, hotkey.signature == 0x474D_484B else { return OSStatus(eventNotHandledErr) }
    let id = hotkey.id
    let center = Unmanaged<CarbonHotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { center.fire(id: id) }
    return noErr
}
