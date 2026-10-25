import AppKit

private final class Surface: NSView {
    var color: NSColor = .windowBackgroundColor
    var radius: CGFloat = 0
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

private final class NavigationButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        if state == .on {
            NSColor.systemGreen.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        super.draw(dirtyRect)
    }
}

/// Presentation only. AppDelegate owns recording, permissions and insertion.
public final class VoiceTypingView: NSView {
    public enum Page: Int, CaseIterable { case dictation, settings, voiceTest }
    public private(set) var selectedPage: Page = .dictation
    public let statusLabel = VoiceTypingView.label("Focus your session, then hold Right Option.", size: 13)
    public let permissionsLabel = VoiceTypingView.label("Checking permissions…", size: 12, secondary: true)
    public let transcript = NSTextView()
    public let vocabulary = NSTextField(string: "")
    public let language = NSPopUpButton()
    public let keyChoice = NSPopUpButton()
    public let microphoneButton = NSButton(title: "Enable microphone", target: nil, action: nil)
    public let accessibilityButton = NSButton(title: "Enable Accessibility", target: nil, action: nil)
    public let hotkeyButton = NSButton(title: "Enable / refresh shortcut", target: nil, action: nil)
    public let copyButton = NSButton(title: "Copy text", target: nil, action: nil)
    public let restoreButton = NSButton(title: "Restore clipboard", target: nil, action: nil)
    public let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    public let comparisonCancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    public let previewButton = NSButton(title: "Preview indicator", target: nil, action: nil)
    public let comparisonButton = NSButton(title: "Record voice sample", target: nil, action: nil)
    private let stateHeading = VoiceTypingView.label("Ready to listen", size: 16, weight: .semibold)
    private let stateIcon = NSImageView()
    private var pages: [NSView] = []
    private var navigation: [NSButton] = []
    private let accent = NSColor(name: "VoiceTypingAccent") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.52, green: 0.86, blue: 0.71, alpha: 1)
            : NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.29, alpha: 1)
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
    }
    public override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        selectPage(.dictation)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public static func menuImage(recording: Bool, processing: Bool) -> NSImage? {
        let name = recording ? "record.circle" : processing ? "ellipsis" : "waveform"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "VoiceTyping")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        image?.isTemplate = true
        return image
    }

    public func updateState(recording: Bool, processing: Bool, ready: Bool) {
        stateHeading.stringValue = recording ? "Listening to you" : processing ? "Turning speech into text" : ready ? "Ready to listen" : "Finish setup in Settings"
        stateIcon.image = NSImage(systemSymbolName: recording ? "waveform" : processing ? "ellipsis.circle" : ready ? "checkmark.circle.fill" : "exclamationmark.circle", accessibilityDescription: nil)
        stateIcon.contentTintColor = recording ? .systemRed : ready || processing ? accent : .secondaryLabelColor
    }

    public func selectPage(_ page: Page) {
        selectedPage = page
        for (i, view) in pages.enumerated() { view.isHidden = i != page.rawValue }
        for (i, button) in navigation.enumerated() {
            button.state = i == page.rawValue ? .on : .off
            button.contentTintColor = i == page.rawValue ? accent : .secondaryLabelColor
        }
    }
    @objc private func navigate(_ sender: NSButton) {
        if let page = Page(rawValue: sender.tag) { selectPage(page) }
    }

    private static func label(_ text: String, size: CGFloat = 14, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
    private func column(_ views: [NSView], spacing: CGFloat = 14) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        return stack
    }
    private func row(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .horizontal
        stack.alignment = .centerY; stack.spacing = spacing
        return stack
    }
    private func pin(_ child: NSView, to parent: NSView, inset: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }
    private func divider() -> NSBox { let line = NSBox(); line.boxType = .separator; return line }
    private func fullWidth(_ children: [NSView], in stack: NSStackView) {
        for child in children { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }
    private func heading(_ title: String, subtitle: String) -> NSStackView {
        column([Self.label(title, size: 29, weight: .semibold), Self.label(subtitle, secondary: true)], spacing: 8)
    }
    private func build() {
        let sidebar = Surface(); sidebar.color = .underPageBackgroundColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false; addSubview(sidebar)
        NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo: leadingAnchor), sidebar.topAnchor.constraint(equalTo: topAnchor), sidebar.bottomAnchor.constraint(equalTo: bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 184)])
        let mark = NSImageView(image: NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!)
        mark.contentTintColor = accent; mark.widthAnchor.constraint(equalToConstant: 27).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let brand = row([mark, Self.label("VoiceTyping", size: 17, weight: .semibold)], spacing: 7)
        let nav = column([], spacing: 8)
        for (i, entry) in [("Dictation", "mic"), ("Settings", "slider.horizontal.3"), ("Voice test", "waveform.path")].enumerated() {
            let button = NavigationButton(title: entry.0, target: self, action: #selector(navigate(_:)))
            button.image = NSImage(systemSymbolName: entry.1, accessibilityDescription: nil)
            button.imagePosition = .imageLeading; button.font = .systemFont(ofSize: 14, weight: .medium)
            button.bezelStyle = .recessed; button.setButtonType(.pushOnPushOff); button.isBordered = false
            button.tag = i; button.alignment = .left
            button.widthAnchor.constraint(equalToConstant: 152).isActive = true
            button.heightAnchor.constraint(equalToConstant: 39).isActive = true
            button.setAccessibilityLabel(entry.0)
            navigation.append(button); nav.addArrangedSubview(button)
        }
        let sideStack = column([brand, nav], spacing: 34)
        sideStack.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(sideStack)
        NSLayoutConstraint.activate([sideStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 30), sideStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16)])
        let privacy = Self.label("On your Mac.\nNo account. No cloud.", size: 12, secondary: true)
        privacy.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(privacy)
        NSLayoutConstraint.activate([privacy.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 24), privacy.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -24)])

        let content = NSView(); content.translatesAutoresizingMaskIntoConstraints = false; addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 36), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36), content.topAnchor.constraint(equalTo: topAnchor, constant: 28), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)])
        let body = NSView(); body.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(body)
        let status = column([row([stateIcon, stateHeading]), statusLabel, permissionsLabel], spacing: 6)
        stateIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        stateIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        status.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(status)
        statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        fullWidth([statusLabel, permissionsLabel], in: status)
        NSLayoutConstraint.activate([body.topAnchor.constraint(equalTo: content.topAnchor), body.leadingAnchor.constraint(equalTo: content.leadingAnchor), body.trailingAnchor.constraint(equalTo: content.trailingAnchor), body.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -18), status.leadingAnchor.constraint(equalTo: content.leadingAnchor), status.trailingAnchor.constraint(equalTo: content.trailingAnchor), status.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        pages = [dictationPage(), settingsPage(), testPage()]
        for page in pages { pin(page, to: body) }
        updateState(recording: false, processing: false, ready: false)
    }
    private func page(_ stack: NSStackView) -> NSView {
        let view = NSView(); stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor), stack.topAnchor.constraint(equalTo: view.topAnchor)])
        return view
    }
    private func dictationPage() -> NSView {
        let header = heading("Speak. Your words appear.", subtitle: "Right in the session where you’re working.")
        let keySurface = Surface(); keySurface.color = .controlBackgroundColor; keySurface.radius = 15
        let key = Self.label("⌥", size: 42, weight: .regular); key.alignment = .center
        pin(key, to: keySurface, inset: 12)
        keySurface.widthAnchor.constraint(equalToConstant: 88).isActive = true
        keySurface.heightAnchor.constraint(equalToConstant: 76).isActive = true
        let keyRow = row([keySurface, column([Self.label("Hold Right Option", size: 19, weight: .medium), Self.label("Speak naturally. Release to insert.", secondary: true)], spacing: 5)], spacing: 22)
        let instructions = Self.label("1  Focus your session     2  Hold & speak     3  Release to insert", size: 13, secondary: true)
        let latest = Self.label("Latest draft", size: 16, weight: .semibold)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        scroll.drawsBackground = true; scroll.backgroundColor = .textBackgroundColor
        transcript.frame = NSRect(x: 0, y: 0, width: 600, height: 148)
        transcript.isEditable = true; transcript.isRichText = false; transcript.font = .systemFont(ofSize: 15)
        transcript.textColor = .textColor; transcript.backgroundColor = .textBackgroundColor
        transcript.textContainerInset = NSSize(width: 13, height: 13)
        transcript.isVerticallyResizable = true; transcript.isHorizontallyResizable = false
        transcript.autoresizingMask = [.width]; transcript.textContainer?.widthTracksTextView = true
        transcript.setAccessibilityLabel("Latest draft")
        scroll.documentView = transcript; scroll.heightAnchor.constraint(equalToConstant: 148).isActive = true
        copyButton.bezelStyle = .rounded; copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeading
        let actions = row([copyButton, restoreButton, cancelButton])
        let note = Self.label("Text is inserted, never sent. Review it before pressing Enter.", size: 12, secondary: true)
        let stack = column([header, keyRow, instructions, divider(), latest, scroll, actions, note], spacing: 16)
        stack.setCustomSpacing(28, after: header); stack.setCustomSpacing(24, after: keyRow)
        fullWidth([header, instructions, scroll, note], in: stack)
        return page(stack)
    }
    private func settingsPage() -> NSView {
        keyChoice.addItems(withTitles: ["Disabled", "Right Option"])
        language.addItems(withTitles: ["English", "Chinese", "Auto detect"])
        keyChoice.setAccessibilityLabel("Dictation shortcut"); language.setAccessibilityLabel("Speech language")
        vocabulary.placeholderString = "Codex, GitHub, names you use often…"
        vocabulary.setAccessibilityLabel("Vocabulary hints")
        let header = heading("Make it yours.", subtitle: "A few preferences. The same simple workflow.")
        let shortcut = column([Self.label("Shortcut & language", size: 16, weight: .semibold), row([Self.label("Hold key"), keyChoice, Self.label("Language"), language]), hotkeyButton], spacing: 10)
        let words = column([Self.label("Your vocabulary", size: 16, weight: .semibold), Self.label("Names and terms to help recognition. These are hints, not guaranteed corrections.", size: 13, secondary: true), vocabulary], spacing: 8)
        let access = column([Self.label("Permissions", size: 16, weight: .semibold), Self.label("Microphone records your voice. Accessibility enables the shortcut and pastes your text.", size: 13, secondary: true), row([microphoneButton, accessibilityButton])], spacing: 8)
        let engine = Self.label("Speech recognition runs locally with Whisper large-v3-turbo. Your normal dictation audio is temporary.", size: 12, secondary: true)
        let stack = column([header, shortcut, divider(), words, divider(), access, engine], spacing: 20)
        fullWidth([header, shortcut, words, access, engine], in: stack)
        vocabulary.widthAnchor.constraint(equalTo: words.widthAnchor).isActive = true
        return page(stack)
    }
    private func testPage() -> NSView {
        comparisonButton.bezelStyle = .rounded
        comparisonButton.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        comparisonButton.imagePosition = .imageLeading; comparisonButton.font = .systemFont(ofSize: 15, weight: .semibold)
        let header = heading("Find your voice.", subtitle: "Check your microphone and try a short recording.")
        let copy = Self.label("Click Record voice sample, speak, then click Stop recording. The result appears in Latest draft on the Dictation tab.")
        let retained = Self.label("Voice tests save audio and text locally for comparison. They are not pasted into your session or uploaded. Cancel discards an active recording.", size: 13, secondary: true)
        let footer = Self.label("Everyday dictation uses Right Option in your session. This test button is only for microphone and transcription checks.", size: 13, secondary: true)
        let stack = column([header, copy, row([comparisonButton, comparisonCancelButton]), retained, divider(), Self.label("Recording indicator", size: 16, weight: .semibold), Self.label("Preview the floating waveform without using your microphone.", size: 13, secondary: true), previewButton, footer], spacing: 20)
        fullWidth([header, copy, retained, footer], in: stack)
        return page(stack)
    }
}
