import Carbon.HIToolbox

/// ⌃⌥1…⌃⌥9 via Carbon hotkeys (no Accessibility permission needed).
@MainActor
final class Hotkeys {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x4353_7774 // 'CSwt'
    private static let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                   kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
    private var refs: [EventHotKeyRef] = []
    /// 0-based positions whose hotkey registered.
    private(set) var registered: Set<Int> = []

    init() { Self.installHandlerOnce() }

    /// Replaces all hotkeys: action i gets ⌃⌥(i+1). Taken combinations are skipped.
    func register(_ actions: [() -> Void]) {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        registered.removeAll()
        Self.handlers.removeAll()
        for (index, action) in actions.prefix(Self.keyCodes.count).enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            let status = RegisterEventHotKey(UInt32(Self.keyCodes[index]), UInt32(controlKey | optionKey),
                                             id, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else { continue }
            refs.append(ref)
            registered.insert(index)
            Self.handlers[UInt32(index)] = action
        }
    }

    private static func installHandlerOnce() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == Hotkeys.signature else { return noErr }
            MainActor.assumeIsolated { Hotkeys.handlers[id.id]?() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
