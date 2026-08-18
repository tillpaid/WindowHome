import Foundation

enum MouseSnapMode: String, CaseIterable, Identifiable {
    case off
    case edgeAndOption
    case optionOnly

    var id: String { rawValue }
}

enum KeyboardShortcutPreferences {
    private static let saveHomeKey = "saveHomeShortcut"
    private static let restoreHomeKey = "restoreHomeShortcut"
    private static let undoHomeKey = "undoHomeShortcut"
    private static let redoHomeKey = "redoHomeShortcut"
    private static let restoreAllKey = "restoreAllShortcut"
    private static let centerAndSaveHomeKey = "centerAndSaveHomeShortcut"
    private static let moveToNextDisplayKey = "moveToNextDisplayShortcut"
    private static let moveToPreviousDisplayKey = "moveToPreviousDisplayShortcut"
    private static let snapLeftKey = "snapLeftShortcut"
    private static let snapRightKey = "snapRightShortcut"
    private static let snapTopKey = "snapTopShortcut"
    private static let snapBottomKey = "snapBottomShortcut"
    private static let snapFullScreenKey = "snapFullScreenShortcut"
    private static let snapTopLeftKey = "snapTopLeftShortcut"
    private static let snapTopRightKey = "snapTopRightShortcut"
    private static let snapBottomLeftKey = "snapBottomLeftShortcut"
    private static let snapBottomRightKey = "snapBottomRightShortcut"
    private static let increaseWidthKey = "increaseWidthShortcut"
    private static let decreaseWidthKey = "decreaseWidthShortcut"
    private static let increaseHeightKey = "increaseHeightShortcut"
    private static let decreaseHeightKey = "decreaseHeightShortcut"
    private static let snapPaddingKey = "snapPadding"
    private static let resizeStepKey = "resizeStep"
    private static let restoreFullHomeAfterDisplayMoveKey = "restoreFullHomeAfterDisplayMoveEnabled"
    private static let automaticSaveAfterMouseMoveEnabledKey = "automaticSaveAfterMouseMoveEnabled"
    private static let mouseSnapEnabledKey = "mouseSnapEnabled"
    private static let mouseSnapModeKey = "mouseSnapMode"
    private static let showMouseSnapAreasKey = "showMouseSnapAreas"

    private static func clearedKey(for key: String) -> String { "\(key)Cleared" }

    static func loadSaveHome() -> KeyboardShortcut? { loadShortcut(forKey: saveHomeKey, defaultShortcut: .saveHomeDefault) }
    static func loadRestoreHome() -> KeyboardShortcut? { loadShortcut(forKey: restoreHomeKey, defaultShortcut: .restoreHomeDefault) }
    static func loadUndoHome() -> KeyboardShortcut? { loadShortcut(forKey: undoHomeKey, defaultShortcut: .undoHomeDefault) }
    static func loadRedoHome() -> KeyboardShortcut? { loadShortcut(forKey: redoHomeKey, defaultShortcut: .redoHomeDefault) }
    static func loadRestoreAll() -> KeyboardShortcut? { loadShortcut(forKey: restoreAllKey, defaultShortcut: .restoreAllDefault) }
    static func loadCenterAndSaveHome() -> KeyboardShortcut? { loadShortcut(forKey: centerAndSaveHomeKey, defaultShortcut: .centerAndSaveHomeDefault) }
    static func loadMoveToNextDisplay() -> KeyboardShortcut? { loadShortcut(forKey: moveToNextDisplayKey, defaultShortcut: .moveToNextDisplayDefault) }
    static func loadMoveToPreviousDisplay() -> KeyboardShortcut? { loadShortcut(forKey: moveToPreviousDisplayKey, defaultShortcut: .moveToPreviousDisplayDefault) }
    static func loadSnapLeft() -> KeyboardShortcut? { loadShortcut(forKey: snapLeftKey, defaultShortcut: .snapLeftDefault) }
    static func loadSnapRight() -> KeyboardShortcut? { loadShortcut(forKey: snapRightKey, defaultShortcut: .snapRightDefault) }
    static func loadSnapTop() -> KeyboardShortcut? { loadShortcut(forKey: snapTopKey, defaultShortcut: .snapTopDefault) }
    static func loadSnapBottom() -> KeyboardShortcut? { loadShortcut(forKey: snapBottomKey, defaultShortcut: .snapBottomDefault) }
    static func loadSnapFullScreen() -> KeyboardShortcut? { loadShortcut(forKey: snapFullScreenKey, defaultShortcut: .snapFullScreenDefault) }
    static func loadSnapTopLeft() -> KeyboardShortcut? { loadShortcut(forKey: snapTopLeftKey, defaultShortcut: .snapTopLeftDefault) }
    static func loadSnapTopRight() -> KeyboardShortcut? { loadShortcut(forKey: snapTopRightKey, defaultShortcut: .snapTopRightDefault) }
    static func loadSnapBottomLeft() -> KeyboardShortcut? { loadShortcut(forKey: snapBottomLeftKey, defaultShortcut: .snapBottomLeftDefault) }
    static func loadSnapBottomRight() -> KeyboardShortcut? { loadShortcut(forKey: snapBottomRightKey, defaultShortcut: .snapBottomRightDefault) }
    static func loadIncreaseWidth() -> KeyboardShortcut? { loadShortcut(forKey: increaseWidthKey, defaultShortcut: .increaseWidthDefault) }
    static func loadDecreaseWidth() -> KeyboardShortcut? { loadShortcut(forKey: decreaseWidthKey, defaultShortcut: .decreaseWidthDefault) }
    static func loadIncreaseHeight() -> KeyboardShortcut? { loadShortcut(forKey: increaseHeightKey, defaultShortcut: .increaseHeightDefault) }
    static func loadDecreaseHeight() -> KeyboardShortcut? { loadShortcut(forKey: decreaseHeightKey, defaultShortcut: .decreaseHeightDefault) }
    static var snapPadding: Double { UserDefaults.standard.object(forKey: snapPaddingKey) as? Double ?? 12 }
    static var resizeStep: Double { UserDefaults.standard.object(forKey: resizeStepKey) as? Double ?? 10 }
    static var restoreFullHomeAfterDisplayMoveEnabled: Bool {
        UserDefaults.standard.object(forKey: restoreFullHomeAfterDisplayMoveKey) as? Bool ?? true
    }
    static var automaticSaveAfterMouseMoveEnabled: Bool { UserDefaults.standard.bool(forKey: automaticSaveAfterMouseMoveEnabledKey) }
    static var mouseSnapEnabled: Bool { UserDefaults.standard.bool(forKey: mouseSnapEnabledKey) }
    static var mouseSnapMode: MouseSnapMode {
        if let rawValue = UserDefaults.standard.string(forKey: mouseSnapModeKey),
           let mode = MouseSnapMode(rawValue: rawValue) {
            return mode
        }
        return mouseSnapEnabled ? .edgeAndOption : .off
    }
    static var showMouseSnapAreas: Bool {
        UserDefaults.standard.object(forKey: showMouseSnapAreasKey) as? Bool ?? true
    }

    static func save(_ shortcut: KeyboardShortcut?, forSaveHome: Bool) {
        let key = forSaveHome ? saveHomeKey : restoreHomeKey
        saveShortcut(shortcut, forKey: key)
    }

    static func saveRestoreAll(_ shortcut: KeyboardShortcut?) {
        saveShortcut(shortcut, forKey: restoreAllKey)
    }

    static func saveUndoHome(_ shortcut: KeyboardShortcut?) {
        saveShortcut(shortcut, forKey: undoHomeKey)
    }

    static func saveRedoHome(_ shortcut: KeyboardShortcut?) {
        saveShortcut(shortcut, forKey: redoHomeKey)
    }

    static func saveCenterAndSaveHome(_ shortcut: KeyboardShortcut?) {
        saveShortcut(shortcut, forKey: centerAndSaveHomeKey)
    }

    static func saveMoveToNextDisplay(_ shortcut: KeyboardShortcut?) {
        saveShortcut(shortcut, forKey: moveToNextDisplayKey)
    }

    static func saveMoveToPreviousDisplay(_ shortcut: KeyboardShortcut?) {
        saveShortcut(shortcut, forKey: moveToPreviousDisplayKey)
    }

    static func saveSnapShortcut(_ shortcut: KeyboardShortcut?, direction: SnapDirection) {
        let key: String
        switch direction {
        case .left: key = snapLeftKey
        case .right: key = snapRightKey
        case .top: key = snapTopKey
        case .bottom: key = snapBottomKey
        case .fullScreen: key = snapFullScreenKey
        case .topLeft: key = snapTopLeftKey
        case .topRight: key = snapTopRightKey
        case .bottomLeft: key = snapBottomLeftKey
        case .bottomRight: key = snapBottomRightKey
        }
        saveShortcut(shortcut, forKey: key)
    }

    static func saveResizeShortcut(_ shortcut: KeyboardShortcut?, action: WindowResizeAction) {
        let key: String
        switch action {
        case .increaseWidth: key = increaseWidthKey
        case .decreaseWidth: key = decreaseWidthKey
        case .increaseHeight: key = increaseHeightKey
        case .decreaseHeight: key = decreaseHeightKey
        }
        saveShortcut(shortcut, forKey: key)
    }

    static func saveSnapPadding(_ padding: Double) {
        UserDefaults.standard.set(padding, forKey: snapPaddingKey)
    }

    static func saveResizeStep(_ step: Double) {
        UserDefaults.standard.set(step, forKey: resizeStepKey)
    }

    static func saveRestoreFullHomeAfterDisplayMoveEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: restoreFullHomeAfterDisplayMoveKey)
    }

    static func saveAutomaticSaveAfterMouseMoveEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: automaticSaveAfterMouseMoveEnabledKey)
    }

    static func saveMouseSnapEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: mouseSnapEnabledKey)
    }

    static func saveMouseSnapMode(_ mode: MouseSnapMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: mouseSnapModeKey)
        UserDefaults.standard.set(mode != .off, forKey: mouseSnapEnabledKey)
    }

    static func saveShowMouseSnapAreas(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: showMouseSnapAreasKey)
    }

    private static func load(forKey key: String) -> KeyboardShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
    }

    private static func loadShortcut(forKey key: String, defaultShortcut: KeyboardShortcut) -> KeyboardShortcut? {
        if UserDefaults.standard.bool(forKey: clearedKey(for: key)) {
            return nil
        }
        return load(forKey: key) ?? defaultShortcut
    }

    private static func saveShortcut(_ shortcut: KeyboardShortcut?, forKey key: String) {
        let cleared = clearedKey(for: key)
        if let shortcut {
            UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: key)
            UserDefaults.standard.set(false, forKey: cleared)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.set(true, forKey: cleared)
        }
    }
}
