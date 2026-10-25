import AppKit

public final class RecordingPanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

private final class WaveformView: NSView {
    var title = "Listening…"
    var levels = Array(repeating: CGFloat(0), count: 24)
    var processing = false
    var result = false
    var error = false
    var tick = 0

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 22, yRadius: 22)
        NSColor(calibratedWhite: 0.09, alpha: 0.97).setFill(); shape.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke(); shape.lineWidth = 1; shape.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center; paragraph.lineBreakMode = .byWordWrapping
        let color: NSColor = error ? .systemOrange : .white
        if result {
            (title as NSString).draw(in: NSRect(x: 20, y: 25, width: bounds.width - 40, height: 48),
                withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: color, .paragraphStyle: paragraph])
            return
        }
        let parts = title.components(separatedBy: " · ")
        let heading = parts.first ?? title
        let subtitle = parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : "Your audio stays on this Mac"
        (heading as NSString).draw(in: NSRect(x: 16, y: 69, width: bounds.width - 32, height: 21),
            withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        (subtitle as NSString).draw(in: NSRect(x: 16, y: 12, width: bounds.width - 32, height: 17),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.82), .paragraphStyle: paragraph])
        if processing {
            for i in 0..<3 {
                let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                NSColor.white.withAlphaComponent(still || (tick / 5) % 3 == i ? 1 : 0.35).setFill()
                NSBezierPath(ovalIn: NSRect(x: bounds.midX - 16 + CGFloat(i * 12), y: 43, width: 7, height: 7)).fill()
            }
        } else {
            NSColor(calibratedRed: 0.52, green: 0.86, blue: 0.71, alpha: 1).setFill()
            let width: CGFloat = 4, gap: CGFloat = 4
            let start = (bounds.width - CGFloat(levels.count) * (width + gap) + gap) / 2
            for (i, level) in levels.enumerated() {
                let height = 3 + level * 25
                NSBezierPath(roundedRect: NSRect(x: start + CGFloat(i) * (width + gap), y: 47 - height / 2, width: width, height: height), xRadius: 2, yRadius: 2).fill()
            }
        }
    }
}

public final class RecordingOverlay {
    public let panel: RecordingPanel
    private let waveform = WaveformView(frame: NSRect(x: 0, y: 0, width: 360, height: 104))
    private var timer: Timer?
    private var dismissal: Timer?

    public init() {
        panel = RecordingPanel(contentRect: waveform.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.contentView = waveform
    }

    private func present() {
        panel.setAccessibilityLabel(waveform.title)
        dismissal?.invalidate(); dismissal = nil
        if !panel.isVisible {
            let point = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 28))
            }
        }
        // Never activate NSApp or make this panel key/main: the input keeps focus.
        panel.orderFrontRegardless()
    }

    public func showRecording(levelProvider: @escaping () -> Float, title: String = "Listening · release Right Option to finish") {
        timer?.invalidate()
        waveform.title = title; waveform.processing = false; waveform.result = false; waveform.error = false
        waveform.levels = Array(repeating: 0, count: 24)
        present()
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let value = levelProvider()
            let level = value.isFinite ? max(0, min(1, CGFloat(value))) : 0
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                waveform.levels = Array(repeating: level, count: 24)
            } else {
                waveform.levels.removeFirst(); waveform.levels.append(level)
            }
            waveform.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
        waveform.needsDisplay = true
    }

    public func showTranscribing() {
        timer?.invalidate()
        waveform.title = "Transcribing on your Mac…"; waveform.processing = true; waveform.result = false
        present()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { waveform.needsDisplay = true; return }
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            waveform.tick += 1; waveform.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
        waveform.needsDisplay = true
    }

    public func showResult(_ title: String, isError: Bool = false) {
        timer?.invalidate(); timer = nil
        waveform.title = title; waveform.result = true; waveform.error = isError
        present(); waveform.needsDisplay = true
        dismissal = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in self?.hide() }
    }

    public func showPreview() {
        showRecording(levelProvider: { Float(0.3 + abs(sin(Date.timeIntervalSinceReferenceDate * 5)) * 0.6) }, title: "Preview · microphone is not recording")
        dismissal = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.hide() }
    }

    public func hide() {
        timer?.invalidate(); timer = nil; dismissal?.invalidate(); dismissal = nil
        panel.orderOut(nil)
    }
}
