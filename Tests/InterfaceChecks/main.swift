import AppKit
import DictationUI
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let view = VoiceTypingView(frame: NSRect(x: 0, y: 0, width: 900, height: 710))
view.vocabulary.stringValue = "Codex, GitHub"
view.transcript.string = "Keep this draft."
view.selectPage(.settings)
view.selectPage(.voiceTest)
view.selectPage(.dictation)
precondition(view.vocabulary.stringValue == "Codex, GitHub")
precondition(view.transcript.string == "Keep this draft.")
precondition(view.selectedPage == .dictation)
precondition(VoiceTypingView.menuImage(recording: false, processing: false)?.isTemplate == true)
view.statusLabel.stringValue = String(repeating: "Focus changed. Draft kept for review. ", count: 3)
view.layoutSubtreeIfNeeded()
precondition(view.statusLabel.frame.height >= 36)
print("Interface navigation, draft preservation and template icon checks passed")

if CommandLine.arguments.contains("--render") {
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/ui-previews")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
        view.appearance = NSAppearance(named: appearance)
        for page in VoiceTypingView.Page.allCases {
            view.selectPage(page)
            view.statusLabel.stringValue = "Focus your session, hold Right Option, then release to insert."
            view.permissionsLabel.stringValue = "Interface preview · no microphone recording"
            view.updateState(recording: false, processing: false, ready: true)
            view.transcript.string = ""
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot render preview") }
            view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name)-\(page.rawValue).png"))
        }
    }
    print("Rendered native interface previews")
}
