import AppKit
import ApplicationServices

final class Inserter {
    private var previous: [[NSPasteboard.PasteboardType: Data]]?
    private var generation: Int?
    func restore() -> Bool {
        let board = NSPasteboard.general
        guard let previous, board.changeCount == generation else { self.previous = nil; return false }
        let items = previous.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        board.clearContents()
        if !items.isEmpty { board.writeObjects(items) }
        self.previous = nil; generation = nil
        return true
    }
    func paste(_ text: String, targetPID: pid_t) throws {
        guard AXIsProcessTrusted() else { throw DictationError.message("Accessibility access is needed to paste. Your transcript is ready to copy.") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            throw DictationError.message("Focus changed. Select your intended input and copy the transcript manually.")
        }
        let board = NSPasteboard.general
        previous = (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        board.clearContents(); board.writeObjects([item])
        generation = board.changeCount
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw DictationError.message("Could not paste. The transcript is available to copy.")
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
}
