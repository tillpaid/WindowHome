import CoreGraphics

/// A prepared AX writer avoids repeated capability checks and unchanged size writes.
/// The action's existing writer still applies the final frame and any origin correction.
@MainActor
final class WindowAnimationGeometryWriter {
    private var previous: WindowGeometry
    private let writeOrder: DisplayMoveGeometryWriteOrder
    private let setPosition: (CGPoint) throws -> Void
    private let setSize: (CGSize) throws -> Void

    init(
        source: WindowGeometry, writeOrder: DisplayMoveGeometryWriteOrder,
        setPosition: @escaping (CGPoint) throws -> Void,
        setSize: @escaping (CGSize) throws -> Void
    ) {
        previous = source
        self.writeOrder = writeOrder
        self.setPosition = setPosition
        self.setSize = setSize
    }

    func write(_ geometry: WindowGeometry) throws {
        let sizeChanged = geometry.size != previous.size
        switch writeOrder {
        case .resizeBeforeMove:
            try writeSize(geometry.size)
            // A resize may shift the app's origin even when the requested position is unchanged.
            try writePosition(geometry.origin, force: sizeChanged)
        case .moveBeforeResize:
            try writePosition(geometry.origin, force: sizeChanged)
            try writeSize(geometry.size)
        }
    }

    private func writePosition(_ position: CGPoint, force: Bool) throws {
        guard force || position != previous.origin else { return }
        try setPosition(position)
        previous = WindowGeometry(origin: position, size: previous.size)
    }

    private func writeSize(_ size: CGSize) throws {
        guard size != previous.size else { return }
        try setSize(size)
        previous = WindowGeometry(origin: previous.origin, size: size)
    }
}
