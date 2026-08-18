import ApplicationServices

enum AccessibilityPermissionService {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// macOS shows its Privacy & Security pane; the user must explicitly enable WindowHome there.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
