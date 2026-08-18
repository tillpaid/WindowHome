import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: KeyboardShortcut?
    let onRecord: (KeyboardShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        ShortcutRecorderNSView(shortcut: shortcut, onRecord: onRecord)
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.shortcut = shortcut
        nsView.onRecord = onRecord
    }
}

final class ShortcutRecorderNSView: NSView {
    var shortcut: KeyboardShortcut? { didSet { needsDisplay = true } }
    var onRecord: (KeyboardShortcut) -> Void
    private var isRecording = false { didSet { needsDisplay = true } }

    init(shortcut: KeyboardShortcut?, onRecord: @escaping (KeyboardShortcut) -> Void) {
        self.shortcut = shortcut
        self.onRecord = onRecord
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 125, height: 28) }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 { isRecording = false; return }
        guard let shortcut = KeyboardShortcut(event: event) else { return }
        onRecord(shortcut)
        isRecording = false
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let text = isRecording ? "Press shortcut…" : (shortcut?.displayString ?? "Set shortcut")
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        text.draw(in: bounds.insetBy(dx: 8, dy: 5), withAttributes: attributes)
    }
}
