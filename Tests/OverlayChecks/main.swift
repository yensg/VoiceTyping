import AppKit
import DictationUI

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let overlay = RecordingOverlay()
precondition(!overlay.panel.canBecomeKey, "Recording feedback must never take keyboard focus")
precondition(!overlay.panel.canBecomeMain, "Recording feedback must never become the main window")
precondition(overlay.panel.styleMask.contains(.nonactivatingPanel))
precondition(overlay.panel.ignoresMouseEvents, "Feedback must not intercept clicks into a session")
precondition(!overlay.panel.hidesOnDeactivate)
precondition(!overlay.panel.isVisible, "Constructing feedback must not display it")
print("Overlay focus checks passed")
