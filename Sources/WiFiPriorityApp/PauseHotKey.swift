import Carbon
import Foundation
import WiFiPriorityCore

/// Carbon hot keys work while this menu bar app is in the background and do not
/// require keyboard monitoring or Accessibility permission.
final class PauseHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var handlerReady = false
    private(set) var active: PauseShortcut = .off
    var onPress: (() -> Void)?

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x57465052, identifier.id == 1 else { return noErr }
            let instance = Unmanaged<PauseHotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { instance.onPress?() }
            return noErr
        }, 1, &event, context, &handler)
        handlerReady = status == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    @discardableResult
    func set(_ shortcut: PauseShortcut) -> Bool {
        guard shortcut != active else { return true }
        guard handlerReady || shortcut == .off else { return false }
        let prior = active
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        active = .off
        if shortcut.isOff { return true }
        if register(shortcut) { active = shortcut; return true }
        if !prior.isOff, register(prior) { active = prior }
        return false
    }

    private func register(_ shortcut: PauseShortcut) -> Bool {
        if shortcut.isOff { return true }
        let identifier = EventHotKeyID(signature: 0x57465052, id: 1) // WFPR
        var modifiers: UInt32 = 0
        if shortcut.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if shortcut.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if shortcut.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        return RegisterEventHotKey(UInt32(shortcut.keyCode), modifiers, identifier,
                                   GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
}
