import AppKit
import CoreGraphics

struct DisplayContext {
    let fingerprint: DisplayFingerprint
    let name: String
    let visibleFrame: CGRect
}

enum SnapDirection: CaseIterable, Hashable {
    case left, right, top, bottom, fullScreen, topLeft, topRight, bottomLeft, bottomRight
}

struct MouseSnapActivationZone: Equatable {
    let direction: SnapDirection
    let frame: CGRect
}

enum SnapLayout {
    static let fractions: [CGFloat] = [0.5, 2.0 / 3.0, 1.0 / 3.0]

    static func appKitRect(direction: SnapDirection, fraction: CGFloat, padding: CGFloat, visibleFrame: CGRect) -> CGRect {
        let maximumPadding = max(0, min(visibleFrame.width, visibleFrame.height) / 2 - 1)
        let effectivePadding = min(max(0, padding), maximumPadding)
        let frame = visibleFrame.insetBy(dx: effectivePadding, dy: effectivePadding)
        // Reserve the same gap inside a paired layout, so left/right, top/bottom, and
        // diagonally opposed corners do not touch when their fractions add up to 100%.
        let horizontalSpan = max(0, frame.width - effectivePadding)
        let verticalSpan = max(0, frame.height - effectivePadding)
        let quarterHeight = verticalSpan / 2
        let rect: CGRect
        switch direction {
        case .fullScreen:
            rect = frame
        case .left:
            rect = CGRect(x: frame.minX, y: frame.minY, width: horizontalSpan * fraction, height: frame.height)
        case .right:
            let width = horizontalSpan * fraction
            rect = CGRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height)
        case .top:
            let height = verticalSpan * fraction
            rect = CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        case .bottom:
            rect = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: verticalSpan * fraction)
        case .topLeft:
            let size = CGSize(width: horizontalSpan * fraction, height: quarterHeight)
            rect = CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        case .topRight:
            let size = CGSize(width: horizontalSpan * fraction, height: quarterHeight)
            rect = CGRect(x: frame.maxX - size.width, y: frame.maxY - size.height, width: size.width, height: size.height)
        case .bottomLeft:
            rect = CGRect(x: frame.minX, y: frame.minY, width: horizontalSpan * fraction, height: quarterHeight)
        case .bottomRight:
            let size = CGSize(width: horizontalSpan * fraction, height: quarterHeight)
            rect = CGRect(x: frame.maxX - size.width, y: frame.minY, width: size.width, height: size.height)
        }
        return rect
    }

    static func accessibilityGeometry(direction: SnapDirection, fraction: CGFloat, padding: CGFloat, visibleFrame: CGRect, converter: CoordinateConverter) -> WindowGeometry {
        converter.accessibilityGeometry(fromAppKit: appKitRect(direction: direction, fraction: fraction, padding: padding, visibleFrame: visibleFrame))
    }

    /// Places an app-limited window in the middle of the usable display area. This is used
    /// when an app accepts a full-screen Snap request but silently caps its own size.
    static func centeredAppKitRect(size: CGSize, padding: CGFloat, visibleFrame: CGRect) -> CGRect {
        let maximumPadding = max(0, min(visibleFrame.width, visibleFrame.height) / 2 - 1)
        let effectivePadding = min(max(0, padding), maximumPadding)
        let safeFrame = visibleFrame.insetBy(dx: effectivePadding, dy: effectivePadding)
        let constrainedSize = CGSize(
            width: min(max(1, size.width), safeFrame.width),
            height: min(max(1, size.height), safeFrame.height)
        )
        return CGRect(
            x: safeFrame.midX - constrainedSize.width / 2,
            y: safeFrame.midY - constrainedSize.height / 2,
            width: constrainedSize.width,
            height: constrainedSize.height
        )
    }
}

struct CoordinateConverter {
    let desktopFrame: CGRect
    let accessibilityReferenceY: CGFloat

    init(screens: [NSScreen] = NSScreen.screens) {
        desktopFrame = screens.map(\.frame).reduce(.null) { $0.union($1) }
        let mainDisplayID = CGMainDisplayID()
        let mainScreen = screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == mainDisplayID
        }
        // Accessibility/Window Server coordinates use the upper-left corner of the main
        // display as their vertical reference. The union of all screens is not equivalent:
        // a secondary display placed above the main display extends desktopFrame.maxY and
        // would shift every converted window by the full height of that upper display.
        accessibilityReferenceY = (mainScreen ?? screens.first)?.frame.maxY ?? 0
    }

    init(desktopFrame: CGRect, accessibilityReferenceY: CGFloat? = nil) {
        self.desktopFrame = desktopFrame
        self.accessibilityReferenceY = accessibilityReferenceY ?? desktopFrame.maxY
    }

    func appKitRect(fromAccessibility geometry: WindowGeometry) -> CGRect {
        CGRect(x: geometry.origin.x, y: accessibilityReferenceY - geometry.origin.y - geometry.size.height, width: geometry.size.width, height: geometry.size.height)
    }

    func accessibilityGeometry(fromAppKit rect: CGRect) -> WindowGeometry {
        WindowGeometry(origin: CGPoint(x: rect.minX, y: accessibilityReferenceY - rect.maxY), size: rect.size)
    }
}

struct WindowTransferPlan {
    let geometry: WindowGeometry
    let requiresResize: Bool
}

enum DisplayMoveGeometryWriteOrder: Equatable {
    case resizeBeforeMove
    case moveBeforeResize
}

enum DisplayMoveHomeStabilizationDecision: Equatable {
    case stop
    case verifyLater
    case reapplyAndVerifyLater
}

enum DisplayMoveHomePolicy {
    static let stabilizationDelays: [TimeInterval] = [0.06, 0.10, 0.16, 0.24, 0.36, 0.52]

    static func shouldApplyFullHome(
        automationEnabled: Bool,
        sourceIsFullScreen: Bool,
        sourceIsWindowHomeSnapped: Bool,
        sourceIsSystemTiled: Bool
    ) -> Bool {
        automationEnabled || sourceIsFullScreen || sourceIsWindowHomeSnapped || sourceIsSystemTiled
    }

    static func geometryWriteOrder(
        targetSize: CGSize,
        sourceVisibleFrame: CGRect,
        padding: CGFloat
    ) -> DisplayMoveGeometryWriteOrder {
        let availableWidth = max(0, sourceVisibleFrame.width - padding * 2)
        let availableHeight = max(0, sourceVisibleFrame.height - padding * 2)
        return targetSize.width <= availableWidth && targetSize.height <= availableHeight
            ? .resizeBeforeMove
            : .moveBeforeResize
    }

    static func stabilizationDecision(
        actual: WindowGeometry,
        target: WindowGeometry,
        isOnTargetDisplay: Bool,
        tolerance: CGFloat = 4
    ) -> DisplayMoveHomeStabilizationDecision {
        guard isOnTargetDisplay else { return .stop }
        let matchesTarget = abs(actual.origin.x - target.origin.x) <= tolerance
            && abs(actual.origin.y - target.origin.y) <= tolerance
            && abs(actual.size.width - target.size.width) <= tolerance
            && abs(actual.size.height - target.size.height) <= tolerance
        return matchesTarget ? .verifyLater : .reapplyAndVerifyLater
    }
}

enum DisplayServiceError: LocalizedError {
    case noDisplayForWindow

    var errorDescription: String? { "WindowHome could not determine the display containing the focused window." }
}

final class DisplayService {
    enum MoveDirection {
        case next
        case previous
    }

    func context(forAccessibilityGeometry geometry: WindowGeometry) throws -> DisplayContext {
        let screens = NSScreen.screens
        let converter = CoordinateConverter(screens: screens)
        let windowRect = converter.appKitRect(fromAccessibility: geometry)
        guard let index = Self.displayIndex(for: windowRect, in: screens.map(\.frame)) else {
            throw DisplayServiceError.noDisplayForWindow
        }
        let screen = screens[index]

        guard let context = context(for: screen) else {
            throw DisplayServiceError.noDisplayForWindow
        }
        return context
    }

    func coordinateConverter() -> CoordinateConverter { CoordinateConverter() }

    func context(atMouseLocation point: CGPoint) -> DisplayContext? {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.frame.contains(point) }) else { return nil }
        return context(for: screen)
    }

    func mouseSnapDirection(atMouseLocation point: CGPoint, optionPressed: Bool) -> (direction: SnapDirection, display: DisplayContext)? {
        guard let display = context(atMouseLocation: point) else { return nil }
        return Self.mouseSnapDirection(at: point, in: display.visibleFrame, optionPressed: optionPressed)
            .map { ($0, display) }
    }

    func mouseSnapActivationZones(atMouseLocation point: CGPoint, optionPressed: Bool) -> (zones: [MouseSnapActivationZone], display: DisplayContext)? {
        guard let display = context(atMouseLocation: point) else { return nil }
        return (Self.mouseSnapActivationZones(in: display.visibleFrame, optionPressed: optionPressed), display)
    }

    static func mouseSnapActivationZones(in frame: CGRect, optionPressed: Bool) -> [MouseSnapActivationZone] {
        guard frame.width > 0, frame.height > 0 else { return [] }

        let centeredWidth = frame.width / 3
        let centeredHeight = frame.height / 3
        let sideThickness = optionPressed ? frame.width * 0.15 : min(24, frame.width)
        let topThickness = optionPressed ? frame.height * 0.05 : min(24, frame.height)

        return [
            MouseSnapActivationZone(
                direction: .left,
                frame: CGRect(x: frame.minX, y: frame.midY - centeredHeight / 2, width: sideThickness, height: centeredHeight)
            ),
            MouseSnapActivationZone(
                direction: .right,
                frame: CGRect(x: frame.maxX - sideThickness, y: frame.midY - centeredHeight / 2, width: sideThickness, height: centeredHeight)
            ),
            MouseSnapActivationZone(
                direction: .fullScreen,
                frame: CGRect(x: frame.midX - centeredWidth / 2, y: frame.maxY - topThickness, width: centeredWidth, height: topThickness)
            )
        ]
    }

    static func mouseSnapDirection(at point: CGPoint, in frame: CGRect, optionPressed: Bool) -> SnapDirection? {
        mouseSnapActivationZones(in: frame, optionPressed: optionPressed)
            .first(where: { contains(point, in: $0.frame) })?
            .direction
    }

    private static func contains(_ point: CGPoint, in frame: CGRect) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }

    /// NSScreen.screens is the order macOS uses for display traversal. Wrapping the index makes
    /// Next/Previous useful with any number of displays, including a two-display setup.
    func adjacentDisplay(to display: DisplayContext, direction: MoveDirection) -> DisplayContext? {
        let contexts = NSScreen.screens.compactMap(context(for:))
        guard contexts.count > 1,
              let currentIndex = contexts.firstIndex(where: { $0.fingerprint == display.fingerprint }) else {
            return nil
        }
        switch direction {
        case .next:
            return contexts[(currentIndex + 1) % contexts.count]
        case .previous:
            return contexts[(currentIndex - 1 + contexts.count) % contexts.count]
        }
    }

    /// Keeps the current size where possible, centers it on the new display, and then clamps
    /// the result so it always fits within the visible frame and the configured padding.
    func defaultAccessibilityGeometry(from source: WindowGeometry, on display: DisplayContext, padding: CGFloat) -> WindowGeometry {
        let rect = SnapLayout.centeredAppKitRect(
            size: source.size,
            padding: padding,
            visibleFrame: display.visibleFrame
        )
        return coordinateConverter().accessibilityGeometry(fromAppKit: rect)
    }

    func centeredAccessibilityGeometry(size: CGSize, on display: DisplayContext, padding: CGFloat) -> WindowGeometry {
        coordinateConverter().accessibilityGeometry(fromAppKit: SnapLayout.centeredAppKitRect(
            size: size,
            padding: padding,
            visibleFrame: display.visibleFrame
        ))
    }

    func constrainedAccessibilityGeometry(_ geometry: WindowGeometry, on display: DisplayContext, padding: CGFloat, converter suppliedConverter: CoordinateConverter? = nil) -> WindowGeometry {
        let converter = suppliedConverter ?? coordinateConverter()
        let rect = converter.appKitRect(fromAccessibility: geometry)
        let safeFrame = paddedVisibleFrame(for: display, padding: padding)
        let size = CGSize(
            width: min(rect.width, safeFrame.width),
            height: min(rect.height, safeFrame.height)
        )
        let origin = CGPoint(
            x: min(max(rect.minX, safeFrame.minX), safeFrame.maxX - size.width),
            y: min(max(rect.minY, safeFrame.minY), safeFrame.maxY - size.height)
        )
        return converter.accessibilityGeometry(fromAppKit: CGRect(origin: origin, size: size))
    }

    /// Plans the single-display result of a move. Most moves preserve size and therefore need
    /// only AXPosition. When the source window is larger than the destination's usable area,
    /// preserving that size would leave it straddling vertically stacked displays, so the move
    /// must also apply the constrained size.
    func transferPlan(from source: WindowGeometry, toward target: WindowGeometry, on display: DisplayContext, padding: CGFloat, converter: CoordinateConverter? = nil) -> WindowTransferPlan {
        let geometry = constrainedAccessibilityGeometry(
            WindowGeometry(origin: target.origin, size: source.size),
            on: display,
            padding: padding,
            converter: converter
        )
        return WindowTransferPlan(
            geometry: geometry,
            requiresResize: geometry.size != source.size
        )
    }

    func isLikelySystemTiled(accessibilityGeometry: WindowGeometry) -> Bool {
        let screens = NSScreen.screens
        let converter = CoordinateConverter(screens: screens)
        let windowRect = converter.appKitRect(fromAccessibility: accessibilityGeometry)
        guard let index = Self.displayIndex(for: windowRect, in: screens.map(\.frame)) else {
            return false
        }
        let screen = screens[index]
        let visibleFrame = screen.visibleFrame
        return Self.standardSystemTileRects(in: visibleFrame).contains { approximatelyEqual(windowRect, $0) }
            || approximatelyEqual(windowRect, screen.frame)
    }

    static func standardSystemTileRects(in visibleFrame: CGRect) -> [CGRect] {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2
        return [
            visibleFrame,
            CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height),
            CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height),
            CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: visibleFrame.width, height: halfHeight),
            CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: halfHeight),
            CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: halfWidth, height: halfHeight),
            CGRect(x: visibleFrame.midX, y: visibleFrame.midY, width: halfWidth, height: halfHeight),
            CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: halfHeight),
            CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        ]
    }

    static func displayIndex(for windowRect: CGRect, in screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        let windowCenter = CGPoint(x: windowRect.midX, y: windowRect.midY)
        var bestIndex = 0
        var bestArea = intersectionArea(of: windowRect, with: screenFrames[0])
        var bestContainsCenter = screenFrames[0].contains(windowCenter)

        for index in screenFrames.indices.dropFirst() {
            let area = intersectionArea(of: windowRect, with: screenFrames[index])
            let containsCenter = screenFrames[index].contains(windowCenter)
            if area > bestArea || (area == bestArea && containsCenter && !bestContainsCenter) {
                bestIndex = index
                bestArea = area
                bestContainsCenter = containsCenter
            }
        }
        return bestIndex
    }

    private static func intersectionArea(of rect: CGRect, with screenFrame: CGRect) -> CGFloat {
        let intersection = rect.intersection(screenFrame)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func context(for screen: NSScreen) -> DisplayContext? {
        let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let displayNumber else { return nil }
        let displayID = CGDirectDisplayID(displayNumber.uint32Value)
        return DisplayContext(
            fingerprint: DisplayFingerprint(
                vendorNumber: CGDisplayVendorNumber(displayID),
                modelNumber: CGDisplayModelNumber(displayID),
                serialNumber: CGDisplaySerialNumber(displayID),
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                logicalWidth: Int(screen.frame.width.rounded()),
                logicalHeight: Int(screen.frame.height.rounded()),
                pixelWidth: Int(CGDisplayPixelsWide(displayID)),
                pixelHeight: Int(CGDisplayPixelsHigh(displayID))
            ),
            name: screen.localizedName,
            visibleFrame: screen.visibleFrame
        )
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 8) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    private func paddedVisibleFrame(for display: DisplayContext, padding: CGFloat) -> CGRect {
        let visibleFrame = display.visibleFrame
        let maximumPadding = max(0, min(visibleFrame.width, visibleFrame.height) / 2 - 1)
        let effectivePadding = min(max(0, padding), maximumPadding)
        let safeFrame = visibleFrame.insetBy(dx: effectivePadding, dy: effectivePadding)
        return CGRect(
            x: safeFrame.minX,
            y: safeFrame.minY,
            width: max(1, safeFrame.width),
            height: max(1, safeFrame.height)
        )
    }
}
