//
//  WindowHomeTests.swift
//  WindowHomeTests
//
//  Created by Александр Майборода on 24.07.2026.
//

import Testing
import CoreGraphics
import Foundation
@testable import WindowHome

@MainActor
struct WindowHomeTests {

    @Test func prototypeInsetMovesAndShrinksGeometry() {
        let result = PrototypeWindowTransform.inset(from: WindowGeometry(origin: CGPoint(x: 100, y: 80), size: CGSize(width: 800, height: 600)))

        #expect(result.origin == CGPoint(x: 124, y: 104))
        #expect(result.size == CGSize(width: 752, height: 552))
    }

    @Test func prototypeInsetDoesNotGoBelowMinimumSize() {
        let result = PrototypeWindowTransform.inset(from: WindowGeometry(origin: .zero, size: CGSize(width: 250, height: 190)))

        #expect(result.size == CGSize(width: 240, height: 180))
        #expect(result.origin == CGPoint(x: 5, y: 5))
    }

    @Test func symmetricResizeShrinksBothAxesAroundTheSameCenter() {
        var geometry = WindowGeometry(
            origin: CGPoint(x: 100, y: 100),
            size: CGSize(width: 100, height: 100)
        )

        for _ in 0..<2 {
            geometry = SymmetricWindowResize.geometry(from: geometry, action: .decreaseWidth, step: 10)
            geometry = SymmetricWindowResize.geometry(from: geometry, action: .decreaseHeight, step: 10)
        }

        #expect(geometry.origin == CGPoint(x: 110, y: 110))
        #expect(geometry.size == CGSize(width: 80, height: 80))
        #expect(geometry.rect.midX == 150)
        #expect(geometry.rect.midY == 150)
    }

    @Test func symmetricResizeChangesOnlyTheRequestedAxis() {
        let source = WindowGeometry(
            origin: CGPoint(x: 200, y: 300),
            size: CGSize(width: 800, height: 600)
        )

        let wider = SymmetricWindowResize.geometry(from: source, action: .increaseWidth, step: 40)
        let taller = SymmetricWindowResize.geometry(from: source, action: .increaseHeight, step: 20)

        #expect(wider == WindowGeometry(origin: CGPoint(x: 180, y: 300), size: CGSize(width: 840, height: 600)))
        #expect(taller == WindowGeometry(origin: CGPoint(x: 200, y: 290), size: CGSize(width: 800, height: 620)))
    }

    @Test func symmetricResizeHonorsMinimumDimensionAndKeepsCenter() {
        let source = WindowGeometry(
            origin: CGPoint(x: 10, y: 20),
            size: CGSize(width: 15, height: 25)
        )

        let result = SymmetricWindowResize.geometry(
            from: source,
            action: .decreaseWidth,
            step: 20,
            minimumDimension: 10
        )

        #expect(result.origin == CGPoint(x: 12.5, y: 20))
        #expect(result.size == CGSize(width: 10, height: 25))
        #expect(result.rect.midX == source.rect.midX)
    }

    @Test func coordinateConversionRoundTripsAcrossMultipleDisplays() {
        let converter = CoordinateConverter(desktopFrame: CGRect(x: -1440, y: 0, width: 3168, height: 2234))
        let source = WindowGeometry(origin: CGPoint(x: -1200, y: 220), size: CGSize(width: 700, height: 500))

        let result = converter.accessibilityGeometry(fromAppKit: converter.appKitRect(fromAccessibility: source))

        #expect(result == source)
    }

    @Test func coordinateConversionUsesMainDisplayTopWhenAnotherDisplayIsAboveIt() {
        let mainDisplay = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let upperDisplay = CGRect(x: -280, y: 900, width: 2000, height: 1125)
        let desktopFrame = mainDisplay.union(upperDisplay)
        let converter = CoordinateConverter(
            desktopFrame: desktopFrame,
            accessibilityReferenceY: mainDisplay.maxY
        )
        let upperWindow = CGRect(x: 100, y: 1025, width: 1200, height: 800)

        let accessibilityGeometry = converter.accessibilityGeometry(fromAppKit: upperWindow)

        #expect(accessibilityGeometry.origin == CGPoint(x: 100, y: -925))
        #expect(converter.appKitRect(fromAccessibility: accessibilityGeometry) == upperWindow)
    }

    @Test func verticalDisplaySelectionUsesLargestWindowIntersection() {
        let lowerDisplay = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let upperDisplay = CGRect(x: -280, y: 900, width: 2000, height: 1125)
        let windowMostlyOnUpperDisplay = CGRect(x: 100, y: 760, width: 1200, height: 800)

        let result = DisplayService.displayIndex(
            for: windowMostlyOnUpperDisplay,
            in: [lowerDisplay, upperDisplay]
        )

        #expect(result == 1)
    }

    @Test func movingOversizedWindowToLowerDisplayRequestsResizeAndFitsTarget() {
        let mainDisplay = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let upperDisplay = CGRect(x: -280, y: 900, width: 2000, height: 1125)
        let converter = CoordinateConverter(
            desktopFrame: mainDisplay.union(upperDisplay),
            accessibilityReferenceY: mainDisplay.maxY
        )
        let targetDisplay = DisplayContext(
            fingerprint: displayFingerprint(serialNumber: 1),
            name: "Built-in Display",
            visibleFrame: mainDisplay
        )
        let source = converter.accessibilityGeometry(
            fromAppKit: CGRect(x: -200, y: 925, width: 1900, height: 1050)
        )
        let desiredTarget = converter.accessibilityGeometry(
            fromAppKit: CGRect(x: 120, y: 120, width: 800, height: 600)
        )

        let plan = DisplayService().transferPlan(
            from: source,
            toward: desiredTarget,
            on: targetDisplay,
            padding: 20,
            converter: converter
        )
        let appKitResult = converter.appKitRect(fromAccessibility: plan.geometry)

        #expect(plan.requiresResize)
        #expect(appKitResult == CGRect(x: 20, y: 20, width: 1400, height: 860))
        #expect(mainDisplay.insetBy(dx: 20, dy: 20).contains(appKitResult))
    }

    @Test func movingWindowThatFitsDestinationPreservesItsSize() {
        let mainDisplay = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let converter = CoordinateConverter(desktopFrame: mainDisplay)
        let targetDisplay = DisplayContext(
            fingerprint: displayFingerprint(serialNumber: 1),
            name: "Built-in Display",
            visibleFrame: mainDisplay
        )
        let source = WindowGeometry(
            origin: CGPoint(x: 100, y: -700),
            size: CGSize(width: 800, height: 600)
        )
        let desiredTarget = converter.accessibilityGeometry(
            fromAppKit: CGRect(x: 120, y: 250, width: 500, height: 400)
        )

        let plan = DisplayService().transferPlan(
            from: source,
            toward: desiredTarget,
            on: targetDisplay,
            padding: 20,
            converter: converter
        )

        #expect(!plan.requiresResize)
        #expect(plan.geometry.size == source.size)
        #expect(plan.geometry.origin == desiredTarget.origin)
    }

    @Test func displayMoveAutomationControlsFullHomeRestoreForRegularWindows() {
        #expect(DisplayMoveHomePolicy.shouldApplyFullHome(
            automationEnabled: true,
            sourceIsFullScreen: false,
            sourceIsWindowHomeSnapped: false,
            sourceIsSystemTiled: false
        ))
        #expect(!DisplayMoveHomePolicy.shouldApplyFullHome(
            automationEnabled: false,
            sourceIsFullScreen: false,
            sourceIsWindowHomeSnapped: false,
            sourceIsSystemTiled: false
        ))
    }

    @Test func displayMoveKeepsFullHomeRestoreForSnappedAndOversizedLayouts() {
        #expect(DisplayMoveHomePolicy.shouldApplyFullHome(
            automationEnabled: false,
            sourceIsFullScreen: true,
            sourceIsWindowHomeSnapped: false,
            sourceIsSystemTiled: false
        ))
        #expect(DisplayMoveHomePolicy.shouldApplyFullHome(
            automationEnabled: false,
            sourceIsFullScreen: false,
            sourceIsWindowHomeSnapped: true,
            sourceIsSystemTiled: false
        ))
        #expect(DisplayMoveHomePolicy.shouldApplyFullHome(
            automationEnabled: false,
            sourceIsFullScreen: false,
            sourceIsWindowHomeSnapped: false,
            sourceIsSystemTiled: true
        ))
    }

    @Test func displayMoveChoosesWriteOrderThatAvoidsCrossDisplaySizeFlash() {
        let largeSource = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        #expect(DisplayMoveHomePolicy.geometryWriteOrder(
            targetSize: CGSize(width: 900, height: 700),
            sourceVisibleFrame: largeSource,
            padding: 20
        ) == .resizeBeforeMove)

        let smallSource = CGRect(x: 0, y: 0, width: 1000, height: 700)
        #expect(DisplayMoveHomePolicy.geometryWriteOrder(
            targetSize: CGSize(width: 1400, height: 900),
            sourceVisibleFrame: smallSource,
            padding: 20
        ) == .moveBeforeResize)
    }

    @Test func displayMoveStabilizationReappliesDelayedClaudeFullscreenLayout() {
        let home = WindowGeometry(
            origin: CGPoint(x: 100, y: 120),
            size: CGSize(width: 900, height: 700)
        )
        let delayedFullscreen = WindowGeometry(
            origin: CGPoint(x: 12, y: 30),
            size: CGSize(width: 1400, height: 900)
        )

        #expect(DisplayMoveHomePolicy.stabilizationDecision(
            actual: delayedFullscreen,
            target: home,
            isOnTargetDisplay: true
        ) == .reapplyAndVerifyLater)
        #expect(DisplayMoveHomePolicy.stabilizationDecision(
            actual: home,
            target: home,
            isOnTargetDisplay: true
        ) == .verifyLater)
        #expect(DisplayMoveHomePolicy.stabilizationDecision(
            actual: delayedFullscreen,
            target: home,
            isOnTargetDisplay: false
        ) == .stop)
        #expect(DisplayMoveHomePolicy.stabilizationDelays.reduce(0, +) < 2)
    }

    @Test func storedGeometryScalesWhenVisibleFrameChanges() {
        let originalConverter = CoordinateConverter(desktopFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let originalVisibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let geometry = WindowGeometry(origin: CGPoint(x: 100, y: 400), size: CGSize(width: 500, height: 300))
        let stored = StoredGeometry(accessibilityGeometry: geometry, visibleFrame: originalVisibleFrame, converter: originalConverter)
        let resizedConverter = CoordinateConverter(desktopFrame: CGRect(x: 0, y: 0, width: 2000, height: 1600))

        let result = stored.accessibilityGeometry(for: CGRect(x: 0, y: 0, width: 2000, height: 1600), converter: resizedConverter)

        #expect(result.origin == CGPoint(x: 200, y: 800))
        #expect(result.size == CGSize(width: 1000, height: 600))
    }

    @Test func displayFingerprintTreatsEachResolutionAsItsOwnHome() {
        let fullHD = DisplayFingerprint(
            vendorNumber: 1,
            modelNumber: 2,
            serialNumber: 3,
            isBuiltIn: false,
            logicalWidth: 1920,
            logicalHeight: 1080,
            pixelWidth: 1920,
            pixelHeight: 1080
        )
        let quadHD = DisplayFingerprint(
            vendorNumber: 1,
            modelNumber: 2,
            serialNumber: 3,
            isBuiltIn: false,
            logicalWidth: 2560,
            logicalHeight: 1440,
            pixelWidth: 2560,
            pixelHeight: 1440
        )

        #expect(fullHD != quadHD)
    }

    @Test func legacyDisplayFingerprintRemainsReadableButDoesNotMatchResolutionSpecificHome() throws {
        let data = Data("""
        {
          "vendorNumber": 1,
          "modelNumber": 2,
          "serialNumber": 3,
          "isBuiltIn": false
        }
        """.utf8)
        let legacy = try JSONDecoder().decode(DisplayFingerprint.self, from: data)
        let current = DisplayFingerprint(
            vendorNumber: 1,
            modelNumber: 2,
            serialNumber: 3,
            isBuiltIn: false,
            logicalWidth: 1920,
            logicalHeight: 1080,
            pixelWidth: 1920,
            pixelHeight: 1080
        )

        #expect(legacy.logicalWidth == 0)
        #expect(legacy.pixelWidth == 0)
        #expect(legacy != current)
    }

    @Test func builtInDisplaySharesOneHomeAcrossSayNoToNotchModes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowHomeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("profiles.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let notchVisibleMode = builtInDisplayFingerprint(logicalHeight: 945)
        let notchHiddenMode = builtInDisplayFingerprint(logicalHeight: 982)
        let firstPosition = windowProfile(
            displayFingerprint: notchVisibleMode,
            geometry: storedGeometry(x: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 1)
        )
        let newestPosition = windowProfile(
            displayFingerprint: notchHiddenMode,
            geometry: storedGeometry(x: 200),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2)
        )
        try JSONEncoder().encode([firstPosition, newestPosition]).write(to: fileURL)

        let store = try ProfileStore(fileURL: fileURL)
        let sharedHome = try #require(store.profile(
            bundleIdentifier: "com.example.WindowHomeTests",
            displayFingerprint: notchVisibleMode
        ))
        #expect(sharedHome.geometry == newestPosition.geometry)
        #expect(sharedHome.history.map(\.geometry) == [firstPosition.geometry])

        let migratedProfiles = try JSONDecoder().decode([WindowProfile].self, from: Data(contentsOf: fileURL))
        #expect(migratedProfiles.count == 1)

        let currentPosition = windowProfile(
            displayFingerprint: notchVisibleMode,
            geometry: storedGeometry(x: 300),
            updatedAt: Date(timeIntervalSinceReferenceDate: 3)
        )
        try store.upsert(currentPosition)
        let changedModeHome = try #require(store.profile(
            bundleIdentifier: "com.example.WindowHomeTests",
            displayFingerprint: notchHiddenMode
        ))
        #expect(changedModeHome.geometry == currentPosition.geometry)
        #expect(changedModeHome.history.map(\.geometry) == [firstPosition.geometry, newestPosition.geometry])
    }

    @Test func externalDisplayModesRemainSeparateHomes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowHomeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("profiles.json")
        let fullHD = DisplayFingerprint(
            vendorNumber: 1, modelNumber: 2, serialNumber: 3, isBuiltIn: false,
            logicalWidth: 1920, logicalHeight: 1080, pixelWidth: 1920, pixelHeight: 1080
        )
        let quadHD = DisplayFingerprint(
            vendorNumber: 1, modelNumber: 2, serialNumber: 3, isBuiltIn: false,
            logicalWidth: 2560, logicalHeight: 1440, pixelWidth: 2560, pixelHeight: 1440
        )
        let fullHDProfile = windowProfile(displayFingerprint: fullHD, geometry: storedGeometry(x: 100), updatedAt: .distantPast)
        let quadHDProfile = windowProfile(displayFingerprint: quadHD, geometry: storedGeometry(x: 200), updatedAt: .now)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode([fullHDProfile, quadHDProfile]).write(to: fileURL)

        let store = try ProfileStore(fileURL: fileURL)

        #expect(store.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fullHD)?.geometry == fullHDProfile.geometry)
        #expect(store.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: quadHD)?.geometry == quadHDProfile.geometry)
        let persistedProfiles = try JSONDecoder().decode([WindowProfile].self, from: Data(contentsOf: fileURL))
        #expect(persistedProfiles.count == 2)
    }

    @Test func builtInDisplayScaleModesRemainSeparateHomes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowHomeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("profiles.json")
        let defaultScale = builtInDisplayFingerprint(logicalHeight: 982)
        let largerScale = builtInDisplayFingerprint(logicalWidth: 1800, logicalHeight: 1169)
        let defaultScaleProfile = windowProfile(displayFingerprint: defaultScale, geometry: storedGeometry(x: 100), updatedAt: .distantPast)
        let largerScaleProfile = windowProfile(displayFingerprint: largerScale, geometry: storedGeometry(x: 200), updatedAt: .now)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode([defaultScaleProfile, largerScaleProfile]).write(to: fileURL)

        let store = try ProfileStore(fileURL: fileURL)

        #expect(store.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: defaultScale)?.geometry == defaultScaleProfile.geometry)
        #expect(store.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: largerScale)?.geometry == largerScaleProfile.geometry)
        let persistedProfiles = try JSONDecoder().decode([WindowProfile].self, from: Data(contentsOf: fileURL))
        #expect(persistedProfiles.count == 2)
    }

    @Test func defaultShortcutsAreDistinctAndIncludeModifiers() {
        let shortcuts = [
            KeyboardShortcut.saveHomeDefault,
            .restoreHomeDefault,
            .undoHomeDefault,
            .redoHomeDefault,
            .restoreAllDefault,
            .centerAndSaveHomeDefault,
            .moveToNextDisplayDefault,
            .moveToPreviousDisplayDefault,
            .snapLeftDefault,
            .snapRightDefault,
            .snapTopDefault,
            .snapBottomDefault,
            .snapFullScreenDefault,
            .snapTopLeftDefault,
            .snapTopRightDefault,
            .snapBottomLeftDefault,
            .snapBottomRightDefault,
            .increaseWidthDefault,
            .decreaseWidthDefault,
            .increaseHeightDefault,
            .decreaseHeightDefault
        ]

        #expect(shortcuts.enumerated().allSatisfy { index, shortcut in
            !shortcuts.dropFirst(index + 1).contains(shortcut)
        })
        #expect(KeyboardShortcut.saveHomeDefault != KeyboardShortcut.restoreHomeDefault)
        #expect(KeyboardShortcut.restoreHomeDefault != KeyboardShortcut.restoreAllDefault)
        #expect(KeyboardShortcut.saveHomeDefault.displayString == "⌃⌥⌘S")
        #expect(KeyboardShortcut.restoreHomeDefault.displayString == "⌥⌘↩")
        #expect(KeyboardShortcut.undoHomeDefault.displayString == "⌃⌥⌘Z")
        #expect(KeyboardShortcut.redoHomeDefault.displayString == "⌃⌥⇧⌘Z")
        #expect(KeyboardShortcut.restoreAllDefault.displayString == "⌃⌥⌘↩")
        #expect(KeyboardShortcut.centerAndSaveHomeDefault.displayString == "⌃⌘C")
        #expect(KeyboardShortcut.moveToNextDisplayDefault.displayString == "⌃⌥⌘→")
        #expect(KeyboardShortcut.moveToPreviousDisplayDefault.displayString == "⌃⌥⌘←")
        #expect(KeyboardShortcut.snapLeftDefault.displayString == "⌥⌘←")
        #expect(KeyboardShortcut.snapRightDefault.displayString == "⌥⌘→")
        #expect(KeyboardShortcut.snapTopDefault.displayString == "⌥⌘↑")
        #expect(KeyboardShortcut.snapBottomDefault.displayString == "⌥⌘↓")
        #expect(KeyboardShortcut.snapFullScreenDefault.displayString == "⌥⌘F")
        #expect(KeyboardShortcut.snapTopLeftDefault.displayString == "⌃⌘←")
        #expect(KeyboardShortcut.snapTopRightDefault.displayString == "⌃⌘→")
        #expect(KeyboardShortcut.snapBottomLeftDefault.displayString == "⌃⇧⌘←")
        #expect(KeyboardShortcut.snapBottomRightDefault.displayString == "⌃⇧⌘→")
        #expect(KeyboardShortcut.increaseWidthDefault.displayString == "⌃⌥⇧⌘→")
        #expect(KeyboardShortcut.decreaseWidthDefault.displayString == "⌃⌥⇧⌘←")
        #expect(KeyboardShortcut.increaseHeightDefault.displayString == "⌃⌥⇧⌘↑")
        #expect(KeyboardShortcut.decreaseHeightDefault.displayString == "⌃⌥⇧⌘↓")
        #expect(KeyboardShortcut.moveToNextDisplayDefault != KeyboardShortcut.moveToPreviousDisplayDefault)
        #expect(KeyboardShortcut.undoHomeDefault != KeyboardShortcut.restoreHomeDefault)
        #expect(KeyboardShortcut.redoHomeDefault != KeyboardShortcut.undoHomeDefault)
        #expect(KeyboardShortcut.centerAndSaveHomeDefault != KeyboardShortcut.restoreAllDefault)
    }

    @Test func resizeShortcutRepeatUsesADeliberateCadence() {
        #expect(HotkeyService.resizeRepeatInitialDelay == 0.35)
        #expect(HotkeyService.resizeRepeatInterval == 0.12)
        #expect(HotkeyService.resizeRepeatInitialDelay > HotkeyService.resizeRepeatInterval)
    }

    @Test func standardSystemTileRectsIncludeSidesRowsAndCorners() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1200, height: 800)
        let layouts = DisplayService.standardSystemTileRects(in: visibleFrame)

        #expect(layouts.contains(CGRect(x: 100, y: 50, width: 600, height: 800)))
        #expect(layouts.contains(CGRect(x: 100, y: 450, width: 1200, height: 400)))
        #expect(layouts.contains(CGRect(x: 700, y: 50, width: 600, height: 400)))
    }

    @Test func legacyWindowProfileWithoutUndoOrRedoHistoryRemainsReadable() throws {
        let fingerprint = displayFingerprint(serialNumber: 1)
        let profile = windowProfile(
            displayFingerprint: fingerprint,
            geometry: storedGeometry(x: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 1)
        )
        let encoded = try JSONEncoder().encode(profile)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "history")
        object.removeValue(forKey: "future")

        let decoded = try JSONDecoder().decode(
            WindowProfile.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.geometry == profile.geometry)
        #expect(decoded.history.isEmpty)
        #expect(decoded.future.isEmpty)
    }

    @Test func homeHistoryIsIndependentForEachDisplayAndPersistsUndoAndRedo() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowHomeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("profiles.json")
        let store = try ProfileStore(fileURL: fileURL)
        let firstDisplay = displayFingerprint(serialNumber: 1)
        let secondDisplay = displayFingerprint(serialNumber: 2)
        let firstGeometry = storedGeometry(x: 100)
        let secondGeometry = storedGeometry(x: 200)
        let thirdGeometry = storedGeometry(x: 300)
        let otherDisplayFirstGeometry = storedGeometry(x: 500)
        let otherDisplaySecondGeometry = storedGeometry(x: 600)

        try store.upsert(windowProfile(displayFingerprint: firstDisplay, geometry: firstGeometry, updatedAt: Date(timeIntervalSinceReferenceDate: 1)))
        try store.upsert(windowProfile(displayFingerprint: secondDisplay, geometry: otherDisplayFirstGeometry, updatedAt: Date(timeIntervalSinceReferenceDate: 2)))
        try store.upsert(windowProfile(displayFingerprint: firstDisplay, geometry: secondGeometry, updatedAt: Date(timeIntervalSinceReferenceDate: 3)))
        try store.upsert(windowProfile(displayFingerprint: secondDisplay, geometry: otherDisplaySecondGeometry, updatedAt: Date(timeIntervalSinceReferenceDate: 4)))
        try store.upsert(windowProfile(displayFingerprint: firstDisplay, geometry: thirdGeometry, updatedAt: Date(timeIntervalSinceReferenceDate: 5)))

        #expect(store.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: firstDisplay)?.history.count == 2)
        #expect(store.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: secondDisplay)?.history.count == 1)

        let firstUndoResult = try store.undoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: firstDisplay)
        let firstUndo = try #require(firstUndoResult)
        #expect(firstUndo.geometry == secondGeometry)
        #expect(firstUndo.history.count == 1)
        #expect(firstUndo.future.map(\.geometry) == [thirdGeometry])
        #expect(store.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: secondDisplay)?.geometry == otherDisplaySecondGeometry)

        let reloadedStore = try ProfileStore(fileURL: fileURL)
        let secondUndoResult = try reloadedStore.undoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: firstDisplay)
        let secondUndo = try #require(secondUndoResult)
        #expect(secondUndo.geometry == firstGeometry)
        #expect(secondUndo.history.isEmpty)
        #expect(secondUndo.future.map(\.geometry) == [thirdGeometry, secondGeometry])
        let exhaustedHistory = try reloadedStore.undoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: firstDisplay)
        #expect(exhaustedHistory == nil)

        let firstRedoResult = try reloadedStore.redoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: firstDisplay)
        let firstRedo = try #require(firstRedoResult)
        #expect(firstRedo.geometry == secondGeometry)
        #expect(firstRedo.future.map(\.geometry) == [thirdGeometry])

        let reloadedAfterRedo = try ProfileStore(fileURL: fileURL)
        let secondRedoResult = try reloadedAfterRedo.redoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: firstDisplay)
        let secondRedo = try #require(secondRedoResult)
        #expect(secondRedo.geometry == thirdGeometry)
        #expect(secondRedo.future.isEmpty)
        let exhaustedFuture = try reloadedAfterRedo.redoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: firstDisplay)
        #expect(exhaustedFuture == nil)
        #expect(reloadedStore.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: secondDisplay)?.geometry == otherDisplaySecondGeometry)
        #expect(reloadedStore.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: secondDisplay)?.history.count == 1)
        #expect(reloadedStore.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: secondDisplay)?.future.isEmpty == true)
    }

    @Test func savingNewGeometryAfterUndoCreatesANewBranchAndClearsRedo() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowHomeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
        let fingerprint = displayFingerprint(serialNumber: 1)
        let geometries = (1...5).map { storedGeometry(x: CGFloat($0 * 100)) }

        for (index, geometry) in geometries.enumerated() {
            try store.upsert(windowProfile(
                displayFingerprint: fingerprint,
                geometry: geometry,
                updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index + 1))
            ))
        }

        _ = try store.undoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fingerprint)
        let thirdPositionResult = try store.undoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fingerprint)
        let thirdPosition = try #require(thirdPositionResult)
        #expect(thirdPosition.geometry == geometries[2])
        #expect(thirdPosition.future.map(\.geometry) == [geometries[4], geometries[3]])

        let fourthPositionResult = try store.redoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fingerprint)
        let fourthPosition = try #require(fourthPositionResult)
        #expect(fourthPosition.geometry == geometries[3])
        let fifthPositionResult = try store.redoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fingerprint)
        let fifthPosition = try #require(fifthPositionResult)
        #expect(fifthPosition.geometry == geometries[4])

        _ = try store.undoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fingerprint)
        _ = try store.undoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fingerprint)
        let newFourthPosition = storedGeometry(x: 350)
        try store.upsert(windowProfile(
            displayFingerprint: fingerprint,
            geometry: newFourthPosition,
            updatedAt: Date(timeIntervalSinceReferenceDate: 6)
        ))

        let branchedProfile = try #require(store.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fingerprint))
        #expect(branchedProfile.geometry == newFourthPosition)
        #expect(branchedProfile.history.map(\.geometry) == [geometries[0], geometries[1], geometries[2]])
        #expect(branchedProfile.future.isEmpty)
        let discardedRedo = try store.redoProfile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fingerprint)
        #expect(discardedRedo == nil)
    }

    @Test func homeHistorySkipsDuplicatesAndKeepsTheMostRecentTwentyPositions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowHomeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
        let fingerprint = displayFingerprint(serialNumber: 1)
        let initialGeometry = storedGeometry(x: 0)

        try store.upsert(windowProfile(displayFingerprint: fingerprint, geometry: initialGeometry, updatedAt: .distantPast))
        try store.upsert(windowProfile(displayFingerprint: fingerprint, geometry: initialGeometry, updatedAt: Date(timeIntervalSinceReferenceDate: 1)))
        #expect(store.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fingerprint)?.history.isEmpty == true)

        for index in 1...25 {
            try store.upsert(windowProfile(
                displayFingerprint: fingerprint,
                geometry: storedGeometry(x: CGFloat(index * 10)),
                updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index + 1))
            ))
        }

        let profile = try #require(store.profile(bundleIdentifier: "com.example.WindowHomeTests", displayFingerprint: fingerprint))
        #expect(profile.history.count == ProfileStore.maximumHistoryCount)
        #expect(profile.history.first?.geometry == storedGeometry(x: 50))
        #expect(profile.history.last?.geometry == storedGeometry(x: 240))
        #expect(profile.geometry == storedGeometry(x: 250))
    }

    @Test func snapLayoutUsesPaddingAndCyclesThroughExpectedFractions() {
        let converter = CoordinateConverter(desktopFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let leftHalf = SnapLayout.accessibilityGeometry(direction: .left, fraction: 0.5, padding: 20, visibleFrame: frame, converter: converter)
        let rightThird = SnapLayout.accessibilityGeometry(direction: .right, fraction: 1.0 / 3.0, padding: 20, visibleFrame: frame, converter: converter)
        let topTwoThirds = SnapLayout.accessibilityGeometry(direction: .top, fraction: 2.0 / 3.0, padding: 20, visibleFrame: frame, converter: converter)
        let topLeftThird = SnapLayout.accessibilityGeometry(direction: .topLeft, fraction: 1.0 / 3.0, padding: 20, visibleFrame: frame, converter: converter)
        let bottomRightTwoThirds = SnapLayout.accessibilityGeometry(direction: .bottomRight, fraction: 2.0 / 3.0, padding: 20, visibleFrame: frame, converter: converter)

        #expect(leftHalf.origin == CGPoint(x: 20, y: 20))
        #expect(leftHalf.size == CGSize(width: 470, height: 760))
        #expect(rightThird.origin.x == 666.6666666666667)
        #expect(rightThird.size.width == 313.3333333333333)
        #expect(topTwoThirds.origin.y == 20)
        #expect(topTwoThirds.size.height == 493.3333333333333)
        #expect(topLeftThird.origin == CGPoint(x: 20, y: 20))
        #expect(topLeftThird.size == CGSize(width: 313.3333333333333, height: 370))
        #expect(bottomRightTwoThirds.origin == CGPoint(x: 353.33333333333337, y: 410))
        #expect(bottomRightTwoThirds.size == CGSize(width: 626.6666666666666, height: 370))
    }

    @Test func appLimitedFullScreenWindowCanBeCenteredInUsableDisplayArea() {
        let result = SnapLayout.centeredAppKitRect(
            size: CGSize(width: 700, height: 400),
            padding: 20,
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )

        #expect(result == CGRect(x: 150, y: 200, width: 700, height: 400))
    }

    @Test func regularMouseSnapAreasAreCompactCenteredEdgeHitBoxes() {
        let frame = CGRect(x: 100, y: 50, width: 1200, height: 900)

        let zones = DisplayService.mouseSnapActivationZones(in: frame, optionPressed: false)

        #expect(zones == [
            MouseSnapActivationZone(direction: .left, frame: CGRect(x: 100, y: 350, width: 24, height: 300)),
            MouseSnapActivationZone(direction: .right, frame: CGRect(x: 1276, y: 350, width: 24, height: 300)),
            MouseSnapActivationZone(direction: .fullScreen, frame: CGRect(x: 500, y: 926, width: 400, height: 24))
        ])
    }

    @Test func optionMouseSnapAreasUseLargerVisibleEdgeTargets() {
        let frame = CGRect(x: 100, y: 50, width: 1200, height: 900)

        let zones = DisplayService.mouseSnapActivationZones(in: frame, optionPressed: true)

        #expect(zones == [
            MouseSnapActivationZone(direction: .left, frame: CGRect(x: 100, y: 350, width: 180, height: 300)),
            MouseSnapActivationZone(direction: .right, frame: CGRect(x: 1120, y: 350, width: 180, height: 300)),
            MouseSnapActivationZone(direction: .fullScreen, frame: CGRect(x: 500, y: 905, width: 400, height: 45))
        ])
    }

    @Test func mouseSnapHitTestingUsesOnlyTheDrawnAreas() {
        let frame = CGRect(x: 0, y: 0, width: 1200, height: 900)

        #expect(DisplayService.mouseSnapDirection(at: CGPoint(x: 0, y: 450), in: frame, optionPressed: false) == .left)
        #expect(DisplayService.mouseSnapDirection(at: CGPoint(x: 1200, y: 450), in: frame, optionPressed: false) == .right)
        #expect(DisplayService.mouseSnapDirection(at: CGPoint(x: 600, y: 900), in: frame, optionPressed: false) == .fullScreen)
        #expect(DisplayService.mouseSnapDirection(at: CGPoint(x: 0, y: 100), in: frame, optionPressed: false) == nil)
        #expect(DisplayService.mouseSnapDirection(at: CGPoint(x: 100, y: 900), in: frame, optionPressed: false) == nil)
    }

    private func displayFingerprint(serialNumber: UInt32) -> DisplayFingerprint {
        DisplayFingerprint(
            vendorNumber: 1,
            modelNumber: 2,
            serialNumber: serialNumber,
            isBuiltIn: false,
            logicalWidth: 1000,
            logicalHeight: 800,
            pixelWidth: 2000,
            pixelHeight: 1600
        )
    }

    private func builtInDisplayFingerprint(logicalWidth: Int = 1512, logicalHeight: Int) -> DisplayFingerprint {
        DisplayFingerprint(
            vendorNumber: 1552,
            modelNumber: 41038,
            serialNumber: 4251086178,
            isBuiltIn: true,
            logicalWidth: logicalWidth,
            logicalHeight: logicalHeight,
            pixelWidth: logicalWidth,
            pixelHeight: logicalHeight
        )
    }

    private func storedGeometry(x: CGFloat) -> StoredGeometry {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        return StoredGeometry(
            accessibilityGeometry: WindowGeometry(
                origin: CGPoint(x: x, y: 100),
                size: CGSize(width: 400, height: 300)
            ),
            visibleFrame: frame,
            converter: CoordinateConverter(desktopFrame: frame)
        )
    }

    private func windowProfile(
        displayFingerprint: DisplayFingerprint,
        geometry: StoredGeometry,
        updatedAt: Date
    ) -> WindowProfile {
        WindowProfile(
            id: UUID(),
            bundleIdentifier: "com.example.WindowHomeTests",
            applicationName: "WindowHome Tests",
            displayFingerprint: displayFingerprint,
            displayName: "Test Display",
            geometry: geometry,
            updatedAt: updatedAt
        )
    }

}
