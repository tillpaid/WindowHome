import Carbon.HIToolbox
import Foundation

enum HotkeyServiceError: LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        "WindowHome could not register this shortcut (system error \(status)). It may already be used by another app."
    }

    private var status: OSStatus {
        if case let .registrationFailed(status) = self { return status }
        return noErr
    }
}

final class HotkeyService {
    static let resizeRepeatInitialDelay: TimeInterval = 0.35
    static let resizeRepeatInterval: TimeInterval = 0.12

    private static let signature: OSType = 0x57484F4D // WHOM
    private static let saveHomeID: UInt32 = 1
    private static let restoreHomeID: UInt32 = 2
    private static let undoHomeID: UInt32 = 16
    private static let redoHomeID: UInt32 = 17
    private static let increaseWidthID: UInt32 = 18
    private static let decreaseWidthID: UInt32 = 19
    private static let increaseHeightID: UInt32 = 20
    private static let decreaseHeightID: UInt32 = 21
    private static let restoreAllID: UInt32 = 3
    private static let centerAndSaveHomeID: UInt32 = 15
    private static let moveToNextDisplayID: UInt32 = 4
    private static let moveToPreviousDisplayID: UInt32 = 5
    private static let snapLeftID: UInt32 = 6
    private static let snapRightID: UInt32 = 7
    private static let snapTopID: UInt32 = 8
    private static let snapBottomID: UInt32 = 9
    private static let snapFullScreenID: UInt32 = 10
    private static let snapTopLeftID: UInt32 = 11
    private static let snapTopRightID: UInt32 = 12
    private static let snapBottomLeftID: UInt32 = 13
    private static let snapBottomRightID: UInt32 = 14

    private var eventHandler: EventHandlerRef?
    private var registeredHotkeys: [EventHotKeyRef] = []
    private var saveHomeAction: (() -> Void)?
    private var restoreHomeAction: (() -> Void)?
    private var undoHomeAction: (() -> Void)?
    private var redoHomeAction: (() -> Void)?
    private var restoreAllAction: (() -> Void)?
    private var centerAndSaveHomeAction: (() -> Void)?
    private var moveToNextDisplayAction: (() -> Void)?
    private var moveToPreviousDisplayAction: (() -> Void)?
    private var snapActions: [UInt32: () -> Void] = [:]
    private var resizeActions: [UInt32: () -> Void] = [:]
    private var activeResizeHotkeyID: UInt32?
    private var resizeRepeatRequestID: UUID?

    init() throws {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = eventTypes.withUnsafeMutableBufferPointer { eventTypes in
            InstallEventHandler(
                GetEventDispatcherTarget(),
                Self.handleEvent,
                eventTypes.count,
                eventTypes.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
        }
        guard status == noErr else { throw HotkeyServiceError.registrationFailed(status) }
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(saveHome: KeyboardShortcut?, restoreHome: KeyboardShortcut?, undoHome: KeyboardShortcut?, redoHome: KeyboardShortcut?, restoreAll: KeyboardShortcut?, centerAndSaveHome: KeyboardShortcut?, moveToNextDisplay: KeyboardShortcut?, moveToPreviousDisplay: KeyboardShortcut?, snapLeft: KeyboardShortcut?, snapRight: KeyboardShortcut?, snapTop: KeyboardShortcut?, snapBottom: KeyboardShortcut?, snapFullScreen: KeyboardShortcut?, snapTopLeft: KeyboardShortcut?, snapTopRight: KeyboardShortcut?, snapBottomLeft: KeyboardShortcut?, snapBottomRight: KeyboardShortcut?, increaseWidth: KeyboardShortcut?, decreaseWidth: KeyboardShortcut?, increaseHeight: KeyboardShortcut?, decreaseHeight: KeyboardShortcut?, onSaveHome: @escaping () -> Void, onRestoreHome: @escaping () -> Void, onUndoHome: @escaping () -> Void, onRedoHome: @escaping () -> Void, onRestoreAll: @escaping () -> Void, onCenterAndSaveHome: @escaping () -> Void, onMoveToNextDisplay: @escaping () -> Void, onMoveToPreviousDisplay: @escaping () -> Void, onSnapLeft: @escaping () -> Void, onSnapRight: @escaping () -> Void, onSnapTop: @escaping () -> Void, onSnapBottom: @escaping () -> Void, onSnapFullScreen: @escaping () -> Void, onSnapTopLeft: @escaping () -> Void, onSnapTopRight: @escaping () -> Void, onSnapBottomLeft: @escaping () -> Void, onSnapBottomRight: @escaping () -> Void, onIncreaseWidth: @escaping () -> Void, onDecreaseWidth: @escaping () -> Void, onIncreaseHeight: @escaping () -> Void, onDecreaseHeight: @escaping () -> Void) throws {
        unregisterAll()
        saveHomeAction = onSaveHome
        restoreHomeAction = onRestoreHome
        undoHomeAction = onUndoHome
        redoHomeAction = onRedoHome
        restoreAllAction = onRestoreAll
        centerAndSaveHomeAction = onCenterAndSaveHome
        moveToNextDisplayAction = onMoveToNextDisplay
        moveToPreviousDisplayAction = onMoveToPreviousDisplay
        snapActions = [Self.snapLeftID: onSnapLeft, Self.snapRightID: onSnapRight, Self.snapTopID: onSnapTop, Self.snapBottomID: onSnapBottom, Self.snapFullScreenID: onSnapFullScreen, Self.snapTopLeftID: onSnapTopLeft, Self.snapTopRightID: onSnapTopRight, Self.snapBottomLeftID: onSnapBottomLeft, Self.snapBottomRightID: onSnapBottomRight]
        resizeActions = [
            Self.increaseWidthID: onIncreaseWidth,
            Self.decreaseWidthID: onDecreaseWidth,
            Self.increaseHeightID: onIncreaseHeight,
            Self.decreaseHeightID: onDecreaseHeight
        ]
        do {
            try register(saveHome, id: Self.saveHomeID)
            try register(restoreHome, id: Self.restoreHomeID)
            try register(undoHome, id: Self.undoHomeID)
            try register(redoHome, id: Self.redoHomeID)
            try register(restoreAll, id: Self.restoreAllID)
            try register(centerAndSaveHome, id: Self.centerAndSaveHomeID)
            try register(moveToNextDisplay, id: Self.moveToNextDisplayID)
            try register(moveToPreviousDisplay, id: Self.moveToPreviousDisplayID)
            try register(snapLeft, id: Self.snapLeftID)
            try register(snapRight, id: Self.snapRightID)
            try register(snapTop, id: Self.snapTopID)
            try register(snapBottom, id: Self.snapBottomID)
            try register(snapFullScreen, id: Self.snapFullScreenID)
            try register(snapTopLeft, id: Self.snapTopLeftID)
            try register(snapTopRight, id: Self.snapTopRightID)
            try register(snapBottomLeft, id: Self.snapBottomLeftID)
            try register(snapBottomRight, id: Self.snapBottomRightID)
            try register(increaseWidth, id: Self.increaseWidthID)
            try register(decreaseWidth, id: Self.decreaseWidthID)
            try register(increaseHeight, id: Self.increaseHeightID)
            try register(decreaseHeight, id: Self.decreaseHeightID)
        } catch {
            unregisterAll()
            throw error
        }
    }

    private func register(_ shortcut: KeyboardShortcut?, id: UInt32) throws {
        guard let shortcut else { return }
        var hotkey: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkey)
        guard status == noErr, let hotkey else { throw HotkeyServiceError.registrationFailed(status) }
        registeredHotkeys.append(hotkey)
    }

    private func unregisterAll() {
        stopResizeRepeat()
        registeredHotkeys.forEach { UnregisterEventHotKey($0) }
        registeredHotkeys.removeAll()
    }

    private static let handleEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
        return service.handle(event)
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
        guard status == noErr else { return status }

        let eventKind = GetEventKind(event)
        if eventKind == UInt32(kEventHotKeyReleased) {
            guard resizeActions[hotkeyID.id] != nil else { return noErr }
            stopResizeRepeat(for: hotkeyID.id)
            return noErr
        }
        guard eventKind == UInt32(kEventHotKeyPressed) else { return OSStatus(eventNotHandledErr) }

        switch hotkeyID.id {
        case Self.saveHomeID: saveHomeAction?()
        case Self.restoreHomeID: restoreHomeAction?()
        case Self.undoHomeID: undoHomeAction?()
        case Self.redoHomeID: redoHomeAction?()
        case Self.restoreAllID: restoreAllAction?()
        case Self.centerAndSaveHomeID: centerAndSaveHomeAction?()
        case Self.moveToNextDisplayID: moveToNextDisplayAction?()
        case Self.moveToPreviousDisplayID: moveToPreviousDisplayAction?()
        case Self.snapLeftID, Self.snapRightID, Self.snapTopID, Self.snapBottomID, Self.snapFullScreenID, Self.snapTopLeftID, Self.snapTopRightID, Self.snapBottomLeftID, Self.snapBottomRightID: snapActions[hotkeyID.id]?()
        case Self.increaseWidthID, Self.decreaseWidthID, Self.increaseHeightID, Self.decreaseHeightID:
            guard activeResizeHotkeyID != hotkeyID.id else { return noErr }
            resizeActions[hotkeyID.id]?()
            beginResizeRepeat(for: hotkeyID.id)
        default: return OSStatus(eventNotHandledErr)
        }
        return noErr
    }

    private func beginResizeRepeat(for hotkeyID: UInt32) {
        stopResizeRepeat()
        activeResizeHotkeyID = hotkeyID
        let requestID = UUID()
        resizeRepeatRequestID = requestID
        scheduleResizeRepeat(for: hotkeyID, requestID: requestID, after: Self.resizeRepeatInitialDelay)
    }

    private func scheduleResizeRepeat(for hotkeyID: UInt32, requestID: UUID, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.activeResizeHotkeyID == hotkeyID,
                  self.resizeRepeatRequestID == requestID else { return }

            self.resizeActions[hotkeyID]?()
            self.scheduleResizeRepeat(
                for: hotkeyID,
                requestID: requestID,
                after: Self.resizeRepeatInterval
            )
        }
    }

    private func stopResizeRepeat(for hotkeyID: UInt32? = nil) {
        if let hotkeyID, activeResizeHotkeyID != hotkeyID { return }
        activeResizeHotkeyID = nil
        resizeRepeatRequestID = nil
    }
}
