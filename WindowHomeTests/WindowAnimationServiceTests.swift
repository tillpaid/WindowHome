import Testing
import Foundation
import CoreGraphics
@testable import WindowHome

@MainActor
struct WindowAnimationServiceTests {
    private let source = WindowGeometry(origin: CGPoint(x: -1200, y: -800), size: CGSize(width: 900, height: 700))
    private let target = WindowGeometry(origin: CGPoint(x: 100, y: 80), size: CGSize(width: 600, height: 450))
    private let first = WindowAnimationService.WindowID(processIdentifier: 1, windowIdentifier: 1)
    private let second = WindowAnimationService.WindowID(processIdentifier: 1, windowIdentifier: 2)
    private enum TestError: Error { case refused }

    @Test func preferenceIsOptInAndPersistsBothValues() throws {
        let suite = "WindowHomeTests.animation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!KeyboardShortcutPreferences.loadAnimatedWindowMoves(defaults: defaults))
        KeyboardShortcutPreferences.saveAnimatedWindowMoves(true, defaults: defaults)
        #expect(KeyboardShortcutPreferences.loadAnimatedWindowMoves(defaults: defaults))
        KeyboardShortcutPreferences.saveAnimatedWindowMoves(false, defaults: defaults)
        #expect(!KeyboardShortcutPreferences.loadAnimatedWindowMoves(defaults: defaults))
    }

    @Test func curveHasExactEndpointsAndMovesMonotonicallyAcrossNegativeCoordinates() {
        #expect(WindowAnimationCurve.geometry(from: source, to: target, progress: -1) == source)
        #expect(WindowAnimationCurve.geometry(from: source, to: target, progress: 2) == target)
        var previous = source
        for index in 1...100 {
            let frame = WindowAnimationCurve.geometry(from: source, to: target, progress: Double(index) / 100)
            #expect(frame.origin.x >= previous.origin.x)
            #expect(frame.origin.y >= previous.origin.y)
            #expect(frame.size.width <= previous.size.width)
            #expect(frame.size.height <= previous.size.height)
            previous = frame
        }
        #expect(WindowAnimationCurve.geometry(from: source, to: target, progress: 0.05).origin.x - source.origin.x < (target.origin.x - source.origin.x) * 0.05)
    }

    @Test func respectsFeatureFlagAndReduceMotion() {
        #expect(!WindowAnimationCurve.shouldAnimate(enabled: false, reduceMotion: false))
        #expect(!WindowAnimationCurve.shouldAnimate(enabled: true, reduceMotion: true))
        #expect(WindowAnimationCurve.shouldAnimate(enabled: true, reduceMotion: false))
    }

    @Test func completionRunsOnlyAfterExactFinalFrameAndMissedTicksAreSkipped() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var frames: [WindowGeometry] = []
        var completed = false
        try service.animate(window: first, from: source, to: target, write: { frames.append($0) }, completion: {
            #expect(frames.last == target)
            completed = true
        }, failure: { _ in Issue.record("Unexpected failure") })
        time = WindowAnimationTiming.defaultDuration / 2
        service.advance()
        #expect(!completed)
        #expect(frames.last == WindowAnimationCurve.geometry(from: source, to: target, progress: 0.5))
        time = 3
        service.advance()
        #expect(completed)
        #expect(frames.count == 3)
        #expect(!service.isAnimating)
    }

    @Test func cancellationPreventsOldWritesAndCompletion() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var frames: [WindowGeometry] = []
        try service.animate(window: first, from: source, to: target, write: { frames.append($0) },
                            completion: { Issue.record("Cancelled transition completed") }, failure: { _ in })
        service.cancelAll()
        time = 1
        service.advance()
        #expect(frames.count == 1)
        #expect(!service.isAnimating)
    }

    @Test func newerRequestReplacesSameWindowWhileOtherWindowFinishesIndependently() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var firstFrames: [WindowGeometry] = []
        var secondFinished = false
        try service.animate(window: first, from: source, to: target, write: { _ in },
                            completion: { Issue.record("Stale request completed") }, failure: { _ in })
        try service.animate(window: second, from: source, to: target, write: { _ in },
                            completion: { secondFinished = true }, failure: { _ in })
        try service.animate(window: first, from: target, to: source, write: { firstFrames.append($0) }, failure: { _ in })
        time = 1
        service.advance()
        #expect(firstFrames.last == source)
        #expect(secondFinished)
        #expect(!service.isAnimating)
    }

    @Test func disablingOrReducingMotionFinishesAtTarget() throws {
        var reduceMotion = false
        let service = WindowAnimationService(automaticTicks: false, now: { 0 }, reduceMotion: { reduceMotion })
        var frames: [WindowGeometry] = []
        var completions = 0
        try service.animate(window: first, from: source, to: target, write: { frames.append($0) },
                            completion: { completions += 1 }, failure: { _ in })
        service.cancelAll(finishAtTarget: true)
        #expect(frames.last == target)
        #expect(completions == 1)
        try service.animate(window: first, from: target, to: source, write: { frames.append($0) },
                            completion: { completions += 1 }, failure: { _ in })
        reduceMotion = true
        service.advance()
        #expect(frames.last == source)
        #expect(completions == 2)
        #expect(!service.isAnimating)
    }

    @Test func slowAppFallsBackWithoutQueuingAnAnimation() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var frames: [WindowGeometry] = []
        var completed = false
        try service.animate(window: first, from: source, to: target, write: {
            frames.append($0)
            time += 0.1
        }, completion: { completed = true }, failure: { _ in })
        #expect(frames.count == 2)
        #expect(frames.last == target)
        #expect(completed)
        #expect(!service.isAnimating)
    }

    @Test func rejectedIntermediateFrameFallsBackAndDoesNotStopOtherWindows() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var writes = 0
        var completed = false
        var otherCompleted = false
        try service.animate(window: first, from: source, to: target, write: { frame in
            writes += 1
            if writes == 2 { throw TestError.refused }
            if writes == 3 { #expect(frame == target) }
        }, completion: { completed = true }, failure: { _ in Issue.record("Final target should work") })
        try service.animate(window: second, from: source, to: target, write: { _ in },
                            completion: { otherCompleted = true }, failure: { _ in })
        time = 0.1
        service.advance()
        #expect(completed)
        #expect(service.isAnimating)
        time = 1
        service.advance()
        #expect(otherCompleted)
    }

    @Test func finalFailureIsReportedAndNeverCompletes() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var failed = false
        try service.animate(window: first, from: source, to: target, write: { frame in
            if frame == target { throw TestError.refused }
        }, completion: { Issue.record("Failed transition completed") }, failure: { _ in failed = true })
        time = 1
        service.advance()
        #expect(failed)
        #expect(!service.isAnimating)
    }

    @Test func initialFailureThrowsWithoutPendingFrames() {
        let service = WindowAnimationService(automaticTicks: false, reduceMotion: { false })
        #expect(throws: TestError.self) {
            try service.animate(window: first, from: source, to: target, write: { _ in throw TestError.refused }, failure: { _ in })
        }
        #expect(!service.isAnimating)
    }

    @Test func rejectedFirstIntermediateFrameCanStillApplyFinalTarget() throws {
        let service = WindowAnimationService(automaticTicks: false, reduceMotion: { false })
        var completed = false
        var frames: [WindowGeometry] = []
        try service.animate(window: first, from: source, to: target, write: { frame in
            if frame != target { throw TestError.refused }
            frames.append(frame)
        }, completion: { completed = true }, failure: { _ in })
        #expect(frames == [target])
        #expect(completed)
        #expect(!service.isAnimating)
    }

    @Test func firstWriteStaysAtSourceAndFinalUsesActionWriter() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var frames: [WindowGeometry] = []
        var finalFrames: [WindowGeometry] = []
        try service.animate(window: first, from: source, to: target, write: { frames.append($0) },
                            finalWrite: { finalFrames.append($0) }, failure: { _ in })
        #expect(frames == [source])
        #expect(finalFrames.isEmpty)
        time = 1
        service.advance()
        #expect(finalFrames == [target])
        #expect(frames == [source])
    }

    @Test func finalActionWriterIsUsedOnFallbackAndDisable() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var targets: [WindowGeometry] = []
        try service.animate(window: first, from: source, to: target, write: { _ in
            if time > 0 { throw TestError.refused }
        }, finalWrite: { targets.append($0) }, failure: { _ in })
        time = 0.1
        service.advance()
        #expect(targets == [target])
        try service.animate(window: second, from: target, to: source, write: { _ in },
                            finalWrite: { targets.append($0) }, failure: { _ in })
        service.cancelAll(finishAtTarget: true)
        #expect(targets == [target, source])
    }

    @Test func animationWriterSkipsSizeForPositionOnlyMovesAndDuplicateFrames() throws {
        var positions: [CGPoint] = []
        let writer = WindowAnimationGeometryWriter(source: source, writeOrder: .resizeBeforeMove,
            setPosition: { positions.append($0) }, setSize: { _ in Issue.record("Position-only move resized") })
        let moved = WindowGeometry(origin: target.origin, size: source.size)
        try writer.write(source)
        try writer.write(moved)
        try writer.write(moved)
        #expect(positions == [target.origin])
    }

    @Test func animationWriterRetainsWriteOrderAndRepositionsAfterSizeOnlyChange() throws {
        for resizeFirst in [true, false] {
            var operations: [String] = []
            let writer = WindowAnimationGeometryWriter(source: source,
                writeOrder: resizeFirst ? .resizeBeforeMove : .moveBeforeResize,
                setPosition: { _ in operations.append("position") }, setSize: { _ in operations.append("size") })
            try writer.write(WindowGeometry(origin: source.origin, size: target.size))
            #expect(operations == (resizeFirst ? ["size", "position"] : ["position", "size"]))
            operations.removeAll()
            try writer.write(WindowGeometry(origin: target.origin, size: target.size))
            #expect(operations == ["position"])
        }
    }

    @Test func rejectedAttributeIsNotCachedAsApplied() throws {
        var reject = true
        var writes = 0
        let writer = WindowAnimationGeometryWriter(source: source, writeOrder: .resizeBeforeMove,
            setPosition: { _ in
                writes += 1
                if reject { throw TestError.refused }
            }, setSize: { _ in })
        let moved = WindowGeometry(origin: target.origin, size: source.size)
        #expect(throws: TestError.self) { try writer.write(moved) }
        reject = false
        try writer.write(moved)
        #expect(writes == 2)
    }

    @Test func transientSlowWriteDoesNotJumpToFinalFrame() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var completed = false
        try service.animate(window: first, from: source, to: target, write: { _ in time += 0.04 },
                            completion: { completed = true }, failure: { _ in })
        #expect(service.isAnimating)
        time = 0.1
        service.advance()
        #expect(service.isAnimating)
        #expect(!completed)
        time = 1
        service.advance()
        #expect(completed)
    }

    @Test func animationDurationDefaultsPersistsAndClampsInvalidValues() throws {
        let suite = "WindowHomeTests.animationDuration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(KeyboardShortcutPreferences.loadWindowAnimationDuration(defaults: defaults) == 0.32)
        KeyboardShortcutPreferences.saveWindowAnimationDuration(0.64, defaults: defaults)
        #expect(KeyboardShortcutPreferences.loadWindowAnimationDuration(defaults: defaults) == 0.64)
        KeyboardShortcutPreferences.saveWindowAnimationDuration(-1, defaults: defaults)
        #expect(KeyboardShortcutPreferences.loadWindowAnimationDuration(defaults: defaults) == 0.15)
        KeyboardShortcutPreferences.saveWindowAnimationDuration(2, defaults: defaults)
        #expect(KeyboardShortcutPreferences.loadWindowAnimationDuration(defaults: defaults) == 0.8)
        KeyboardShortcutPreferences.saveWindowAnimationDuration(.nan, defaults: defaults)
        #expect(KeyboardShortcutPreferences.loadWindowAnimationDuration(defaults: defaults) == 0.32)
        defaults.set(-2.0, forKey: "windowAnimationDuration")
        #expect(KeyboardShortcutPreferences.loadWindowAnimationDuration(defaults: defaults) == 0.15)
        defaults.set("invalid", forKey: "windowAnimationDuration")
        #expect(KeyboardShortcutPreferences.loadWindowAnimationDuration(defaults: defaults) == 0.32)
        #expect(WindowAnimationTiming.clampedDuration(.infinity) == 0.32)
    }

    @Test func windowsKeepTheirRequestedDurationIndependently() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var shortCompleted = false
        var longCompleted = false
        var longFrames: [WindowGeometry] = []
        try service.animate(window: first, from: source, to: target, duration: 0.2,
                            write: { _ in }, completion: { shortCompleted = true }, failure: { _ in })
        try service.animate(window: second, from: source, to: target, duration: 0.8,
                            write: { longFrames.append($0) }, completion: { longCompleted = true }, failure: { _ in })
        time = 0.4
        service.advance()
        #expect(shortCompleted)
        #expect(!longCompleted)
        #expect(longFrames.last == WindowAnimationCurve.geometry(from: source, to: target, progress: 0.5))
        time = 0.8
        service.advance()
        #expect(longCompleted)
        #expect(!service.isAnimating)
    }

    @Test func animationClampsZeroDurationRatherThanFinishingImmediately() throws {
        var time = 0.0
        let service = WindowAnimationService(automaticTicks: false, now: { time }, reduceMotion: { false })
        var completed = false
        try service.animate(window: first, from: source, to: target, duration: 0,
                            write: { _ in }, completion: { completed = true }, failure: { _ in })
        time = 0.1
        service.advance()
        #expect(!completed)
        time = 0.15
        service.advance()
        #expect(completed)
    }
}
