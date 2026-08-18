import AppKit
import ApplicationServices
import CoreGraphics

enum FocusedWindowError: LocalizedError {
    case accessibilityPermissionRequired
    case focusedApplicationUnavailable
    case focusedWindowUnavailable
    case unsupportedWindow
    case positionNotSettable
    case sizeNotSettable
    case cannotReadGeometry(AXError)
    case cannotModifyGeometry(AXError)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "WindowHome needs Accessibility permission. Enable it in System Settings, then return here."
        case .focusedApplicationUnavailable:
            "macOS did not provide a focused application. Focus a regular app window and try again."
        case .focusedWindowUnavailable:
            "The focused application has no controllable focused window."
        case .unsupportedWindow:
            "This window does not expose a readable position and size. Full-screen, minimized, sheet, and system windows may be unsupported."
        case .positionNotSettable:
            "This app exposes the window, but macOS reports that its position cannot be changed. Exit full-screen or maximize mode and try again."
        case .sizeNotSettable:
            "This app exposes the window, but macOS reports that its size cannot be changed. Exit full-screen or maximize mode and try again."
        case .cannotReadGeometry(let error):
            "WindowHome could not read this window's geometry (Accessibility error \(error.rawValue))."
        case .cannotModifyGeometry(let error):
            "This window refused the test geometry change (Accessibility error \(error.rawValue))."
        }
    }
}

struct FocusedWindowSnapshot {
    let window: AXUIElement
    let windowIdentifier: CFHashCode
    let processIdentifier: pid_t
    let applicationName: String
    let bundleIdentifier: String?
    let geometry: WindowGeometry
}

final class FocusedWindowService {
    func mainWindowSnapshot(for application: NSRunningApplication) -> FocusedWindowSnapshot? {
        guard AccessibilityPermissionService.isTrusted,
              let bundleIdentifier = application.bundleIdentifier else {
            return nil
        }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let window = focusedOrMainWindow(for: applicationElement),
              let geometry = try? readGeometry(of: window, fallbackProcessIdentifier: application.processIdentifier) else {
            return nil
        }
        return FocusedWindowSnapshot(
            window: window,
            windowIdentifier: CFHash(window),
            processIdentifier: application.processIdentifier,
            applicationName: application.localizedName ?? bundleIdentifier,
            bundleIdentifier: bundleIdentifier,
            geometry: geometry
        )
    }

    func focusedWindow() throws -> FocusedWindowSnapshot {
        guard AccessibilityPermissionService.isTrusted else {
            throw FocusedWindowError.accessibilityPermissionRequired
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        guard let application = focusedApplication(from: systemWideElement) else {
            throw FocusedWindowError.focusedApplicationUnavailable
        }
        guard let window = focusedOrMainWindow(for: application) else {
            throw FocusedWindowError.focusedWindowUnavailable
        }

        let pid = processIdentifier(for: application)
        let runningApplication = NSRunningApplication(processIdentifier: pid)
        let geometry = try readGeometry(of: window, fallbackProcessIdentifier: pid)

        return FocusedWindowSnapshot(window: window, windowIdentifier: CFHash(window), processIdentifier: pid, applicationName: runningApplication?.localizedName ?? "Unknown app", bundleIdentifier: runningApplication?.bundleIdentifier, geometry: geometry)
    }

    func readGeometry(of window: AXUIElement, fallbackProcessIdentifier: pid_t? = nil) throws -> WindowGeometry {
        do {
            return try accessibilityGeometry(of: window)
        } catch FocusedWindowError.cannotReadGeometry, FocusedWindowError.unsupportedWindow {
            guard let pid = fallbackProcessIdentifier, let geometry = windowServerGeometry(for: pid) else {
                throw FocusedWindowError.unsupportedWindow
            }
            return geometry
        }
    }

    private func accessibilityGeometry(of window: AXUIElement) throws -> WindowGeometry {
        guard let positionReference = try attributeValue(kAXPositionAttribute, from: window),
              let sizeReference = try attributeValue(kAXSizeAttribute, from: window),
              CFGetTypeID(positionReference) == AXValueGetTypeID(),
              CFGetTypeID(sizeReference) == AXValueGetTypeID() else {
            throw FocusedWindowError.unsupportedWindow
        }
        let positionValue = unsafeBitCast(positionReference, to: AXValue.self)
        let sizeValue = unsafeBitCast(sizeReference, to: AXValue.self)

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) else {
            throw FocusedWindowError.unsupportedWindow
        }
        return WindowGeometry(origin: position, size: size)
    }

    func setGeometry(_ geometry: WindowGeometry, for window: AXUIElement) throws {
        var canSetPosition = DarwinBoolean(false)
        let positionSettableResult = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &canSetPosition)
        guard positionSettableResult == .success, canSetPosition.boolValue else {
            throw FocusedWindowError.positionNotSettable
        }
        var canSetSize = DarwinBoolean(false)
        let sizeSettableResult = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &canSetSize)
        guard sizeSettableResult == .success, canSetSize.boolValue else {
            throw FocusedWindowError.sizeNotSettable
        }
        try setGeometryValues(geometry, for: window)
    }

    func setGeometryForDisplayMove(
        _ geometry: WindowGeometry,
        writeOrder: DisplayMoveGeometryWriteOrder,
        for window: AXUIElement
    ) throws {
        switch writeOrder {
        case .resizeBeforeMove:
            // Shrink while still on the larger source display so the old large frame never flashes
            // on the smaller destination display.
            try setSize(geometry.size, for: window)
            try setPosition(geometry.origin, for: window)
        case .moveBeforeResize:
            // A size larger than the source display can be clamped by macOS. Move first so the
            // resize is evaluated against the destination, then correct any origin shift.
            try setPosition(geometry.origin, for: window)
            try setSize(geometry.size, for: window)
            try setPosition(geometry.origin, for: window)
        }
    }

    func setPosition(_ position: CGPoint, for window: AXUIElement) throws {
        var canSetPosition = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &canSetPosition)
        guard result == .success, canSetPosition.boolValue else {
            throw FocusedWindowError.positionNotSettable
        }
        var position = position
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            throw FocusedWindowError.unsupportedWindow
        }
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        guard positionResult == .success else { throw FocusedWindowError.cannotModifyGeometry(positionResult) }
    }

    func setSize(_ size: CGSize, for window: AXUIElement) throws {
        var canSetSize = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &canSetSize)
        guard result == .success, canSetSize.boolValue else {
            throw FocusedWindowError.sizeNotSettable
        }
        var size = size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw FocusedWindowError.unsupportedWindow
        }
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard sizeResult == .success else { throw FocusedWindowError.cannotModifyGeometry(sizeResult) }
    }

    func resizeAroundCenter(
        _ targetGeometry: WindowGeometry,
        from sourceGeometry: WindowGeometry,
        for window: AXUIElement,
        processIdentifier: pid_t
    ) throws -> WindowGeometry {
        try setSize(targetGeometry.size, for: window)
        let appliedGeometry = try readGeometry(of: window, fallbackProcessIdentifier: processIdentifier)
        let centeredGeometry = SymmetricWindowResize.geometryWithPreservedCenter(
            source: sourceGeometry,
            size: appliedGeometry.size
        )
        try setPosition(centeredGeometry.origin, for: window)
        return centeredGeometry
    }

    private func setGeometryValues(_ geometry: WindowGeometry, for window: AXUIElement) throws {
        var position = geometry.origin
        var size = geometry.size
        guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw FocusedWindowError.unsupportedWindow
        }

        // Accessibility exposes position and size as separate values. Set the final size first so
        // the subsequent move does not visibly land on the target display at the old size.
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard sizeResult == .success else { throw FocusedWindowError.cannotModifyGeometry(sizeResult) }

        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        guard positionResult == .success else { throw FocusedWindowError.cannotModifyGeometry(positionResult) }
    }

    func isFullScreen(_ window: AXUIElement) -> Bool {
        guard let value = try? attributeValue("AXFullScreen", from: window),
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return false
        }
        let boolean = unsafeBitCast(value, to: CFBoolean.self)
        return CFBooleanGetValue(boolean)
    }

    private func attributeValue(_ attribute: String, from element: AXUIElement) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { throw FocusedWindowError.cannotReadGeometry(result) }
        return value
    }

    /// AXFocusedApplication may report kAXErrorNoValue for some Chromium and Electron apps.
    /// NSWorkspace gives the same foreground process without relying on that AX attribute.
    private func focusedApplication(from systemWideElement: AXUIElement) -> AXUIElement? {
        if let applicationValue = try? attributeValue(kAXFocusedApplicationAttribute, from: systemWideElement),
           CFGetTypeID(applicationValue) == AXUIElementGetTypeID() {
            return unsafeBitCast(applicationValue, to: AXUIElement.self)
        }

        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return nil }
        return AXUIElementCreateApplication(frontmostApplication.processIdentifier)
    }

    /// Electron and Chromium windows occasionally omit AXFocusedWindow while still exposing AXMainWindow.
    private func focusedOrMainWindow(for application: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            guard let value = try? attributeValue(attribute, from: application),
                  CFGetTypeID(value) == AXUIElementGetTypeID() else {
                continue
            }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
        return nil
    }

    private func processIdentifier(for application: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(application, &pid)
        return pid
    }

    /// Some Chromium/Electron windows expose AXWindow but return kAXErrorNoValue for AXPosition/AXSize.
    /// The Window Server still provides their frontmost on-screen frame in the same global coordinate system.
    private func windowServerGeometry(for processIdentifier: pid_t) -> WindowGeometry? {
        guard let windowInfoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowInfoList {
            let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue
            guard ownerPID == processIdentifier, layer == 0,
                  let bounds = windowInfo[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds, &rect), !rect.isEmpty else { continue }
            return WindowGeometry(origin: rect.origin, size: rect.size)
        }
        return nil
    }
}
