import CoreGraphics
import Foundation

struct DisplayFingerprint: Codable, Equatable, Hashable {
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let isBuiltIn: Bool
    /// Window geometry is expressed in AppKit points, so these dimensions distinguish
    /// different effective resolutions of the same external physical display.
    let logicalWidth: Int
    let logicalHeight: Int
    /// Keep the active pixel mode in the key as well: two display modes can expose the
    /// same AppKit canvas while still representing different user-selected resolutions.
    let pixelWidth: Int
    let pixelHeight: Int

    init(
        vendorNumber: UInt32,
        modelNumber: UInt32,
        serialNumber: UInt32,
        isBuiltIn: Bool,
        logicalWidth: Int = 0,
        logicalHeight: Int = 0,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0
    ) {
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.isBuiltIn = isBuiltIn
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// Legacy external-display profiles remain readable, but are not treated as a match
    /// for a resolution-specific Home profile.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vendorNumber = try container.decode(UInt32.self, forKey: .vendorNumber)
        modelNumber = try container.decode(UInt32.self, forKey: .modelNumber)
        serialNumber = try container.decode(UInt32.self, forKey: .serialNumber)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        logicalWidth = try container.decodeIfPresent(Int.self, forKey: .logicalWidth) ?? 0
        logicalHeight = try container.decodeIfPresent(Int.self, forKey: .logicalHeight) ?? 0
        pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth) ?? 0
        pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight) ?? 0
    }

    /// Say No to Notch changes only the usable height of the built-in screen. Share a
    /// Home for those variants, but retain separate Homes when the user changes scale,
    /// which changes the effective width. External displays remain mode-specific.
    func identifiesSameHomeDisplay(as other: DisplayFingerprint) -> Bool {
        guard isBuiltIn, other.isBuiltIn else { return self == other }
        return vendorNumber == other.vendorNumber
            && modelNumber == other.modelNumber
            && serialNumber == other.serialNumber
            && logicalWidth == other.logicalWidth
            && pixelWidth == other.pixelWidth
    }
}

struct StoredGeometry: Codable, Equatable {
    let relativeX: CGFloat
    let relativeY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let normalizedX: CGFloat
    let normalizedY: CGFloat
    let normalizedWidth: CGFloat
    let normalizedHeight: CGFloat
    let savedVisibleFrame: CodableRect

    init(accessibilityGeometry: WindowGeometry, visibleFrame: CGRect, converter: CoordinateConverter) {
        let appKitRect = converter.appKitRect(fromAccessibility: accessibilityGeometry)
        let relativeRect = appKitRect.offsetBy(dx: -visibleFrame.minX, dy: -visibleFrame.minY)
        relativeX = relativeRect.minX
        relativeY = relativeRect.minY
        width = relativeRect.width
        height = relativeRect.height
        normalizedX = relativeRect.minX / visibleFrame.width
        normalizedY = relativeRect.minY / visibleFrame.height
        normalizedWidth = relativeRect.width / visibleFrame.width
        normalizedHeight = relativeRect.height / visibleFrame.height
        savedVisibleFrame = CodableRect(visibleFrame)
    }

    func accessibilityGeometry(for visibleFrame: CGRect, converter: CoordinateConverter) -> WindowGeometry {
        let frameHasNotChanged = savedVisibleFrame.cgRect.equalTo(visibleFrame)
        let relativeRect: CGRect
        if frameHasNotChanged {
            relativeRect = CGRect(x: relativeX, y: relativeY, width: width, height: height)
        } else {
            relativeRect = CGRect(x: normalizedX * visibleFrame.width, y: normalizedY * visibleFrame.height, width: normalizedWidth * visibleFrame.width, height: normalizedHeight * visibleFrame.height)
        }
        return converter.accessibilityGeometry(fromAppKit: relativeRect.offsetBy(dx: visibleFrame.minX, dy: visibleFrame.minY))
    }
}

struct CodableRect: Codable, Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: CGRect) {
        x = rect.minX
        y = rect.minY
        width = rect.width
        height = rect.height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct HomePositionRevision: Codable, Equatable {
    let geometry: StoredGeometry
    let savedAt: Date
}

struct WindowProfile: Codable, Identifiable, Equatable {
    let id: UUID
    let bundleIdentifier: String
    let applicationName: String
    let displayFingerprint: DisplayFingerprint
    let displayName: String
    let geometry: StoredGeometry
    let updatedAt: Date
    let history: [HomePositionRevision]
    let future: [HomePositionRevision]

    init(
        id: UUID,
        bundleIdentifier: String,
        applicationName: String,
        displayFingerprint: DisplayFingerprint,
        displayName: String,
        geometry: StoredGeometry,
        updatedAt: Date,
        history: [HomePositionRevision] = [],
        future: [HomePositionRevision] = []
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.displayFingerprint = displayFingerprint
        self.displayName = displayName
        self.geometry = geometry
        self.updatedAt = updatedAt
        self.history = history
        self.future = future
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        applicationName = try container.decode(String.self, forKey: .applicationName)
        displayFingerprint = try container.decode(DisplayFingerprint.self, forKey: .displayFingerprint)
        displayName = try container.decode(String.self, forKey: .displayName)
        geometry = try container.decode(StoredGeometry.self, forKey: .geometry)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        history = try container.decodeIfPresent([HomePositionRevision].self, forKey: .history) ?? []
        future = try container.decodeIfPresent([HomePositionRevision].self, forKey: .future) ?? []
    }
}
