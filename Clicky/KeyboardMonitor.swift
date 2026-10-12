import ApplicationServices
import Carbon

struct KeyStroke: Sendable {
    let code: UInt16
    let isDown: Bool
}

/// The tap observes physical key codes only. It never reads text or blocks input.
final class KeyboardMonitor {
    var onKey: ((KeyStroke) -> Void)?
    var onToggle: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var heldKeys = Set<UInt16>()

    var isRunning: Bool { tap != nil }
    static var isAuthorized: Bool { CGPreflightListenEventAccess() }
    static var isSecureInput: Bool { IsSecureEventInputEnabled() }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.receive(type: type, event: event)
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            return false
        }
        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        heldKeys.removeAll()
    }

    func resetHeldKeys() { heldKeys.removeAll() }

    private func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            heldKeys.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard !Self.isSecureInput else { heldKeys.removeAll(); return }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyDown {
            // A held key produces one physical press, not an artificial stream of clicks.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                  heldKeys.insert(code).inserted else { return }
            if code == 46 && event.flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift])
                == [.maskControl, .maskAlternate, .maskCommand] {
                onToggle?()
                return
            }
            onKey?(KeyStroke(code: code, isDown: true))
        } else if type == .keyUp {
            guard heldKeys.remove(code) != nil else { return }
            onKey?(KeyStroke(code: code, isDown: false))
        } else if type == .flagsChanged {
            if code == 57 {
                // Caps Lock reports its latched state, not physical down/up transitions.
                onKey?(KeyStroke(code: code, isDown: true))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    self?.onKey?(KeyStroke(code: code, isDown: false))
                }
                return
            }
            // Side-specific device flags distinguish left/right modifiers held together.
            let deviceMask: UInt64
            switch code {
            case 54: deviceMask = 0x10
            case 55: deviceMask = 0x08
            case 56: deviceMask = 0x02
            case 60: deviceMask = 0x04
            case 58: deviceMask = 0x20
            case 61: deviceMask = 0x40
            case 59: deviceMask = 0x01
            case 62: deviceMask = 0x2000
            case 63: deviceMask = CGEventFlags.maskSecondaryFn.rawValue
            default: return
            }
            let isDown = event.flags.rawValue & deviceMask != 0
            if isDown {
                guard heldKeys.insert(code).inserted else { return }
            } else {
                guard heldKeys.remove(code) != nil else { return }
            }
            onKey?(KeyStroke(code: code, isDown: isDown))
        }
    }
}
