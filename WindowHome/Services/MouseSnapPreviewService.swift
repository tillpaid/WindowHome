import AppKit
import QuartzCore

@MainActor
final class MouseSnapPreviewService {
    private enum Constants {
        static let visibleAlpha: CGFloat = 1
        static let appearDuration: TimeInterval = 0.18
        static let activationAppearDuration: TimeInterval = 0.22
        static let activationDisappearDuration: TimeInterval = 0.12
        static let activationHighlightDuration: TimeInterval = 0.12
        static let frameTolerance: CGFloat = 1
    }

    private final class PreviewView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.14).cgColor
            layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.95).cgColor
            layer?.borderWidth = 3
            layer?.cornerRadius = 12
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private final class ActivationZoneView: NSView {
        private var active: Bool?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.cornerRadius = 8
            layer?.masksToBounds = true
            autoresizingMask = [.width, .height]
            setActive(false, animated: false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func setActive(_ active: Bool, animated: Bool = true) {
            guard self.active != active, let layer else { return }
            self.active = active

            let backgroundColor = NSColor.systemBlue.withAlphaComponent(active ? 0.32 : 0.12).cgColor
            let borderColor = NSColor.systemBlue.withAlphaComponent(active ? 1 : 0.7).cgColor
            let borderWidth: CGFloat = active ? 3 : 2

            if animated {
                animate(layer: layer, keyPath: "backgroundColor", from: layer.presentation()?.backgroundColor ?? layer.backgroundColor, to: backgroundColor)
                animate(layer: layer, keyPath: "borderColor", from: layer.presentation()?.borderColor ?? layer.borderColor, to: borderColor)
                animate(layer: layer, keyPath: "borderWidth", from: layer.presentation()?.borderWidth ?? layer.borderWidth, to: borderWidth)
            }
            layer.backgroundColor = backgroundColor
            layer.borderColor = borderColor
            layer.borderWidth = borderWidth
        }

        func animateAppearance() {
            guard let layer else { return }
            layer.removeAnimation(forKey: "activation-zone-appearance")

            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0
            opacity.toValue = 1

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.82
            scale.toValue = 1

            let group = CAAnimationGroup()
            group.animations = [opacity, scale]
            group.duration = Constants.activationAppearDuration
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(group, forKey: "activation-zone-appearance")
        }

        private func animate(layer: CALayer, keyPath: String, from: Any?, to: Any) {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = Constants.activationHighlightDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "activation-zone-\(keyPath)")
        }
    }

    private var panel: NSPanel?
    private var lastTargetFrame: CGRect?
    private var activationZonePanels: [SnapDirection: NSPanel] = [:]
    private var visibleActivationDirections: Set<SnapDirection> = []

    func show(frame: CGRect, from sourceFrame: CGRect) {
        let activePanel: NSPanel
        if let existing = panel {
            activePanel = existing
        } else {
            activePanel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            activePanel.isOpaque = false
            activePanel.backgroundColor = .clear
            activePanel.hasShadow = false
            activePanel.level = .statusBar
            activePanel.ignoresMouseEvents = true
            activePanel.hidesOnDeactivate = false
            activePanel.animationBehavior = .none
            activePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            activePanel.contentView = PreviewView(frame: frame)
            self.panel = activePanel
        }

        let shouldAnimateAppearance = activePanel.alphaValue == 0 || activePanel.frame.isEmpty || lastTargetFrame == nil
        if !shouldAnimateAppearance, let lastTargetFrame, approximatelyEqual(lastTargetFrame, frame) {
            return
        }
        let initialFrame = shouldAnimateAppearance ? sourceFrame : activePanel.frame
        activePanel.contentView?.frame = CGRect(origin: .zero, size: initialFrame.size)
        activePanel.setFrame(initialFrame, display: true)
        activePanel.orderFrontRegardless()

        if shouldAnimateAppearance { activePanel.alphaValue = 0 }

        if shouldAnimateAppearance {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.appearDuration
                activePanel.animator().alphaValue = Constants.visibleAlpha
                activePanel.animator().setFrame(frame, display: true)
            }
        } else {
            activePanel.alphaValue = Constants.visibleAlpha
            activePanel.setFrame(frame, display: true)
        }
        activePanel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
        lastTargetFrame = frame
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.alphaValue = 0
        lastTargetFrame = nil
    }

    func showActivationZones(_ zones: [MouseSnapActivationZone], activeDirection: SnapDirection?) {
        let requestedDirections = Set(zones.map(\.direction))
        for direction in Array(visibleActivationDirections) where !requestedDirections.contains(direction) {
            hideActivationZone(direction)
        }

        for zone in zones {
            let activePanel: NSPanel
            if let existing = activationZonePanels[zone.direction] {
                activePanel = existing
            } else {
                activePanel = makeActivationZonePanel(frame: zone.frame)
                activationZonePanels[zone.direction] = activePanel
            }
            let isAppearing = visibleActivationDirections.insert(zone.direction).inserted
            activePanel.setFrame(zone.frame, display: true)
            activePanel.contentView?.frame = CGRect(origin: .zero, size: zone.frame.size)
            (activePanel.contentView as? ActivationZoneView)?.setActive(zone.direction == activeDirection)
            activePanel.alphaValue = Constants.visibleAlpha
            activePanel.orderFrontRegardless()
            if isAppearing {
                (activePanel.contentView as? ActivationZoneView)?.animateAppearance()
            }
        }
    }

    func hideActivationZones() {
        for direction in Array(visibleActivationDirections) {
            hideActivationZone(direction)
        }
    }

    private func hideActivationZone(_ direction: SnapDirection) {
        guard visibleActivationDirections.remove(direction) != nil,
              let panel = activationZonePanels[direction] else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.activationDisappearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.activationDisappearDuration) { [weak self, weak panel] in
            guard let self, !self.visibleActivationDirections.contains(direction) else { return }
            panel?.orderOut(nil)
        }
    }

    private func makeActivationZonePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = ActivationZoneView(frame: CGRect(origin: .zero, size: frame.size))
        panel.contentView = view
        return panel
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= Constants.frameTolerance
        && abs(lhs.minY - rhs.minY) <= Constants.frameTolerance
        && abs(lhs.width - rhs.width) <= Constants.frameTolerance
        && abs(lhs.height - rhs.height) <= Constants.frameTolerance
    }
}
