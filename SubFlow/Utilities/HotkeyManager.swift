import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private var monitor: Any?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
            let hasFlags = event.modifierFlags.contains(requiredFlags)
            let isKeyT = event.keyCode == UInt16(kVK_ANSI_T)

            if hasFlags && isKeyT {
                self?.action()
            }
        }
    }

    func unregister() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        unregister()
    }
}
