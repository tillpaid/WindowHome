import AppKit
import QuartzCore

enum WindowAnimationTiming {
    nonisolated static let defaultDuration: TimeInterval = 0.32
    nonisolated static let durationRange: ClosedRange<Double> = 0.15...0.8

    nonisolated static func clampedDuration(_ duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite else { return defaultDuration }
        return min(durationRange.upperBound, max(durationRange.lowerBound, duration))
    }
}

enum WindowAnimationCurve {

    static func geometry(from source: WindowGeometry, to target: WindowGeometry, progress: Double) -> WindowGeometry {
        let t = CGFloat(min(1, max(0, progress)))
        // Zero velocity and acceleration at both ends, including the final exact-frame write.
        let eased = t * t * t * (t * (t * 6 - 15) + 10)
        return WindowGeometry(
            origin: CGPoint(x: source.origin.x + (target.origin.x - source.origin.x) * eased,
                            y: source.origin.y + (target.origin.y - source.origin.y) * eased),
            size: CGSize(width: source.size.width + (target.size.width - source.size.width) * eased,
                         height: source.size.height + (target.size.height - source.size.height) * eased)
        )
    }

    static func shouldAnimate(enabled: Bool, reduceMotion: Bool) -> Bool { enabled && !reduceMotion }
}

/// Owns only explicitly requested transitions. No AX/window-move observer is installed.
@MainActor
final class WindowAnimationService {
    typealias WindowID = DisplayMoveRequests.WindowID
    private static let stalledWriteDuration: TimeInterval = 0.08

    private struct Transition {
        let source: WindowGeometry
        let target: WindowGeometry
        let startedAt: TimeInterval
        let duration: TimeInterval
        let write: (WindowGeometry) throws -> Void
        let finalWrite: (WindowGeometry) throws -> Void
        let completion: () throws -> Void
        let failure: (Error) -> Void
    }

    private let now: () -> TimeInterval
    private let automaticTicks: Bool
    private let reduceMotion: () -> Bool
    private var transitions: [WindowID: Transition] = [:]
    private var invalidateDisplayLink: (() -> Void)?
    private var fallbackTimer: Timer?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    var onMouseInterruption: (() -> Void)?

    init(
        automaticTicks: Bool = true,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.automaticTicks = automaticTicks
        self.now = now
        self.reduceMotion = reduceMotion
    }

    var isAnimating: Bool { !transitions.isEmpty }

    func animate(
        window: WindowID, from source: WindowGeometry, to target: WindowGeometry,
        duration: TimeInterval = WindowAnimationTiming.defaultDuration,
        write: @escaping (WindowGeometry) throws -> Void,
        finalWrite: ((WindowGeometry) throws -> Void)? = nil,
        completion: @escaping () throws -> Void = {}, failure: @escaping (Error) -> Void
    ) throws {
        transitions.removeValue(forKey: window)
        defer { if transitions.isEmpty { stopDriver() } }
        let finalWrite = finalWrite ?? write
        guard source != target else {
            try finalWrite(target)
            try completion()
            return
        }
        let startedAt = now()
        // Perform the first write synchronously so unsupported windows fail at the action boundary.
        do {
            try write(source)
        } catch {
            try finalWrite(target)
            try completion()
            return
        }
        if now() - startedAt > Self.stalledWriteDuration {
            // Slow cross-process calls cannot sustain animation. Finish directly instead of queuing frames.
            try finalWrite(target)
            try completion()
            return
        }
        transitions[window] = Transition(source: source, target: target, startedAt: startedAt,
                                         duration: WindowAnimationTiming.clampedDuration(duration),
                                         write: write, finalWrite: finalWrite, completion: completion, failure: failure)
        if automaticTicks {
            installMouseMonitorsIfNeeded()
            startDriverIfNeeded()
        }
    }

    /// Uses elapsed time, skipping missed frames rather than replaying a backlog.
    func advance() {
        if reduceMotion() {
            cancelAll(finishAtTarget: true)
            return
        }
        for (window, transition) in transitions {
            let progress = (now() - transition.startedAt) / transition.duration
            if progress >= 1 {
                transitions.removeValue(forKey: window)
                finish(transition)
                continue
            }
            let beganWrite = now()
            do {
                try transition.write(WindowAnimationCurve.geometry(from: transition.source, to: transition.target, progress: progress))
                if now() - beganWrite > Self.stalledWriteDuration {
                    transitions.removeValue(forKey: window)
                    finish(transition)
                }
            } catch {
                transitions.removeValue(forKey: window)
                // Intermediate geometry may be rejected even when the final frame is accepted.
                finish(transition)
            }
        }
        if transitions.isEmpty { stopDriver() }
    }

    func cancelAll(finishAtTarget: Bool = false) {
        let pending = Array(transitions.values)
        transitions.removeAll()
        stopDriver()
        if finishAtTarget { pending.forEach(finish) }
    }

    private func finish(_ transition: Transition) {
        do {
            try transition.finalWrite(transition.target)
            try transition.completion()
        } catch { transition.failure(error) }
    }

    private func startDriverIfNeeded() {
        guard invalidateDisplayLink == nil, fallbackTimer == nil, !transitions.isEmpty else { return }
        if #available(macOS 14.0, *), let screen = NSScreen.screens.max(by: { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond }) {
            let target = DisplayLinkTarget(owner: self)
            let link = screen.displayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
            let maximum = Float(min(120, max(1, screen.maximumFramesPerSecond)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            invalidateDisplayLink = { link.invalidate() }
        } else {
            // Ventura: a repeating timer keeps its cadence independent of AX write duration.
            let target = DisplayLinkTarget(owner: self)
            let timer = Timer(timeInterval: 1 / 60, target: target, selector: #selector(DisplayLinkTarget.tick(_:)), userInfo: nil, repeats: true)
            timer.tolerance = 0.0005
            RunLoop.main.add(timer, forMode: .common)
            fallbackTimer = timer
        }
    }

    private final class DisplayLinkTarget: NSObject {
        weak var owner: WindowAnimationService?
        init(owner: WindowAnimationService) { self.owner = owner }
        @objc func tick(_ sender: AnyObject) { owner?.advance() }
    }

    private func installMouseMonitorsIfNeeded() {
        guard localMouseMonitor == nil else { return }
        // Cancel on mouse-down before programmatic drift could be mistaken for a real drag.
        // Mouse events need no additional Input Monitoring permission and are never stored.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.interruptForMouse()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.interruptForMouse()
        }
    }

    private func interruptForMouse() {
        cancelAll()
        onMouseInterruption?()
    }

    private func stopDriver() {
        invalidateDisplayLink?()
        invalidateDisplayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }
}
