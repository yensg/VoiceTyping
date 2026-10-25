import AppKit
import AVFoundation
import ApplicationServices
import DictationCore
import DictationUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var window: NSWindow!
    private var interface: VoiceTypingView!
    private var statusLabel: NSTextField!
    private var comparisonButton: NSButton!
    private var permissionsLabel: NSTextField!
    private var transcript: NSTextView!
    private var vocabulary: NSTextField!
    private var language: NSPopUpButton!
    private var keyChoice: NSPopUpButton!
    private let recorder = AudioRecorder()
    private let overlay = RecordingOverlay()
    private let transcriber = Transcriber()
    private let transcriptionWork = DispatchGroup()
    private let hotkey = Hotkey()
    private let inserter = Inserter()
    private var gate = SessionGate()
    private var token: UUID?
    private var targetPID: pid_t = 0
    private var timeout: Timer?
    private var busy = false
    private var terminating = false
    private var shortcutReady = false
    private var isRecording = false
    private var activationObserver: NSObjectProtocol?
    private var targetLost = false
    private var comparisonRecording = false
    private var comparisonAudio: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit VoiceTyping", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu; mainMenu.addItem(appItem); NSApp.mainMenu = mainMenu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuIcon()
        let menu = NSMenu()
        menu.addItem(withTitle: "Open VoiceTyping", action: #selector(show), keyEquivalent: "")
        menu.addItem(withTitle: "Preview recording indicator", action: #selector(previewIndicator), keyEquivalent: "")
        menu.addItem(withTitle: "Cancel current recording", action: #selector(cancel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit VoiceTyping", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        makeWindow()
        hotkey.onDown = { [weak self] in self?.start() }
        hotkey.onUp = { [weak self] in self?.stop() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
        hotkey.onDisabled = { [weak self] in
            self?.shortcutReady = false; self?.cancel(); self?.setStatus("Hotkey was disabled by macOS. Re-enable it here; secure input may be active.")
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] event in
            guard let self, self.busy, let app = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.processIdentifier != self.targetPID { self.targetLost = true }
        }
        updatePermissions()
        if keyChoice.indexOfSelectedItem == 1 { enableHotkey() }
        show()
    }

    private func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 710), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "VoiceTyping"
        window.isReleasedWhenClosed = false
        window.center()
        interface = VoiceTypingView(frame: NSRect(x: 0, y: 0, width: 900, height: 710))
        window.contentView = interface
        statusLabel = interface.statusLabel; permissionsLabel = interface.permissionsLabel
        transcript = interface.transcript; vocabulary = interface.vocabulary
        language = interface.language; keyChoice = interface.keyChoice
        comparisonButton = interface.comparisonButton
        keyChoice.selectItem(at: UserDefaults.standard.integer(forKey: "hotkeyIndex") == 1 ? 1 : 0)
        keyChoice.target = self; keyChoice.action = #selector(changeKey)
        language.selectItem(at: max(0, min(2, UserDefaults.standard.integer(forKey: "languageIndex"))))
        vocabulary.stringValue = UserDefaults.standard.string(forKey: "vocabulary") ?? ""
        for (control, action) in [
            (interface.microphoneButton, #selector(microphone)),
            (interface.accessibilityButton, #selector(accessibility)),
            (interface.hotkeyButton, #selector(enableHotkey)),
            (interface.copyButton, #selector(copyDraft)),
            (interface.restoreButton, #selector(restoreClipboard)),
            (interface.cancelButton, #selector(cancel)),
            (interface.comparisonCancelButton, #selector(cancel)),
            (interface.previewButton, #selector(previewIndicator)),
            (interface.comparisonButton, #selector(recordComparison))
        ] { control.target = self; control.action = action }
    }

    private func updateMenuIcon() {
        item.button?.title = ""
        item.button?.image = VoiceTypingView.menuImage(recording: isRecording, processing: busy && !isRecording)
        let state = isRecording ? "Recording" : busy ? "Transcribing" : "Dictation"
        item.button?.toolTip = "VoiceTyping — " + state
        item.button?.setAccessibilityLabel("VoiceTyping — " + state)
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
        updateMenuIcon()
        interface.updateState(recording: isRecording, processing: busy && !isRecording,
                              ready: shortcutReady)
        statusLabel.textColor = isRecording ? .systemRed : .labelColor
        if let comparisonButton {
            comparisonButton.title = isRecording && comparisonRecording ? "Stop recording" : (busy ? "Transcribing…" : "Record voice sample")
            comparisonButton.contentTintColor = isRecording ? .systemRed : .controlAccentColor
            comparisonButton.isEnabled = !busy || (isRecording && comparisonRecording)
        }
    }
    private func updatePermissions() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "enabled" : "needed"
        interface.microphoneButton.isEnabled = mic != "enabled"
        interface.microphoneButton.title = mic == "enabled" ? "Microphone enabled" : "Enable microphone"
        interface.accessibilityButton.isEnabled = !AXIsProcessTrusted()
        interface.accessibilityButton.title = AXIsProcessTrusted() ? "Accessibility enabled" : "Enable Accessibility"
        permissionsLabel.stringValue = "Microphone: \(mic) · Accessibility: \(AXIsProcessTrusted() ? "enabled" : "needed")"
    }
    @objc private func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); updatePermissions() }
    @objc private func microphone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in DispatchQueue.main.async { self?.updatePermissions() } }
    }
    @objc private func accessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options); updatePermissions()
    }
    @objc private func changeKey() {
        if busy { cancel() }
        UserDefaults.standard.set(keyChoice.indexOfSelectedItem, forKey: "hotkeyIndex")
        enableHotkey()
    }
    @objc private func enableHotkey() {
        guard !terminating else { return }
        shortcutReady = false
        updatePermissions()
        guard keyChoice.indexOfSelectedItem == 1 else { hotkey.disable(); setStatus("Global shortcut disabled. Choose a key before enabling."); return }
        hotkey.keyCode = 61
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { setStatus("Grant microphone access first."); return }
        guard hotkey.enable() else { setStatus("Accessibility access is needed. If already enabled, a rebuild may require re-approval."); return }
        shortcutReady = true
        setStatus("Ready. Focus your input, then hold \(keyChoice.titleOfSelectedItem ?? "Right Option").")
    }

    @objc private func previewIndicator() { if !busy { overlay.showPreview() } }
    @objc private func recordComparison() {
        if isRecording && comparisonRecording { stop() }
        else { start(comparison: true) }
    }
    private func start(comparison: Bool = false) {
        guard !busy, !terminating else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, comparison || AXIsProcessTrusted() else {
            setStatus("Microphone and Accessibility permissions are required."); return
        }
        guard let target = NSWorkspace.shared.frontmostApplication, (comparison || target.processIdentifier != ProcessInfo.processInfo.processIdentifier) else {
            setStatus("First focus the input where you want the draft."); return
        }
        do {
            try recorder.start()
            transcriptionWork.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { transcriptionWork.leave() }
                transcriber.warm()
            }
            comparisonRecording = comparison; comparisonAudio = nil
            targetPID = target.processIdentifier; targetLost = false
            token = gate.begin(pid: targetPID); busy = true; isRecording = true; hotkey.recording = true
            overlay.showRecording(levelProvider: { [weak self] in self?.recorder.level ?? 0 },
                                  title: comparison ? "Listening · click Stop recording to finish" : "Listening · release Right Option to finish")
            updateMenuIcon()
            setStatus(comparison ? "● RECORDING — speak now. Click Stop recording when finished." : "Recording for \(target.localizedName ?? "selected app"). Release to transcribe; Escape cancels.")
            timeout = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in self?.stop() }
        } catch { setStatus(error.localizedDescription) }
    }

    private func stop() {
        guard isRecording, let token else { return }
        timeout?.invalidate(); timeout = nil; isRecording = false; hotkey.recording = false
        let started = Date()
        overlay.showTranscribing()
        do {
            let samples = try recorder.stop()
            if comparisonRecording {
                let config = try EngineConfiguration.load()
                let directory = URL(fileURLWithPath: config.testDirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let url = directory.appendingPathComponent("comparison-" + UUID().uuidString + ".wav")
                try Transcriber.wav(samples).write(to: url, options: .atomic)
                comparisonAudio = url
            }
            guard AudioGate.accepts(samples, sampleRate: 16000) else {
                busy = false; gate.cancel(); self.token = nil; updateMenuIcon()
                overlay.showResult("No speech detected")
                setStatus("No clear speech detected. Nothing was inserted."); return
            }
            let languages = ["en", "zh", "auto"]
            let selected = max(0, min(2, language.indexOfSelectedItem))
            UserDefaults.standard.set(selected, forKey: "languageIndex")
            let terms = vocabulary.stringValue
            UserDefaults.standard.set(terms, forKey: "vocabulary")
            updateMenuIcon(); setStatus("Transcribing locally…")
            transcriber.prepare(id: token)
            transcriptionWork.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { transcriptionWork.leave() }
                let result = Result { try self.transcriber.transcribe(id: token, samples: samples, language: languages[selected], vocabulary: terms) }
                DispatchQueue.main.async { self.finish(result, token: token, started: started) }
            }
        } catch { busy = false; gate.cancel(); self.token = nil; updateMenuIcon(); overlay.showResult("Recording failed — open VoiceTyping", isError: true); setStatus(error.localizedDescription) }
    }

    private func finish(_ result: Result<String, Error>, token: UUID, started: Date) {
        guard self.token == token else { return }
        busy = false; updateMenuIcon()
        defer { gate.cancel(); self.token = nil }
        switch result {
        case .failure(let error): overlay.showResult("Transcription failed — open VoiceTyping", isError: true); setStatus(error.localizedDescription)
        case .success(let text):
            let draft = sanitizeDraft(text)
            guard !draft.isEmpty else { overlay.showResult("No speech detected"); setStatus("No speech transcript returned. Nothing inserted."); return }
            transcript.string = draft
            if comparisonRecording {
                overlay.showResult("Sample ready in VoiceTyping")
                do {
                    guard let comparisonAudio else { throw DictationError.message("Audio path is missing.") }
                    try draft.write(to: comparisonAudio.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
                    setStatus("Comparison complete. Audio and transcript saved locally; nothing pasted.")
                } catch {
                    setStatus("Audio saved, but transcript file could not be saved. Copy the draft below. Nothing pasted.")
                }
                return
            }
            guard !targetLost, gate.accepts(token: token, pid: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1) else {
                overlay.showResult("Draft kept — focus changed", isError: true)
                setStatus("Focus changed. Draft is ready here; copy it to your intended input."); return
            }
            do {
                try inserter.paste(draft, targetPID: targetPID)
                overlay.hide()
                setStatus(String(format: "Pasted (unconfirmed) in %.1f s. Review the draft before sending.", Date().timeIntervalSince(started)))
            } catch { overlay.showResult("Draft ready — copy from VoiceTyping", isError: true); setStatus(error.localizedDescription) }
        }
    }

    @objc private func cancel() {
        overlay.hide()
        timeout?.invalidate(); timeout = nil; recorder.cancel(); transcriber.cancel(); gate.cancel()
        token = nil; busy = false; isRecording = false; hotkey.recording = false
        updateMenuIcon(); setStatus("Cancelled. Nothing inserted.")
    }
    @objc private func restoreClipboard() {
        setStatus(inserter.restore() ? "Previous clipboard restored." : "Clipboard changed or no previous clipboard is available; left unchanged.")
    }
    @objc private func copyDraft() {
        let text = sanitizeDraft(transcript.string)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        setStatus("Draft copied. Paste it into your chosen input and review before sending.")
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true; hotkey.disable(); cancel()
        transcriptionWork.notify(queue: .global()) { [self] in
            transcriber.close()
            DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
