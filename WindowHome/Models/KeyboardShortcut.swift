import AppKit
import Carbon.HIToolbox
import CoreGraphics

struct KeyboardShortcut: Codable, Equatable {
    static let saveHomeDefault = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | optionKey | controlKey))
    static let restoreHomeDefault = KeyboardShortcut(keyCode: UInt32(kVK_Return), modifiers: UInt32(cmdKey | optionKey))
    static let undoHomeDefault = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey | optionKey | controlKey))
    static let redoHomeDefault = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
    static let restoreAllDefault = KeyboardShortcut(keyCode: UInt32(kVK_Return), modifiers: UInt32(cmdKey | optionKey | controlKey))
    static let centerAndSaveHomeDefault = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | controlKey))
    static let moveToNextDisplayDefault = KeyboardShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(cmdKey | optionKey | controlKey))
    static let moveToPreviousDisplayDefault = KeyboardShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey | optionKey | controlKey))
    static let increaseWidthDefault = KeyboardShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
    static let decreaseWidthDefault = KeyboardShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
    static let increaseHeightDefault = KeyboardShortcut(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
    static let decreaseHeightDefault = KeyboardShortcut(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
    static let snapLeftDefault = KeyboardShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey | optionKey))
    static let snapRightDefault = KeyboardShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(cmdKey | optionKey))
    static let snapTopDefault = KeyboardShortcut(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(cmdKey | optionKey))
    static let snapBottomDefault = KeyboardShortcut(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(cmdKey | optionKey))
    static let snapFullScreenDefault = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | optionKey))
    static let snapTopLeftDefault = KeyboardShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey | controlKey))
    static let snapTopRightDefault = KeyboardShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(cmdKey | controlKey))
    static let snapBottomLeftDefault = KeyboardShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey | controlKey | shiftKey))
    static let snapBottomRightDefault = KeyboardShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(cmdKey | controlKey | shiftKey))

    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        guard carbonModifiers != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
    }

    init?(event: CGEvent) {
        var carbonModifiers: UInt32 = 0
        let flags = event.flags
        if flags.contains(.maskCommand) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.maskAlternate) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.maskControl) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.maskShift) { carbonModifiers |= UInt32(shiftKey) }
        guard carbonModifiers != 0 else { return nil }
        self.init(keyCode: UInt32(event.getIntegerValueField(.keyboardEventKeycode)), modifiers: carbonModifiers)
    }

    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyName(for: keyCode)
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F", UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
            UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R", UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z", UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}
