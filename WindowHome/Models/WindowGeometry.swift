import CoreGraphics

struct WindowGeometry: Equatable, Sendable {
    let origin: CGPoint
    let size: CGSize

    init(origin: CGPoint, size: CGSize) {
        self.origin = origin
        self.size = size
    }

    var rect: CGRect { CGRect(origin: origin, size: size) }

    var description: String {
        "x: \(origin.x.rounded()), y: \(origin.y.rounded()), width: \(size.width.rounded()), height: \(size.height.rounded())"
    }
}

enum WindowResizeAction: CaseIterable {
    case increaseWidth
    case decreaseWidth
    case increaseHeight
    case decreaseHeight
}

enum SymmetricWindowResize {
    static func geometry(
        from geometry: WindowGeometry,
        action: WindowResizeAction,
        step: CGFloat,
        minimumDimension: CGFloat = 1
    ) -> WindowGeometry {
        let effectiveStep = max(0, step)
        let minimumDimension = max(1, minimumDimension)
        var size = geometry.size

        switch action {
        case .increaseWidth:
            size.width += effectiveStep
        case .decreaseWidth:
            size.width = max(minimumDimension, size.width - effectiveStep)
        case .increaseHeight:
            size.height += effectiveStep
        case .decreaseHeight:
            size.height = max(minimumDimension, size.height - effectiveStep)
        }

        return geometryWithPreservedCenter(source: geometry, size: size)
    }

    static func geometryWithPreservedCenter(source: WindowGeometry, size: CGSize) -> WindowGeometry {
        WindowGeometry(
            origin: CGPoint(
                x: source.origin.x + (source.size.width - size.width) / 2,
                y: source.origin.y + (source.size.height - size.height) / 2
            ),
            size: size
        )
    }
}

enum PrototypeWindowTransform {
    static func inset(from geometry: WindowGeometry, amount: CGFloat = 24, minimumSize: CGSize = CGSize(width: 240, height: 180)) -> WindowGeometry {
        let horizontalInset = min(amount, max(0, (geometry.size.width - minimumSize.width) / 2))
        let verticalInset = min(amount, max(0, (geometry.size.height - minimumSize.height) / 2))

        return WindowGeometry(
            origin: CGPoint(x: geometry.origin.x + horizontalInset, y: geometry.origin.y + verticalInset),
            size: CGSize(width: geometry.size.width - (horizontalInset * 2), height: geometry.size.height - (verticalInset * 2))
        )
    }
}
