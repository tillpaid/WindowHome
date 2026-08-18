import AppKit
import CoreGraphics
import Foundation

struct MouseDragEvent {
    let mouseLocation: CGPoint
    let optionPressed: Bool
}

/// Observes only mouse button/drag boundaries; it never records pointer coordinates or keyboard input.
final class MouseWindowTrackingService {
    enum Error: LocalizedError {
        case inputMonitoringPermissionRequired
        case eventTapUnavailable

        var errorDescription: String? {
            switch self {
            case .inputMonitoringPermissionRequired:
                "Automatic Home saving needs Input Monitoring permission to observe mouse drag boundaries."
            case .eventTapUnavailable:
                "macOS could not start the listen-only mouse monitor."
            }
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onMouseDown: (() -> Void)?
    private var onMouseDragged: ((MouseDragEvent) -> Void)?
    private var onMouseUp: (() -> Void)?

    deinit { stop() }

    func start(onMouseDown: @escaping () -> Void, onMouseDragged: @escaping (MouseDragEvent) -> Void, onMouseUp: @escaping () -> Void) throws {
        stop()
        guard InputMonitoringPermissionService.isGranted else { throw Error.inputMonitoringPermissionRequired }
        self.onMouseDown = onMouseDown
        self.onMouseDragged = onMouseDragged
        self.onMouseUp = onMouseUp

        let eventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: Self.handleEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw Error.eventTapUnavailable
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        runLoopSource = nil
        onMouseDown = nil
        onMouseDragged = nil
        onMouseUp = nil
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let service = Unmanaged<MouseWindowTrackingService>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = service.eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .leftMouseDown: DispatchQueue.main.async { service.onMouseDown?() }
        case .leftMouseDragged:
            let dragEvent = MouseDragEvent(mouseLocation: NSEvent.mouseLocation, optionPressed: event.flags.contains(.maskAlternate))
            DispatchQueue.main.async { service.onMouseDragged?(dragEvent) }
        case .leftMouseUp: DispatchQueue.main.async { service.onMouseUp?() }
        default: break
        }
        return Unmanaged.passUnretained(event)
    }
}
