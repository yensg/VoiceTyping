import AppKit
import ApplicationServices
import DictationCore

final class Hotkey {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDisabled: (() -> Void)?
    var recording = false
    var keyCode: CGKeyCode = 61
    private var optionState = RightOptionState()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func enable() -> Bool {
        disable()
        guard AXIsProcessTrusted() else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                         callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<Hotkey>.fromOpaque(pointer).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                owner.optionState.reset(); DispatchQueue.main.async { owner.onDisabled?() }
                return Unmanaged.passUnretained(event)
            }
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if type == .keyDown && key == 53 && owner.recording {
                owner.recording = false; DispatchQueue.main.async { owner.onCancel?() }; return nil
            }
            if type == .flagsChanged,
               let pressed = owner.optionState.update(keyCode: key, flags: event.flags.rawValue) {
                DispatchQueue.main.async {
                    if pressed { owner.onDown?() } else { owner.onUp?() }
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func disable() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil; optionState.reset()
    }
    deinit { disable() }
}
