import AppKit
import Combine
import WiFiPriorityCore

/// Watches key presses only while the settings window is recording a shortcut.
/// A local monitor does not request system-wide keyboard monitoring access.
final class ShortcutCapture: ObservableObject {
    @Published private(set) var recording = false
    private var monitor: Any?

    func start(onKey: @escaping (NSEvent) -> Void) {
        stop()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording else { return event }
            onKey(event)
            return nil
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        recording = false
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    static func shortcut(from event: NSEvent) -> PauseShortcut? {
        var modifiers: ShortcutModifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        return PauseShortcut(keyCode: event.keyCode, modifiers: modifiers,
                             key: event.charactersIgnoringModifiers ?? "")
    }
}
