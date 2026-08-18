import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var permissionGranted = AccessibilityPermissionService.isTrusted
    @Published private(set) var focusedWindowDescription = "No window read yet."
    @Published private(set) var statusMessage = "Ready to inspect the focused window."
    @Published private(set) var statusCopyFeedback = ""
    @Published private(set) var saveHomeShortcut: KeyboardShortcut? = KeyboardShortcut.saveHomeDefault
    @Published private(set) var restoreHomeShortcut: KeyboardShortcut? = KeyboardShortcut.restoreHomeDefault
    @Published private(set) var undoHomeShortcut: KeyboardShortcut? = KeyboardShortcut.undoHomeDefault
    @Published private(set) var redoHomeShortcut: KeyboardShortcut? = KeyboardShortcut.redoHomeDefault
    @Published private(set) var restoreAllShortcut: KeyboardShortcut? = KeyboardShortcut.restoreAllDefault
    @Published private(set) var centerAndSaveHomeShortcut: KeyboardShortcut? = KeyboardShortcut.centerAndSaveHomeDefault
    @Published private(set) var moveToNextDisplayShortcut: KeyboardShortcut? = KeyboardShortcut.moveToNextDisplayDefault
    @Published private(set) var moveToPreviousDisplayShortcut: KeyboardShortcut? = KeyboardShortcut.moveToPreviousDisplayDefault
    @Published private(set) var snapLeftShortcut: KeyboardShortcut? = KeyboardShortcut.snapLeftDefault
    @Published private(set) var snapRightShortcut: KeyboardShortcut? = KeyboardShortcut.snapRightDefault
    @Published private(set) var snapTopShortcut: KeyboardShortcut? = KeyboardShortcut.snapTopDefault
    @Published private(set) var snapBottomShortcut: KeyboardShortcut? = KeyboardShortcut.snapBottomDefault
    @Published private(set) var snapFullScreenShortcut: KeyboardShortcut? = KeyboardShortcut.snapFullScreenDefault
    @Published private(set) var snapTopLeftShortcut: KeyboardShortcut? = KeyboardShortcut.snapTopLeftDefault
    @Published private(set) var snapTopRightShortcut: KeyboardShortcut? = KeyboardShortcut.snapTopRightDefault
    @Published private(set) var snapBottomLeftShortcut: KeyboardShortcut? = KeyboardShortcut.snapBottomLeftDefault
    @Published private(set) var snapBottomRightShortcut: KeyboardShortcut? = KeyboardShortcut.snapBottomRightDefault
    @Published private(set) var increaseWidthShortcut: KeyboardShortcut? = KeyboardShortcut.increaseWidthDefault
    @Published private(set) var decreaseWidthShortcut: KeyboardShortcut? = KeyboardShortcut.decreaseWidthDefault
    @Published private(set) var increaseHeightShortcut: KeyboardShortcut? = KeyboardShortcut.increaseHeightDefault
    @Published private(set) var decreaseHeightShortcut: KeyboardShortcut? = KeyboardShortcut.decreaseHeightDefault
    @Published private(set) var snapPadding: Double = 12
    @Published private(set) var resizeStep: Double = 10
    @Published private(set) var restoreFullHomeAfterDisplayMoveEnabled = true
    @Published private(set) var automaticSaveAfterMouseMoveEnabled = false
    @Published private(set) var mouseSnapMode: MouseSnapMode = .off
    @Published private(set) var showMouseSnapAreas = true
    @Published private(set) var inputMonitoringPermissionGranted = InputMonitoringPermissionService.isGranted

    private let focusedWindowService = FocusedWindowService()
    private let displayService = DisplayService()
    private let profileStore: ProfileStore?
    private let hotkeyService: HotkeyService?
    private let mouseWindowTrackingService = MouseWindowTrackingService()
    private let mouseSnapPreviewService = MouseSnapPreviewService()
    private let applicationLaunchObserver = ApplicationLaunchObserver()
    private var lastSnapshot: FocusedWindowSnapshot?
    private var lastSnapDirection: SnapDirection?
    private var lastSnapProcessIdentifier: pid_t?
    private var lastSnapWindowIdentifier: CFHashCode?
    private var snapFractionIndex = 0
    private var activeSnapRequestID: UUID?
    private var activeLaunchRestoreRequestID: UUID?
    private var mouseGesture: MouseGesture?

    var mouseSnapEnabled: Bool { mouseSnapMode != .off }

    private struct MouseGesture {
        let snapshot: FocusedWindowSnapshot
        let sourceDisplay: DisplayContext
        let wasSnapped: Bool
        var didDrag: Bool
        var candidate: (direction: SnapDirection, display: DisplayContext)?
        var didTearOffFromSnap: Bool
    }

    init() {
        saveHomeShortcut = KeyboardShortcutPreferences.loadSaveHome()
        restoreHomeShortcut = KeyboardShortcutPreferences.loadRestoreHome()
        undoHomeShortcut = KeyboardShortcutPreferences.loadUndoHome()
        redoHomeShortcut = KeyboardShortcutPreferences.loadRedoHome()
        restoreAllShortcut = KeyboardShortcutPreferences.loadRestoreAll()
        centerAndSaveHomeShortcut = KeyboardShortcutPreferences.loadCenterAndSaveHome()
        moveToNextDisplayShortcut = KeyboardShortcutPreferences.loadMoveToNextDisplay()
        moveToPreviousDisplayShortcut = KeyboardShortcutPreferences.loadMoveToPreviousDisplay()
        snapLeftShortcut = KeyboardShortcutPreferences.loadSnapLeft()
        snapRightShortcut = KeyboardShortcutPreferences.loadSnapRight()
        snapTopShortcut = KeyboardShortcutPreferences.loadSnapTop()
        snapBottomShortcut = KeyboardShortcutPreferences.loadSnapBottom()
        snapFullScreenShortcut = KeyboardShortcutPreferences.loadSnapFullScreen()
        snapTopLeftShortcut = KeyboardShortcutPreferences.loadSnapTopLeft()
        snapTopRightShortcut = KeyboardShortcutPreferences.loadSnapTopRight()
        snapBottomLeftShortcut = KeyboardShortcutPreferences.loadSnapBottomLeft()
        snapBottomRightShortcut = KeyboardShortcutPreferences.loadSnapBottomRight()
        increaseWidthShortcut = KeyboardShortcutPreferences.loadIncreaseWidth()
        decreaseWidthShortcut = KeyboardShortcutPreferences.loadDecreaseWidth()
        increaseHeightShortcut = KeyboardShortcutPreferences.loadIncreaseHeight()
        decreaseHeightShortcut = KeyboardShortcutPreferences.loadDecreaseHeight()
        snapPadding = KeyboardShortcutPreferences.snapPadding
        resizeStep = KeyboardShortcutPreferences.resizeStep
        restoreFullHomeAfterDisplayMoveEnabled = KeyboardShortcutPreferences.restoreFullHomeAfterDisplayMoveEnabled
        automaticSaveAfterMouseMoveEnabled = KeyboardShortcutPreferences.automaticSaveAfterMouseMoveEnabled
        mouseSnapMode = KeyboardShortcutPreferences.mouseSnapMode
        showMouseSnapAreas = KeyboardShortcutPreferences.showMouseSnapAreas
        do {
            profileStore = try ProfileStore()
        } catch {
            profileStore = nil
            statusMessage = error.localizedDescription
        }
        do {
            hotkeyService = try HotkeyService()
            configureHotkeys()
        } catch {
            hotkeyService = nil
            statusMessage = error.localizedDescription
        }
        configureMouseWindowTracking()
        applicationLaunchObserver.start { [weak self] application in
            Task { @MainActor [weak self] in self?.restoreLaunchedApplication(application) }
        }
    }

    func requestAccessibilityPermission() {
        AccessibilityPermissionService.requestPermission()
        refreshPermissionStatus()
        statusMessage = "System Settings was asked to show Accessibility permission. Enable WindowHome there, then press Refresh."
    }

    func refreshPermissionStatus() {
        permissionGranted = AccessibilityPermissionService.isTrusted
        if permissionGranted { statusMessage = "Accessibility permission is enabled." }
    }

    func inspectFocusedWindow() {
        perform("read the focused window") { snapshot in
            focusedWindowDescription = "\(snapshot.applicationName)\(snapshot.bundleIdentifier.map { " (\($0))" } ?? "")\n\(snapshot.geometry.description)"
            statusMessage = "Read focused window geometry."
        }
    }

    func applyTestInset() {
        perform("apply the test inset") { snapshot in
            cancelLaunchRestoreStabilization()
            let insetGeometry = PrototypeWindowTransform.inset(from: snapshot.geometry)
            try focusedWindowService.setGeometry(insetGeometry, for: snapshot.window)
            focusedWindowDescription = "\(snapshot.applicationName)\n\(insetGeometry.description)"
            statusMessage = "Applied a 24-point inset. Use Restore Last Read to undo it."
        }
    }

    func restoreLastRead() {
        guard let lastSnapshot else {
            statusMessage = "Read a focused window before using Restore Last Read."
            return
        }
        do {
            cancelLaunchRestoreStabilization()
            try focusedWindowService.setGeometry(lastSnapshot.geometry, for: lastSnapshot.window)
            resetSnapCycle()
            statusMessage = "Restored the geometry captured during the last read."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveHome() {
        perform("save the home position") { snapshot in
            guard let bundleIdentifier = snapshot.bundleIdentifier else {
                statusMessage = "This application has no bundle identifier, so it cannot have a saved Home position."
                return
            }
            guard let profileStore else {
                statusMessage = "The profile store is unavailable. Restart WindowHome and try again."
                return
            }

            let display = try displayService.context(forAccessibilityGeometry: snapshot.geometry)
            let profile = WindowProfile(
                id: UUID(),
                bundleIdentifier: bundleIdentifier,
                applicationName: snapshot.applicationName,
                displayFingerprint: display.fingerprint,
                displayName: display.name,
                geometry: StoredGeometry(accessibilityGeometry: snapshot.geometry, visibleFrame: display.visibleFrame, converter: displayService.coordinateConverter()),
                updatedAt: Date()
            )
            try profileStore.upsert(profile)
            statusMessage = "Saved Home for \(snapshot.applicationName) on \(display.name)."
        }
    }

    func restoreHome() {
        perform("restore the home position") { snapshot in
            cancelLaunchRestoreStabilization()
            guard let bundleIdentifier = snapshot.bundleIdentifier else {
                statusMessage = "This application has no bundle identifier, so it has no saved Home position."
                return
            }
            guard let profileStore else {
                statusMessage = "The profile store is unavailable. Restart WindowHome and try again."
                return
            }

            let display = try displayService.context(forAccessibilityGeometry: snapshot.geometry)
            guard let profile = profileStore.profile(bundleIdentifier: bundleIdentifier, displayFingerprint: display.fingerprint) else {
                statusMessage = "No Home position is saved for \(snapshot.applicationName) on \(display.name)."
                return
            }
            let geometry = displayService.constrainedAccessibilityGeometry(
                profile.geometry.accessibilityGeometry(for: display.visibleFrame, converter: displayService.coordinateConverter()),
                on: display,
                padding: CGFloat(snapPadding)
            )
            try focusedWindowService.setGeometry(geometry, for: snapshot.window)
            resetSnapCycle()
            focusedWindowDescription = "\(snapshot.applicationName) on \(display.name)\n\(geometry.description)"
            statusMessage = "Restored Home for \(snapshot.applicationName) on \(display.name)."
        }
    }

    func undoHome() {
        perform("undo the last Home change") { snapshot in
            cancelLaunchRestoreStabilization()
            guard let bundleIdentifier = snapshot.bundleIdentifier else {
                statusMessage = "This application has no bundle identifier, so it has no Home history."
                return
            }
            guard let profileStore else {
                statusMessage = "The profile store is unavailable. Restart WindowHome and try again."
                return
            }

            let display = try displayService.context(forAccessibilityGeometry: snapshot.geometry)
            guard let profile = try profileStore.undoProfile(
                bundleIdentifier: bundleIdentifier,
                displayFingerprint: display.fingerprint
            ) else {
                statusMessage = "No earlier Home position is saved for \(snapshot.applicationName) on \(display.name)."
                return
            }
            let geometry = displayService.constrainedAccessibilityGeometry(
                profile.geometry.accessibilityGeometry(
                    for: display.visibleFrame,
                    converter: displayService.coordinateConverter()
                ),
                on: display,
                padding: CGFloat(snapPadding)
            )
            try focusedWindowService.setGeometry(geometry, for: snapshot.window)
            resetSnapCycle()
            focusedWindowDescription = "\(snapshot.applicationName) on \(display.name)\n\(geometry.description)"
            statusMessage = "Restored the previous Home for \(snapshot.applicationName) on \(display.name)."
        }
    }

    func redoHome() {
        perform("redo the last undone Home change") { snapshot in
            cancelLaunchRestoreStabilization()
            guard let bundleIdentifier = snapshot.bundleIdentifier else {
                statusMessage = "This application has no bundle identifier, so it has no Home history."
                return
            }
            guard let profileStore else {
                statusMessage = "The profile store is unavailable. Restart WindowHome and try again."
                return
            }

            let display = try displayService.context(forAccessibilityGeometry: snapshot.geometry)
            guard let profile = try profileStore.redoProfile(
                bundleIdentifier: bundleIdentifier,
                displayFingerprint: display.fingerprint
            ) else {
                statusMessage = "No newer Home position is available for \(snapshot.applicationName) on \(display.name)."
                return
            }
            let geometry = displayService.constrainedAccessibilityGeometry(
                profile.geometry.accessibilityGeometry(
                    for: display.visibleFrame,
                    converter: displayService.coordinateConverter()
                ),
                on: display,
                padding: CGFloat(snapPadding)
            )
            try focusedWindowService.setGeometry(geometry, for: snapshot.window)
            resetSnapCycle()
            focusedWindowDescription = "\(snapshot.applicationName) on \(display.name)\n\(geometry.description)"
            statusMessage = "Restored the next Home for \(snapshot.applicationName) on \(display.name)."
        }
    }

    func restoreAllHomePositions() {
        restoreAllOpenApplications()
    }

    func centerFocusedWindowAndSaveHome() {
        perform("center and save the home position") { snapshot in
            cancelLaunchRestoreStabilization()
            guard let bundleIdentifier = snapshot.bundleIdentifier else {
                statusMessage = "This application has no bundle identifier, so it cannot have a saved Home position."
                return
            }
            guard let profileStore else {
                statusMessage = "The profile store is unavailable. Restart WindowHome and try again."
                return
            }

            let display = try displayService.context(forAccessibilityGeometry: snapshot.geometry)
            let isSnapped = isSnapGeometry(snapshot.geometry, on: display)
                || focusedWindowService.isFullScreen(snapshot.window)
                || displayService.isLikelySystemTiled(accessibilityGeometry: snapshot.geometry)
            let sourceGeometry: WindowGeometry
            if isSnapped,
               let profile = profileStore.profile(bundleIdentifier: bundleIdentifier, displayFingerprint: display.fingerprint) {
                sourceGeometry = profile.geometry.accessibilityGeometry(
                    for: display.visibleFrame,
                    converter: displayService.coordinateConverter()
                )
            } else {
                sourceGeometry = snapshot.geometry
            }

            let centeredGeometry = displayService.centeredAccessibilityGeometry(
                size: sourceGeometry.size,
                on: display,
                padding: CGFloat(snapPadding)
            )
            try focusedWindowService.setGeometry(centeredGeometry, for: snapshot.window)
            let profile = WindowProfile(
                id: UUID(),
                bundleIdentifier: bundleIdentifier,
                applicationName: snapshot.applicationName,
                displayFingerprint: display.fingerprint,
                displayName: display.name,
                geometry: StoredGeometry(
                    accessibilityGeometry: centeredGeometry,
                    visibleFrame: display.visibleFrame,
                    converter: displayService.coordinateConverter()
                ),
                updatedAt: Date()
            )
            try profileStore.upsert(profile)
            resetSnapCycle()
            focusedWindowDescription = "\(snapshot.applicationName) on \(display.name)\n\(centeredGeometry.description)"
            statusMessage = "Centered \(snapshot.applicationName) and saved this position as Home on \(display.name)."
        }
    }

    func moveFocusedWindowToNextDisplay() {
        moveFocusedWindow(to: .next)
    }

    func moveFocusedWindowToPreviousDisplay() {
        moveFocusedWindow(to: .previous)
    }

    func resizeFocusedWindow(_ action: WindowResizeAction) {
        if let window = NSApp.keyWindow, NSApp.isActive, window.styleMask.contains(.titled) {
            resizeSettingsWindow(window, action: action)
            return
        }
        perform("resize the focused window") { snapshot in
            let display = try displayService.context(forAccessibilityGeometry: snapshot.geometry)
            guard !isWindowSnapped(snapshot, on: display) else {
                statusMessage = "Resize ignored because \(snapshot.applicationName) is snapped."
                return
            }

            cancelLaunchRestoreStabilization()
            resetSnapCycle()
            let targetGeometry = SymmetricWindowResize.geometry(
                from: snapshot.geometry,
                action: action,
                step: CGFloat(resizeStep)
            )
            let appliedGeometry = try focusedWindowService.resizeAroundCenter(
                targetGeometry,
                from: snapshot.geometry,
                for: snapshot.window,
                processIdentifier: snapshot.processIdentifier
            )
            focusedWindowDescription = "\(snapshot.applicationName) on \(display.name)\n\(appliedGeometry.description)"
            do {
                if try saveHome(snapshot: snapshot, geometry: appliedGeometry, on: display) {
                    statusMessage = "Resized \(snapshot.applicationName) and saved the result as its new Home."
                } else {
                    statusMessage = "Resized \(snapshot.applicationName), but this application cannot have a saved Home."
                }
            } catch {
                statusMessage = "Resized \(snapshot.applicationName), but could not save its new Home: \(error.localizedDescription)"
            }
        }
    }

    func snapFocusedWindow(to direction: SnapDirection) {
        if let window = NSApp.keyWindow, NSApp.isActive, window.styleMask.contains(.titled) {
            snapSettingsWindow(window, to: direction)
            return
        }
        perform("snap the focused window") { snapshot in
            let display = try displayService.context(forAccessibilityGeometry: snapshot.geometry)
            saveHomeBeforeFirstSnapIfNeeded(snapshot: snapshot, on: display)
            let fraction = nextSnapFraction(
                direction: direction,
                processIdentifier: snapshot.processIdentifier,
                windowIdentifier: snapshot.windowIdentifier,
                currentGeometry: snapshot.geometry,
                on: display
            )
            let geometry = SnapLayout.accessibilityGeometry(
                direction: direction,
                fraction: fraction,
                padding: CGFloat(snapPadding),
                visibleFrame: display.visibleFrame,
                converter: displayService.coordinateConverter()
            )
            try applySnapGeometry(geometry, direction: direction, on: display, to: snapshot)
            focusedWindowDescription = "\(snapshot.applicationName) on \(display.name)\n\(geometry.description)"
            statusMessage = "Snapped \(snapshot.applicationName) to \(snapLabel(for: direction)) at \(Int((fraction * 100).rounded()))%."
        }
    }

    private func saveHomeBeforeFirstSnapIfNeeded(snapshot: FocusedWindowSnapshot, on display: DisplayContext) {
        guard let bundleIdentifier = snapshot.bundleIdentifier,
              let profileStore,
              profileStore.profile(bundleIdentifier: bundleIdentifier, displayFingerprint: display.fingerprint) == nil else {
            return
        }
        let profile = WindowProfile(
            id: UUID(),
            bundleIdentifier: bundleIdentifier,
            applicationName: snapshot.applicationName,
            displayFingerprint: display.fingerprint,
            displayName: display.name,
            geometry: StoredGeometry(accessibilityGeometry: snapshot.geometry, visibleFrame: display.visibleFrame, converter: displayService.coordinateConverter()),
            updatedAt: Date()
        )
        try? profileStore.upsert(profile)
    }

    private func snapSettingsWindow(_ window: NSWindow, to direction: SnapDirection) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let fraction = nextSnapFraction(
            direction: direction,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            windowIdentifier: CFHashCode(window.windowNumber),
            currentGeometry: displayService.coordinateConverter().accessibilityGeometry(fromAppKit: window.frame),
            on: DisplayContext(
                fingerprint: DisplayFingerprint(vendorNumber: 0, modelNumber: 0, serialNumber: 0, isBuiltIn: false),
                name: screen.localizedName,
                visibleFrame: screen.visibleFrame
            )
        )
        let frame = SnapLayout.appKitRect(direction: direction, fraction: fraction, padding: CGFloat(snapPadding), visibleFrame: screen.visibleFrame)
        window.setFrame(frame, display: true, animate: false)
        focusedWindowDescription = "WindowHome Settings on \(screen.localizedName)\nx: \(frame.minX.rounded()), y: \(frame.minY.rounded()), width: \(frame.width.rounded()), height: \(frame.height.rounded())"
        statusMessage = "Snapped WindowHome Settings to \(snapLabel(for: direction)) at \(Int((fraction * 100).rounded()))%."
    }

    private func resizeSettingsWindow(_ window: NSWindow, action: WindowResizeAction) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let converter = displayService.coordinateConverter()
        let geometry = converter.accessibilityGeometry(fromAppKit: window.frame)
        let display = DisplayContext(
            fingerprint: DisplayFingerprint(vendorNumber: 0, modelNumber: 0, serialNumber: 0, isBuiltIn: false),
            name: screen.localizedName,
            visibleFrame: screen.visibleFrame
        )
        guard !window.styleMask.contains(.fullScreen),
              !window.isZoomed,
              !isSnapGeometry(geometry, on: display),
              !displayService.isLikelySystemTiled(accessibilityGeometry: geometry) else {
            statusMessage = "Resize ignored because WindowHome Settings is snapped."
            return
        }

        let targetGeometry = SymmetricWindowResize.geometry(
            from: geometry,
            action: action,
            step: CGFloat(resizeStep)
        )
        let targetFrame = converter.appKitRect(fromAccessibility: targetGeometry)
        let sourceFrame = window.frame
        window.setFrame(targetFrame, display: true, animate: false)
        let acceptedSize = window.frame.size
        window.setFrameOrigin(CGPoint(
            x: sourceFrame.midX - acceptedSize.width / 2,
            y: sourceFrame.midY - acceptedSize.height / 2
        ))
        let appliedGeometry = converter.accessibilityGeometry(fromAppKit: window.frame)
        focusedWindowDescription = "WindowHome Settings on \(screen.localizedName)\n\(appliedGeometry.description)"
        statusMessage = "Resized WindowHome Settings symmetrically from its center."
    }

    private func nextSnapFraction(direction: SnapDirection, processIdentifier: pid_t, windowIdentifier: CFHashCode, currentGeometry: WindowGeometry, on display: DisplayContext) -> CGFloat {
        if direction == .fullScreen {
            resetSnapCycle()
        } else if lastSnapProcessIdentifier == processIdentifier, lastSnapWindowIdentifier == windowIdentifier, lastSnapDirection == direction {
            snapFractionIndex = (snapFractionIndex + 1) % SnapLayout.fractions.count
        } else {
            lastSnapDirection = direction
            lastSnapProcessIdentifier = processIdentifier
            lastSnapWindowIdentifier = windowIdentifier
            if let currentFractionIndex = snapFractionIndex(for: currentGeometry, direction: direction, on: display) {
                snapFractionIndex = (currentFractionIndex + 1) % SnapLayout.fractions.count
            } else {
                snapFractionIndex = 0
            }
        }
        return SnapLayout.fractions[snapFractionIndex]
    }

    func setSnapPadding(_ padding: Double) {
        snapPadding = min(max(0, padding), 80)
        KeyboardShortcutPreferences.saveSnapPadding(snapPadding)
    }

    func setResizeStep(_ step: Double) {
        resizeStep = min(max(1, step), 500)
        KeyboardShortcutPreferences.saveResizeStep(resizeStep)
    }

    private func restoreAllOpenApplications() {
        guard let profileStore else { return }
        cancelLaunchRestoreStabilization()
        resetSnapCycle()
        var restoredCount = 0
        for application in NSWorkspace.shared.runningApplications where application.activationPolicy == .regular && !application.isTerminated {
            guard let snapshot = focusedWindowService.mainWindowSnapshot(for: application) else { continue }
            do {
                let display = try displayService.context(forAccessibilityGeometry: snapshot.geometry)
                guard let bundleIdentifier = snapshot.bundleIdentifier,
                      let profile = profileStore.profile(bundleIdentifier: bundleIdentifier, displayFingerprint: display.fingerprint) else {
                    continue
                }
                let geometry = displayService.constrainedAccessibilityGeometry(
                    profile.geometry.accessibilityGeometry(for: display.visibleFrame, converter: displayService.coordinateConverter()),
                    on: display,
                    padding: CGFloat(snapPadding)
                )
                try focusedWindowService.setGeometry(geometry, for: snapshot.window)
                restoredCount += 1
            } catch {
                continue
            }
        }
        statusMessage = restoredCount == 1 ? "Restored 1 window to Home." : "Restored \(restoredCount) windows to Home."
    }

    private func restoreLaunchedApplication(_ application: NSRunningApplication) {
        guard application.activationPolicy == .regular,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let requestID = UUID()
        activeLaunchRestoreRequestID = requestID
        retryRestoreLaunchedApplication(application, requestID: requestID, attempt: 0)
    }

    private func retryRestoreLaunchedApplication(_ application: NSRunningApplication, requestID: UUID, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !application.isTerminated else { return }
            guard self.activeLaunchRestoreRequestID == requestID else { return }
            guard let snapshot = self.focusedWindowService.mainWindowSnapshot(for: application) else {
                if attempt < 23 {
                    self.retryRestoreLaunchedApplication(application, requestID: requestID, attempt: attempt + 1)
                }
                return
            }
            do {
                let display = try self.displayService.context(forAccessibilityGeometry: snapshot.geometry)
                let geometry: WindowGeometry
                let statusMessage: String?
                if let bundleIdentifier = snapshot.bundleIdentifier,
                   let profile = self.profileStore?.profile(bundleIdentifier: bundleIdentifier, displayFingerprint: display.fingerprint) {
                    geometry = self.displayService.constrainedAccessibilityGeometry(
                        profile.geometry.accessibilityGeometry(for: display.visibleFrame, converter: self.displayService.coordinateConverter()),
                        on: display,
                        padding: CGFloat(self.snapPadding)
                    )
                    statusMessage = "Restored Home for newly launched \(snapshot.applicationName)."
                } else {
                    geometry = self.displayService.constrainedAccessibilityGeometry(
                        snapshot.geometry,
                        on: display,
                        padding: CGFloat(self.snapPadding)
                    )
                    statusMessage = self.matches(snapshot.geometry, geometry, tolerance: 2)
                        ? nil
                        : "Adjusted newly launched \(snapshot.applicationName) to fit within screen padding."
                }
                try self.focusedWindowService.setGeometry(geometry, for: snapshot.window)
                self.keepLaunchRestoreStable(
                    geometry,
                    for: snapshot,
                    targetDisplayFingerprint: display.fingerprint,
                    requestID: requestID,
                    attempt: 0
                )
                if let statusMessage {
                    self.statusMessage = statusMessage
                }
            } catch {
                if attempt < 23 {
                    self.retryRestoreLaunchedApplication(application, requestID: requestID, attempt: attempt + 1)
                }
            }
        }
    }

    private func keepLaunchRestoreStable(
        _ geometry: WindowGeometry,
        for snapshot: FocusedWindowSnapshot,
        targetDisplayFingerprint: DisplayFingerprint,
        requestID: UUID?,
        attempt: Int
    ) {
        let delays: [TimeInterval] = [0.10, 0.18, 0.28, 0.40, 0.55, 0.72]
        guard let requestID, attempt < delays.count else {
            if activeLaunchRestoreRequestID == requestID {
                activeLaunchRestoreRequestID = nil
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
            guard let self, self.activeLaunchRestoreRequestID == requestID else { return }
            guard let actual = try? self.focusedWindowService.readGeometry(of: snapshot.window, fallbackProcessIdentifier: snapshot.processIdentifier) else {
                if self.activeLaunchRestoreRequestID == requestID {
                    self.activeLaunchRestoreRequestID = nil
                }
                return
            }
            guard let currentDisplay = try? self.displayService.context(forAccessibilityGeometry: actual),
                  currentDisplay.fingerprint == targetDisplayFingerprint else {
                if self.activeLaunchRestoreRequestID == requestID {
                    self.activeLaunchRestoreRequestID = nil
                }
                return
            }
            do {
                if !self.matches(actual, geometry, tolerance: 4) {
                    try self.focusedWindowService.setGeometry(geometry, for: snapshot.window)
                }
                self.keepLaunchRestoreStable(
                    geometry,
                    for: snapshot,
                    targetDisplayFingerprint: targetDisplayFingerprint,
                    requestID: requestID,
                    attempt: attempt + 1
                )
            } catch {
                if self.activeLaunchRestoreRequestID == requestID {
                    self.activeLaunchRestoreRequestID = nil
                }
            }
        }
    }

    func copyStatus() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(statusMessage, forType: .string)
        statusCopyFeedback = "Copied"
    }

    func setRestoreFullHomeAfterDisplayMoveEnabled(_ enabled: Bool) {
        restoreFullHomeAfterDisplayMoveEnabled = enabled
        KeyboardShortcutPreferences.saveRestoreFullHomeAfterDisplayMoveEnabled(enabled)
        statusMessage = enabled
            ? "WindowHome will apply the full saved Home after moving a window to another display."
            : "WindowHome will preserve the current window size when moving it to another display."
    }

    func setAutomaticSaveAfterMouseMoveEnabled(_ enabled: Bool) {
        automaticSaveAfterMouseMoveEnabled = enabled
        KeyboardShortcutPreferences.saveAutomaticSaveAfterMouseMoveEnabled(enabled)
        configureMouseWindowTracking()
    }

    func setMouseSnapMode(_ mode: MouseSnapMode) {
        mouseSnapMode = mode
        KeyboardShortcutPreferences.saveMouseSnapMode(mode)
        configureMouseWindowTracking()
    }

    func setShowMouseSnapAreas(_ enabled: Bool) {
        showMouseSnapAreas = enabled
        KeyboardShortcutPreferences.saveShowMouseSnapAreas(enabled)
        if !enabled { mouseSnapPreviewService.hideActivationZones() }
    }

    func requestInputMonitoringPermission() {
        InputMonitoringPermissionService.requestPermission()
        refreshInputMonitoringPermissionStatus()
        statusMessage = "System Settings was asked to show Input Monitoring permission. Enable WindowHome there, then press Refresh."
    }

    func refreshInputMonitoringPermissionStatus() {
        inputMonitoringPermissionGranted = InputMonitoringPermissionService.isGranted
        configureMouseWindowTracking()
    }

    func updateSaveHomeShortcut(_ shortcut: KeyboardShortcut) {
        guard isAvailableGlobalShortcut(shortcut, excluding: .saveHome) else {
            statusMessage = "Every WindowHome shortcut must be different."
            return
        }
        let previousShortcut = saveHomeShortcut
        saveHomeShortcut = shortcut
        if configureHotkeys() {
            KeyboardShortcutPreferences.save(shortcut, forSaveHome: true)
        } else {
            saveHomeShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func clearSaveHomeShortcut() {
        let previousShortcut = saveHomeShortcut
        saveHomeShortcut = nil
        if configureHotkeys() {
            KeyboardShortcutPreferences.save(nil, forSaveHome: true)
        } else {
            saveHomeShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func updateRestoreHomeShortcut(_ shortcut: KeyboardShortcut) {
        guard isAvailableGlobalShortcut(shortcut, excluding: .restoreHome) else {
            statusMessage = "Every WindowHome shortcut must be different."
            return
        }
        let previousShortcut = restoreHomeShortcut
        restoreHomeShortcut = shortcut
        if configureHotkeys() {
            KeyboardShortcutPreferences.save(shortcut, forSaveHome: false)
        } else {
            restoreHomeShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func clearRestoreHomeShortcut() {
        let previousShortcut = restoreHomeShortcut
        restoreHomeShortcut = nil
        if configureHotkeys() {
            KeyboardShortcutPreferences.save(nil, forSaveHome: false)
        } else {
            restoreHomeShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func updateUndoHomeShortcut(_ shortcut: KeyboardShortcut) {
        guard isAvailableGlobalShortcut(shortcut, excluding: .undoHome) else {
            statusMessage = "Every WindowHome shortcut must be different."
            return
        }
        let previousShortcut = undoHomeShortcut
        undoHomeShortcut = shortcut
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveUndoHome(shortcut)
        } else {
            undoHomeShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func clearUndoHomeShortcut() {
        let previousShortcut = undoHomeShortcut
        undoHomeShortcut = nil
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveUndoHome(nil)
        } else {
            undoHomeShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func updateRedoHomeShortcut(_ shortcut: KeyboardShortcut) {
        guard isAvailableGlobalShortcut(shortcut, excluding: .redoHome) else {
            statusMessage = "Every WindowHome shortcut must be different."
            return
        }
        let previousShortcut = redoHomeShortcut
        redoHomeShortcut = shortcut
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveRedoHome(shortcut)
        } else {
            redoHomeShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func clearRedoHomeShortcut() {
        let previousShortcut = redoHomeShortcut
        redoHomeShortcut = nil
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveRedoHome(nil)
        } else {
            redoHomeShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func updateRestoreAllShortcut(_ shortcut: KeyboardShortcut) {
        guard isAvailableGlobalShortcut(shortcut, excluding: .restoreAll) else {
            statusMessage = "Every WindowHome shortcut must be different."
            return
        }
        let previousShortcut = restoreAllShortcut
        restoreAllShortcut = shortcut
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveRestoreAll(shortcut)
        } else {
            restoreAllShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func clearRestoreAllShortcut() {
        let previousShortcut = restoreAllShortcut
        restoreAllShortcut = nil
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveRestoreAll(nil)
        } else {
            restoreAllShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func updateCenterAndSaveHomeShortcut(_ shortcut: KeyboardShortcut) {
        guard isAvailableGlobalShortcut(shortcut, excluding: .centerAndSaveHome) else {
            statusMessage = "Every WindowHome shortcut must be different."
            return
        }
        let previousShortcut = centerAndSaveHomeShortcut
        centerAndSaveHomeShortcut = shortcut
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveCenterAndSaveHome(shortcut)
        } else {
            centerAndSaveHomeShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func clearCenterAndSaveHomeShortcut() {
        let previousShortcut = centerAndSaveHomeShortcut
        centerAndSaveHomeShortcut = nil
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveCenterAndSaveHome(nil)
        } else {
            centerAndSaveHomeShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func updateMoveToNextDisplayShortcut(_ shortcut: KeyboardShortcut) {
        guard isAvailableGlobalShortcut(shortcut, excluding: .moveToNextDisplay) else {
            statusMessage = "Every WindowHome shortcut must be different."
            return
        }
        let previousShortcut = moveToNextDisplayShortcut
        moveToNextDisplayShortcut = shortcut
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveMoveToNextDisplay(shortcut)
        } else {
            moveToNextDisplayShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func clearMoveToNextDisplayShortcut() {
        let previousShortcut = moveToNextDisplayShortcut
        moveToNextDisplayShortcut = nil
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveMoveToNextDisplay(nil)
        } else {
            moveToNextDisplayShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func updateMoveToPreviousDisplayShortcut(_ shortcut: KeyboardShortcut) {
        guard isAvailableGlobalShortcut(shortcut, excluding: .moveToPreviousDisplay) else {
            statusMessage = "Every WindowHome shortcut must be different."
            return
        }
        let previousShortcut = moveToPreviousDisplayShortcut
        moveToPreviousDisplayShortcut = shortcut
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveMoveToPreviousDisplay(shortcut)
        } else {
            moveToPreviousDisplayShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func clearMoveToPreviousDisplayShortcut() {
        let previousShortcut = moveToPreviousDisplayShortcut
        moveToPreviousDisplayShortcut = nil
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveMoveToPreviousDisplay(nil)
        } else {
            moveToPreviousDisplayShortcut = previousShortcut
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func updateSnapLeftShortcut(_ shortcut: KeyboardShortcut) { updateSnapShortcut(shortcut, direction: .left, kind: .snapLeft) }
    func updateSnapRightShortcut(_ shortcut: KeyboardShortcut) { updateSnapShortcut(shortcut, direction: .right, kind: .snapRight) }
    func updateSnapTopShortcut(_ shortcut: KeyboardShortcut) { updateSnapShortcut(shortcut, direction: .top, kind: .snapTop) }
    func updateSnapBottomShortcut(_ shortcut: KeyboardShortcut) { updateSnapShortcut(shortcut, direction: .bottom, kind: .snapBottom) }
    func updateSnapFullScreenShortcut(_ shortcut: KeyboardShortcut) { updateSnapShortcut(shortcut, direction: .fullScreen, kind: .snapFullScreen) }
    func updateSnapTopLeftShortcut(_ shortcut: KeyboardShortcut) { updateSnapShortcut(shortcut, direction: .topLeft, kind: .snapTopLeft) }
    func updateSnapTopRightShortcut(_ shortcut: KeyboardShortcut) { updateSnapShortcut(shortcut, direction: .topRight, kind: .snapTopRight) }
    func updateSnapBottomLeftShortcut(_ shortcut: KeyboardShortcut) { updateSnapShortcut(shortcut, direction: .bottomLeft, kind: .snapBottomLeft) }
    func updateSnapBottomRightShortcut(_ shortcut: KeyboardShortcut) { updateSnapShortcut(shortcut, direction: .bottomRight, kind: .snapBottomRight) }

    func clearSnapShortcut(_ direction: SnapDirection) {
        let previousShortcut = snapShortcut(for: direction)
        setSnapShortcut(nil, for: direction)
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveSnapShortcut(nil, direction: direction)
        } else {
            setSnapShortcut(previousShortcut, for: direction)
            _ = configureHotkeys(reportFailure: false)
        }
    }

    private func updateSnapShortcut(_ shortcut: KeyboardShortcut, direction: SnapDirection, kind: GlobalShortcutKind) {
        guard isAvailableGlobalShortcut(shortcut, excluding: kind) else {
            statusMessage = "Every WindowHome shortcut must be different."
            return
        }
        let previousShortcut = snapShortcut(for: direction)
        setSnapShortcut(shortcut, for: direction)
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveSnapShortcut(shortcut, direction: direction)
        } else {
            setSnapShortcut(previousShortcut, for: direction)
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func updateIncreaseWidthShortcut(_ shortcut: KeyboardShortcut) { updateResizeShortcut(shortcut, action: .increaseWidth, kind: .increaseWidth) }
    func updateDecreaseWidthShortcut(_ shortcut: KeyboardShortcut) { updateResizeShortcut(shortcut, action: .decreaseWidth, kind: .decreaseWidth) }
    func updateIncreaseHeightShortcut(_ shortcut: KeyboardShortcut) { updateResizeShortcut(shortcut, action: .increaseHeight, kind: .increaseHeight) }
    func updateDecreaseHeightShortcut(_ shortcut: KeyboardShortcut) { updateResizeShortcut(shortcut, action: .decreaseHeight, kind: .decreaseHeight) }

    func clearResizeShortcut(_ action: WindowResizeAction) {
        let previousShortcut = resizeShortcut(for: action)
        setResizeShortcut(nil, for: action)
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveResizeShortcut(nil, action: action)
        } else {
            setResizeShortcut(previousShortcut, for: action)
            _ = configureHotkeys(reportFailure: false)
        }
    }

    private func updateResizeShortcut(_ shortcut: KeyboardShortcut, action: WindowResizeAction, kind: GlobalShortcutKind) {
        guard isAvailableGlobalShortcut(shortcut, excluding: kind) else {
            statusMessage = "Every WindowHome shortcut must be different."
            return
        }
        let previousShortcut = resizeShortcut(for: action)
        setResizeShortcut(shortcut, for: action)
        if configureHotkeys() {
            KeyboardShortcutPreferences.saveResizeShortcut(shortcut, action: action)
        } else {
            setResizeShortcut(previousShortcut, for: action)
            _ = configureHotkeys(reportFailure: false)
        }
    }

    func resetShortcuts() {
        let previousSaveHomeShortcut = saveHomeShortcut
        let previousRestoreHomeShortcut = restoreHomeShortcut
        let previousUndoHomeShortcut = undoHomeShortcut
        let previousRedoHomeShortcut = redoHomeShortcut
        let previousRestoreAllShortcut = restoreAllShortcut
        let previousCenterAndSaveHomeShortcut = centerAndSaveHomeShortcut
        let previousMoveToNextDisplayShortcut = moveToNextDisplayShortcut
        let previousMoveToPreviousDisplayShortcut = moveToPreviousDisplayShortcut
        let previousSnapShortcuts = SnapDirection.allCases.map(snapShortcut)
        let previousResizeShortcuts = WindowResizeAction.allCases.map(resizeShortcut)
        saveHomeShortcut = .saveHomeDefault
        restoreHomeShortcut = .restoreHomeDefault
        undoHomeShortcut = .undoHomeDefault
        redoHomeShortcut = .redoHomeDefault
        restoreAllShortcut = .restoreAllDefault
        centerAndSaveHomeShortcut = .centerAndSaveHomeDefault
        moveToNextDisplayShortcut = .moveToNextDisplayDefault
        moveToPreviousDisplayShortcut = .moveToPreviousDisplayDefault
        snapLeftShortcut = .snapLeftDefault
        snapRightShortcut = .snapRightDefault
        snapTopShortcut = .snapTopDefault
        snapBottomShortcut = .snapBottomDefault
        snapFullScreenShortcut = .snapFullScreenDefault
        snapTopLeftShortcut = .snapTopLeftDefault
        snapTopRightShortcut = .snapTopRightDefault
        snapBottomLeftShortcut = .snapBottomLeftDefault
        snapBottomRightShortcut = .snapBottomRightDefault
        increaseWidthShortcut = .increaseWidthDefault
        decreaseWidthShortcut = .decreaseWidthDefault
        increaseHeightShortcut = .increaseHeightDefault
        decreaseHeightShortcut = .decreaseHeightDefault
        if configureHotkeys() {
            KeyboardShortcutPreferences.save(saveHomeShortcut, forSaveHome: true)
            KeyboardShortcutPreferences.save(restoreHomeShortcut, forSaveHome: false)
            KeyboardShortcutPreferences.saveUndoHome(undoHomeShortcut)
            KeyboardShortcutPreferences.saveRedoHome(redoHomeShortcut)
            KeyboardShortcutPreferences.saveRestoreAll(restoreAllShortcut)
            KeyboardShortcutPreferences.saveCenterAndSaveHome(centerAndSaveHomeShortcut)
            KeyboardShortcutPreferences.saveMoveToNextDisplay(moveToNextDisplayShortcut)
            KeyboardShortcutPreferences.saveMoveToPreviousDisplay(moveToPreviousDisplayShortcut)
            KeyboardShortcutPreferences.saveSnapShortcut(snapLeftShortcut, direction: .left)
            KeyboardShortcutPreferences.saveSnapShortcut(snapRightShortcut, direction: .right)
            KeyboardShortcutPreferences.saveSnapShortcut(snapTopShortcut, direction: .top)
            KeyboardShortcutPreferences.saveSnapShortcut(snapBottomShortcut, direction: .bottom)
            KeyboardShortcutPreferences.saveSnapShortcut(snapFullScreenShortcut, direction: .fullScreen)
            KeyboardShortcutPreferences.saveSnapShortcut(snapTopLeftShortcut, direction: .topLeft)
            KeyboardShortcutPreferences.saveSnapShortcut(snapTopRightShortcut, direction: .topRight)
            KeyboardShortcutPreferences.saveSnapShortcut(snapBottomLeftShortcut, direction: .bottomLeft)
            KeyboardShortcutPreferences.saveSnapShortcut(snapBottomRightShortcut, direction: .bottomRight)
            KeyboardShortcutPreferences.saveResizeShortcut(increaseWidthShortcut, action: .increaseWidth)
            KeyboardShortcutPreferences.saveResizeShortcut(decreaseWidthShortcut, action: .decreaseWidth)
            KeyboardShortcutPreferences.saveResizeShortcut(increaseHeightShortcut, action: .increaseHeight)
            KeyboardShortcutPreferences.saveResizeShortcut(decreaseHeightShortcut, action: .decreaseHeight)
        } else {
            saveHomeShortcut = previousSaveHomeShortcut
            restoreHomeShortcut = previousRestoreHomeShortcut
            undoHomeShortcut = previousUndoHomeShortcut
            redoHomeShortcut = previousRedoHomeShortcut
            restoreAllShortcut = previousRestoreAllShortcut
            centerAndSaveHomeShortcut = previousCenterAndSaveHomeShortcut
            moveToNextDisplayShortcut = previousMoveToNextDisplayShortcut
            moveToPreviousDisplayShortcut = previousMoveToPreviousDisplayShortcut
            for (direction, shortcut) in zip(SnapDirection.allCases, previousSnapShortcuts) { setSnapShortcut(shortcut, for: direction) }
            for (action, shortcut) in zip(WindowResizeAction.allCases, previousResizeShortcuts) { setResizeShortcut(shortcut, for: action) }
            _ = configureHotkeys(reportFailure: false)
        }
    }

    @discardableResult
    private func configureHotkeys(reportFailure: Bool = true) -> Bool {
        guard let hotkeyService else { return false }
        do {
            try hotkeyService.register(
                saveHome: saveHomeShortcut,
                restoreHome: restoreHomeShortcut,
                undoHome: undoHomeShortcut,
                redoHome: redoHomeShortcut,
                restoreAll: restoreAllShortcut,
                centerAndSaveHome: centerAndSaveHomeShortcut,
                moveToNextDisplay: moveToNextDisplayShortcut,
                moveToPreviousDisplay: moveToPreviousDisplayShortcut,
                snapLeft: snapLeftShortcut,
                snapRight: snapRightShortcut,
                snapTop: snapTopShortcut,
                snapBottom: snapBottomShortcut,
                snapFullScreen: snapFullScreenShortcut,
                snapTopLeft: snapTopLeftShortcut,
                snapTopRight: snapTopRightShortcut,
                snapBottomLeft: snapBottomLeftShortcut,
                snapBottomRight: snapBottomRightShortcut,
                increaseWidth: increaseWidthShortcut,
                decreaseWidth: decreaseWidthShortcut,
                increaseHeight: increaseHeightShortcut,
                decreaseHeight: decreaseHeightShortcut,
                onSaveHome: { [weak self] in
                    Task { @MainActor [weak self] in self?.saveHome() }
                },
                onRestoreHome: { [weak self] in
                    Task { @MainActor [weak self] in self?.restoreHome() }
                },
                onUndoHome: { [weak self] in
                    Task { @MainActor [weak self] in self?.undoHome() }
                },
                onRedoHome: { [weak self] in
                    Task { @MainActor [weak self] in self?.redoHome() }
                },
                onRestoreAll: { [weak self] in
                    Task { @MainActor [weak self] in self?.restoreAllHomePositions() }
                },
                onCenterAndSaveHome: { [weak self] in
                    Task { @MainActor [weak self] in self?.centerFocusedWindowAndSaveHome() }
                },
                onMoveToNextDisplay: { [weak self] in
                    Task { @MainActor [weak self] in self?.moveFocusedWindowToNextDisplay() }
                },
                onMoveToPreviousDisplay: { [weak self] in
                    Task { @MainActor [weak self] in self?.moveFocusedWindowToPreviousDisplay() }
                },
                onSnapLeft: { [weak self] in
                    Task { @MainActor [weak self] in self?.snapFocusedWindow(to: .left) }
                },
                onSnapRight: { [weak self] in
                    Task { @MainActor [weak self] in self?.snapFocusedWindow(to: .right) }
                },
                onSnapTop: { [weak self] in
                    Task { @MainActor [weak self] in self?.snapFocusedWindow(to: .top) }
                },
                onSnapBottom: { [weak self] in
                    Task { @MainActor [weak self] in self?.snapFocusedWindow(to: .bottom) }
                },
                onSnapFullScreen: { [weak self] in Task { @MainActor [weak self] in self?.snapFocusedWindow(to: .fullScreen) } },
                onSnapTopLeft: { [weak self] in Task { @MainActor [weak self] in self?.snapFocusedWindow(to: .topLeft) } },
                onSnapTopRight: { [weak self] in Task { @MainActor [weak self] in self?.snapFocusedWindow(to: .topRight) } },
                onSnapBottomLeft: { [weak self] in Task { @MainActor [weak self] in self?.snapFocusedWindow(to: .bottomLeft) } },
                onSnapBottomRight: { [weak self] in Task { @MainActor [weak self] in self?.snapFocusedWindow(to: .bottomRight) } },
                onIncreaseWidth: { [weak self] in Task { @MainActor [weak self] in self?.resizeFocusedWindow(.increaseWidth) } },
                onDecreaseWidth: { [weak self] in Task { @MainActor [weak self] in self?.resizeFocusedWindow(.decreaseWidth) } },
                onIncreaseHeight: { [weak self] in Task { @MainActor [weak self] in self?.resizeFocusedWindow(.increaseHeight) } },
                onDecreaseHeight: { [weak self] in Task { @MainActor [weak self] in self?.resizeFocusedWindow(.decreaseHeight) } }
            )
            return true
        } catch {
            if reportFailure { statusMessage = error.localizedDescription }
            return false
        }
    }

    private func configureMouseWindowTracking() {
        guard automaticSaveAfterMouseMoveEnabled || mouseSnapEnabled else {
            mouseWindowTrackingService.stop()
            mouseGesture = nil
            mouseSnapPreviewService.hide()
            mouseSnapPreviewService.hideActivationZones()
            return
        }
        do {
            try mouseWindowTrackingService.start(
                onMouseDown: { [weak self] in Task { @MainActor [weak self] in self?.captureMouseGesture() } },
                onMouseDragged: { [weak self] event in Task { @MainActor [weak self] in self?.markMouseGestureDragged(event) } },
                onMouseUp: { [weak self] in Task { @MainActor [weak self] in self?.finishMouseGesture() } }
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func captureMouseGesture() {
        guard automaticSaveAfterMouseMoveEnabled || mouseSnapEnabled else { return }
        do {
            let snapshot = try focusedWindowService.focusedWindow()
            guard snapshot.bundleIdentifier != Bundle.main.bundleIdentifier else {
                mouseGesture = nil
                return
            }
            guard !focusedWindowService.isFullScreen(snapshot.window) else { return }
            let display = try displayService.context(forAccessibilityGeometry: snapshot.geometry)
            mouseGesture = MouseGesture(
                snapshot: snapshot,
                sourceDisplay: display,
                wasSnapped: isSnapGeometry(snapshot.geometry, on: display),
                didDrag: false,
                candidate: nil,
                didTearOffFromSnap: false
            )
        } catch {
            mouseGesture = nil
        }
    }

    private func markMouseGestureDragged(_ event: MouseDragEvent) {
        guard var gesture = mouseGesture else { return }
        guard gesture.didDrag || hasWindowGeometryDriftedSinceMouseDown(gesture) else { return }
        gesture.didDrag = true
        if let candidate = mouseSnapCandidate(for: event) {
            gesture.candidate = candidate
            let frame = SnapLayout.appKitRect(direction: candidate.direction, fraction: 0.5, padding: CGFloat(snapPadding), visibleFrame: candidate.display.visibleFrame)
            let sourceFrame = displayService.coordinateConverter().appKitRect(fromAccessibility: gesture.snapshot.geometry)
            mouseSnapPreviewService.show(frame: frame, from: sourceFrame)
        } else {
            gesture.candidate = nil
            mouseSnapPreviewService.hide()
            if gesture.wasSnapped, !gesture.didTearOffFromSnap {
                tearOffMouseSnappedWindow(gesture, mouseLocation: event.mouseLocation)
                gesture.didTearOffFromSnap = true
            }
        }
        updateMouseSnapActivationZones(for: event, activeDirection: gesture.candidate?.direction)
        mouseGesture = gesture
    }

    private func finishMouseGesture() {
        guard let gesture = mouseGesture, gesture.didDrag else {
            mouseGesture = nil
            mouseSnapPreviewService.hide()
            mouseSnapPreviewService.hideActivationZones()
            return
        }
        mouseGesture = nil
        mouseSnapPreviewService.hide()
        mouseSnapPreviewService.hideActivationZones()
        guard let actual = try? focusedWindowService.readGeometry(of: gesture.snapshot.window, fallbackProcessIdentifier: gesture.snapshot.processIdentifier), !matches(actual, gesture.snapshot.geometry) else { return }
        if mouseSnapEnabled, let candidate = gesture.candidate {
            saveHomeBeforeFirstSnapIfNeeded(snapshot: gesture.snapshot, on: gesture.sourceDisplay)
            let geometry = SnapLayout.accessibilityGeometry(direction: candidate.direction, fraction: 0.5, padding: CGFloat(snapPadding), visibleFrame: candidate.display.visibleFrame, converter: displayService.coordinateConverter())
            do {
                try applySnapGeometry(geometry, direction: candidate.direction, on: candidate.display, to: gesture.snapshot)
                resetSnapCycle()
                statusMessage = "Mouse-snapped \(gesture.snapshot.applicationName) to \(snapLabel(for: candidate.direction))."
            } catch {
                statusMessage = "Could not apply mouse Snap: \(error.localizedDescription)"
            }
            return
        }
        finishUnsnappedMouseGesture(gesture, actualGeometry: actual)
    }

    private func finishUnsnappedMouseGesture(_ gesture: MouseGesture, actualGeometry: WindowGeometry) {
        guard let targetDisplay = try? displayService.context(forAccessibilityGeometry: actualGeometry) else { return }
        if gesture.wasSnapped {
            if gesture.didTearOffFromSnap {
                resetSnapCycle()
                return
            }
            if targetDisplay.fingerprint != gesture.sourceDisplay.fingerprint,
               !hasHomeProfile(for: gesture.snapshot, on: targetDisplay) {
                _ = try? saveHome(snapshot: gesture.snapshot, geometry: actualGeometry, on: targetDisplay)
            } else {
                restoreHomeIfAvailable(for: gesture.snapshot, on: targetDisplay)
            }
            resetSnapCycle()
            return
        }
        if automaticSaveAfterMouseMoveEnabled {
            saveMouseAdjustedHome(for: gesture.snapshot)
        }
    }

    private func tearOffMouseSnappedWindow(_ gesture: MouseGesture, mouseLocation: CGPoint) {
        restoreHomeSizeIfAvailable(for: gesture.snapshot, on: gesture.sourceDisplay, mouseLocation: mouseLocation)
        resetSnapCycle()
    }

    private func hasWindowGeometryDriftedSinceMouseDown(_ gesture: MouseGesture) -> Bool {
        guard let actualGeometry = try? focusedWindowService.readGeometry(
            of: gesture.snapshot.window,
            fallbackProcessIdentifier: gesture.snapshot.processIdentifier
        ) else {
            return false
        }
        return !matches(actualGeometry, gesture.snapshot.geometry, tolerance: 3)
    }

    private func mouseSnapCandidate(for event: MouseDragEvent) -> (direction: SnapDirection, display: DisplayContext)? {
        switch mouseSnapMode {
        case .off:
            return nil
        case .edgeAndOption:
            return displayService.mouseSnapDirection(atMouseLocation: event.mouseLocation, optionPressed: event.optionPressed)
        case .optionOnly:
            guard event.optionPressed else { return nil }
            return displayService.mouseSnapDirection(atMouseLocation: event.mouseLocation, optionPressed: true)
        }
    }

    private func updateMouseSnapActivationZones(for event: MouseDragEvent, activeDirection: SnapDirection?) {
        guard showMouseSnapAreas else {
            mouseSnapPreviewService.hideActivationZones()
            return
        }

        let optionPressed: Bool
        switch mouseSnapMode {
        case .off:
            mouseSnapPreviewService.hideActivationZones()
            return
        case .edgeAndOption:
            optionPressed = event.optionPressed
        case .optionOnly:
            guard event.optionPressed else {
                mouseSnapPreviewService.hideActivationZones()
                return
            }
            optionPressed = true
        }

        guard let activation = displayService.mouseSnapActivationZones(
            atMouseLocation: event.mouseLocation,
            optionPressed: optionPressed
        ) else {
            mouseSnapPreviewService.hideActivationZones()
            return
        }
        mouseSnapPreviewService.showActivationZones(activation.zones, activeDirection: activeDirection)
    }

    private func isSnapGeometry(_ geometry: WindowGeometry, on display: DisplayContext) -> Bool {
        let converter = displayService.coordinateConverter()
        for direction in SnapDirection.allCases {
            let fractions: [CGFloat] = direction == .fullScreen ? [0.5] : SnapLayout.fractions
            for fraction in fractions {
                let candidate = SnapLayout.accessibilityGeometry(direction: direction, fraction: fraction, padding: CGFloat(snapPadding), visibleFrame: display.visibleFrame, converter: converter)
                if matches(geometry, candidate, tolerance: 8) { return true }
            }
        }
        return false
    }

    private func isWindowSnapped(_ snapshot: FocusedWindowSnapshot, on display: DisplayContext) -> Bool {
        focusedWindowService.isFullScreen(snapshot.window)
            || isSnapGeometry(snapshot.geometry, on: display)
            || displayService.isLikelySystemTiled(accessibilityGeometry: snapshot.geometry)
    }

    private func hasHomeProfile(for snapshot: FocusedWindowSnapshot, on display: DisplayContext) -> Bool {
        guard let bundleIdentifier = snapshot.bundleIdentifier else { return false }
        return profileStore?.profile(bundleIdentifier: bundleIdentifier, displayFingerprint: display.fingerprint) != nil
    }

    private func restoreHomeIfAvailable(for snapshot: FocusedWindowSnapshot, on display: DisplayContext) {
        guard let bundleIdentifier = snapshot.bundleIdentifier,
              let profile = profileStore?.profile(bundleIdentifier: bundleIdentifier, displayFingerprint: display.fingerprint) else { return }
        do {
            let geometry = displayService.constrainedAccessibilityGeometry(
                profile.geometry.accessibilityGeometry(for: display.visibleFrame, converter: displayService.coordinateConverter()),
                on: display,
                padding: CGFloat(snapPadding)
            )
            try focusedWindowService.setGeometry(geometry, for: snapshot.window)
        } catch {
            statusMessage = "Could not restore Home after mouse unsnap: \(error.localizedDescription)"
        }
    }

    private func restoreHomeSizeIfAvailable(for snapshot: FocusedWindowSnapshot, on display: DisplayContext, mouseLocation: CGPoint) {
        guard let bundleIdentifier = snapshot.bundleIdentifier,
              let profile = profileStore?.profile(bundleIdentifier: bundleIdentifier, displayFingerprint: display.fingerprint),
              let currentGeometry = try? focusedWindowService.readGeometry(of: snapshot.window, fallbackProcessIdentifier: snapshot.processIdentifier) else { return }
        do {
            let converter = displayService.coordinateConverter()
            let currentRect = converter.appKitRect(fromAccessibility: currentGeometry)
            let restoredGeometry = profile.geometry.accessibilityGeometry(for: display.visibleFrame, converter: displayService.coordinateConverter())
            let targetRect = CGRect(
                x: mouseLocation.x - restoredGeometry.size.width / 2,
                y: currentRect.maxY - restoredGeometry.size.height,
                width: restoredGeometry.size.width,
                height: restoredGeometry.size.height
            )
            let constrainedGeometry = displayService.constrainedAccessibilityGeometry(
                converter.accessibilityGeometry(fromAppKit: targetRect),
                on: display,
                padding: CGFloat(snapPadding)
            )
            try focusedWindowService.setGeometry(constrainedGeometry, for: snapshot.window)
        } catch {
            statusMessage = "Could not restore Home size during mouse unsnap: \(error.localizedDescription)"
        }
    }

    private func snapFractionIndex(for geometry: WindowGeometry, direction: SnapDirection, on display: DisplayContext) -> Int? {
        guard direction != .fullScreen else { return nil }
        let converter = displayService.coordinateConverter()
        for (index, fraction) in SnapLayout.fractions.enumerated() {
            let candidate = SnapLayout.accessibilityGeometry(
                direction: direction,
                fraction: fraction,
                padding: CGFloat(snapPadding),
                visibleFrame: display.visibleFrame,
                converter: converter
            )
            if matches(geometry, candidate, tolerance: 8) {
                return index
            }
        }
        return nil
    }

    @discardableResult
    private func saveHome(snapshot: FocusedWindowSnapshot, geometry: WindowGeometry, on display: DisplayContext) throws -> Bool {
        guard let bundleIdentifier = snapshot.bundleIdentifier, let profileStore else { return false }
        let profile = WindowProfile(id: UUID(), bundleIdentifier: bundleIdentifier, applicationName: snapshot.applicationName, displayFingerprint: display.fingerprint, displayName: display.name, geometry: StoredGeometry(accessibilityGeometry: geometry, visibleFrame: display.visibleFrame, converter: displayService.coordinateConverter()), updatedAt: Date())
        try profileStore.upsert(profile)
        return true
    }

    private func saveMouseAdjustedHome(for snapshot: FocusedWindowSnapshot) {
        guard automaticSaveAfterMouseMoveEnabled else { return }
        do {
            guard !focusedWindowService.isFullScreen(snapshot.window) else { return }
            let geometry = try focusedWindowService.readGeometry(of: snapshot.window, fallbackProcessIdentifier: snapshot.processIdentifier)
            guard geometry != snapshot.geometry, !displayService.isLikelySystemTiled(accessibilityGeometry: geometry) else { return }
            guard let bundleIdentifier = snapshot.bundleIdentifier, let profileStore else { return }
            let display = try displayService.context(forAccessibilityGeometry: geometry)
            let profile = WindowProfile(
                id: UUID(),
                bundleIdentifier: bundleIdentifier,
                applicationName: snapshot.applicationName,
                displayFingerprint: display.fingerprint,
                displayName: display.name,
                geometry: StoredGeometry(accessibilityGeometry: geometry, visibleFrame: display.visibleFrame, converter: displayService.coordinateConverter()),
                updatedAt: Date()
            )
            try profileStore.upsert(profile)
            statusMessage = "Automatically saved Home for \(snapshot.applicationName) on \(display.name)."
        } catch {
            statusMessage = "Could not automatically save Home: \(error.localizedDescription)"
        }
    }

    private func moveFocusedWindow(to direction: DisplayService.MoveDirection) {
        perform("move the focused window to another display") { snapshot in
            cancelLaunchRestoreStabilization()
            resetSnapCycle()
            let sourceDisplay = try displayService.context(forAccessibilityGeometry: snapshot.geometry)
            guard let targetDisplay = displayService.adjacentDisplay(to: sourceDisplay, direction: direction) else {
                statusMessage = "Connect another display to move this window."
                return
            }

            let targetGeometry: WindowGeometry
            let status: String
            let shouldApplyTargetSizeImmediately = DisplayMoveHomePolicy.shouldApplyFullHome(
                automationEnabled: restoreFullHomeAfterDisplayMoveEnabled,
                sourceIsFullScreen: focusedWindowService.isFullScreen(snapshot.window),
                sourceIsWindowHomeSnapped: isSnapGeometry(snapshot.geometry, on: sourceDisplay),
                sourceIsSystemTiled: displayService.isLikelySystemTiled(accessibilityGeometry: snapshot.geometry)
            )
            if let bundleIdentifier = snapshot.bundleIdentifier,
               let profile = profileStore?.profile(bundleIdentifier: bundleIdentifier, displayFingerprint: targetDisplay.fingerprint) {
                targetGeometry = displayService.constrainedAccessibilityGeometry(
                    profile.geometry.accessibilityGeometry(for: targetDisplay.visibleFrame, converter: displayService.coordinateConverter()),
                    on: targetDisplay,
                    padding: CGFloat(snapPadding)
                )
                status = shouldApplyTargetSizeImmediately
                    ? "Moved \(snapshot.applicationName) to the Home position on \(targetDisplay.name)."
                    : "Moved \(snapshot.applicationName) to the Home position on \(targetDisplay.name). Press Restore Home to apply its saved size."
            } else {
                targetGeometry = displayService.defaultAccessibilityGeometry(from: snapshot.geometry, on: targetDisplay, padding: CGFloat(snapPadding))
                status = "Moved \(snapshot.applicationName) to a centered position on \(targetDisplay.name). Save Home there to customize it."
            }

            if shouldApplyTargetSizeImmediately,
               hasHomeProfile(for: snapshot, on: targetDisplay) {
                let writeOrder = DisplayMoveHomePolicy.geometryWriteOrder(
                    targetSize: targetGeometry.size,
                    sourceVisibleFrame: sourceDisplay.visibleFrame,
                    padding: CGFloat(snapPadding)
                )
                try focusedWindowService.setGeometryForDisplayMove(
                    targetGeometry,
                    writeOrder: writeOrder,
                    for: snapshot.window
                )
                focusedWindowDescription = "\(snapshot.applicationName) on \(targetDisplay.name)\n\(targetGeometry.description)"
                statusMessage = status
                return
            }

            let transferPlan = displayService.transferPlan(
                from: snapshot.geometry,
                toward: targetGeometry,
                on: targetDisplay,
                padding: CGFloat(snapPadding)
            )
            if transferPlan.requiresResize {
                try focusedWindowService.setGeometry(transferPlan.geometry, for: snapshot.window)
            } else {
                try focusedWindowService.setPosition(transferPlan.geometry.origin, for: snapshot.window)
            }
            focusedWindowDescription = "\(snapshot.applicationName) on \(targetDisplay.name)\n\(transferPlan.geometry.description)"
            statusMessage = status
        }
    }

    private func applySnapGeometry(_ geometry: WindowGeometry, direction: SnapDirection, on display: DisplayContext, to snapshot: FocusedWindowSnapshot) throws {
        cancelLaunchRestoreStabilization()
        let snapRequestID = UUID()
        activeSnapRequestID = snapRequestID
        // Some apps recalculate their frame for a short time after a resize or internal mode
        // switch. Keep ownership of the frame for a brief bounded settling window, but only for
        // the latest explicit Snap request.
        try focusedWindowService.setPosition(geometry.origin, for: snapshot.window)
        try focusedWindowService.setSize(geometry.size, for: snapshot.window)
        let effectiveGeometry = centeredFullScreenGeometryIfNeeded(
            requestedGeometry: geometry,
            direction: direction,
            display: display,
            window: snapshot.window,
            fallbackProcessIdentifier: snapshot.processIdentifier
        )
        if effectiveGeometry.origin != geometry.origin {
            try focusedWindowService.setPosition(effectiveGeometry.origin, for: snapshot.window)
        }
        retrySnapGeometry(effectiveGeometry, direction: direction, on: display, for: snapshot, attempt: 0, snapRequestID: snapRequestID)
    }

    private func retrySnapGeometry(_ geometry: WindowGeometry, direction: SnapDirection, on display: DisplayContext, for snapshot: FocusedWindowSnapshot, attempt: Int, snapRequestID: UUID) {
        let delays: [TimeInterval] = [0.08, 0.12, 0.18, 0.26, 0.36, 0.48]
        guard attempt < delays.count else {
            if activeSnapRequestID == snapRequestID {
                activeSnapRequestID = nil
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
            guard let self else { return }
            guard self.activeSnapRequestID == snapRequestID else { return }
            guard let actual = try? self.focusedWindowService.readGeometry(of: snapshot.window, fallbackProcessIdentifier: snapshot.processIdentifier) else {
                if self.activeSnapRequestID == snapRequestID {
                    self.activeSnapRequestID = nil
                }
                return
            }
            do {
                let effectiveGeometry = self.centeredFullScreenGeometryIfNeeded(
                    requestedGeometry: geometry,
                    actualGeometry: actual,
                    direction: direction,
                    display: display
                )
                if !self.matches(actual, effectiveGeometry) {
                    try self.focusedWindowService.setPosition(effectiveGeometry.origin, for: snapshot.window)
                    try self.focusedWindowService.setSize(effectiveGeometry.size, for: snapshot.window)
                }
                self.retrySnapGeometry(effectiveGeometry, direction: direction, on: display, for: snapshot, attempt: attempt + 1, snapRequestID: snapRequestID)
            } catch {
                if self.activeSnapRequestID == snapRequestID {
                    self.activeSnapRequestID = nil
                }
                return
            }
        }
    }

    private func centeredFullScreenGeometryIfNeeded(
        requestedGeometry: WindowGeometry,
        actualGeometry: WindowGeometry? = nil,
        direction: SnapDirection,
        display: DisplayContext,
        window: AXUIElement? = nil,
        fallbackProcessIdentifier: pid_t? = nil
    ) -> WindowGeometry {
        guard direction == .fullScreen else { return requestedGeometry }
        let actual = actualGeometry ?? (window.flatMap { try? focusedWindowService.readGeometry(of: $0, fallbackProcessIdentifier: fallbackProcessIdentifier) })
        guard let actual,
              actual.size.width < requestedGeometry.size.width - 2 || actual.size.height < requestedGeometry.size.height - 2 else {
            return requestedGeometry
        }
        return displayService.centeredAccessibilityGeometry(
            size: actual.size,
            on: display,
            padding: CGFloat(snapPadding)
        )
    }

    private func matches(_ lhs: WindowGeometry, _ rhs: WindowGeometry, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance && abs(lhs.origin.y - rhs.origin.y) <= tolerance && abs(lhs.size.width - rhs.size.width) <= tolerance && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private func cancelLaunchRestoreStabilization() {
        activeLaunchRestoreRequestID = nil
    }

    private func resetSnapCycle() {
        activeSnapRequestID = nil
        lastSnapDirection = nil
        lastSnapProcessIdentifier = nil
        lastSnapWindowIdentifier = nil
        snapFractionIndex = 0
    }

    private func snapShortcut(for direction: SnapDirection) -> KeyboardShortcut? {
        switch direction {
        case .left: snapLeftShortcut
        case .right: snapRightShortcut
        case .top: snapTopShortcut
        case .bottom: snapBottomShortcut
        case .fullScreen: snapFullScreenShortcut
        case .topLeft: snapTopLeftShortcut
        case .topRight: snapTopRightShortcut
        case .bottomLeft: snapBottomLeftShortcut
        case .bottomRight: snapBottomRightShortcut
        }
    }

    private func setSnapShortcut(_ shortcut: KeyboardShortcut?, for direction: SnapDirection) {
        switch direction {
        case .left: snapLeftShortcut = shortcut
        case .right: snapRightShortcut = shortcut
        case .top: snapTopShortcut = shortcut
        case .bottom: snapBottomShortcut = shortcut
        case .fullScreen: snapFullScreenShortcut = shortcut
        case .topLeft: snapTopLeftShortcut = shortcut
        case .topRight: snapTopRightShortcut = shortcut
        case .bottomLeft: snapBottomLeftShortcut = shortcut
        case .bottomRight: snapBottomRightShortcut = shortcut
        }
    }

    private func resizeShortcut(for action: WindowResizeAction) -> KeyboardShortcut? {
        switch action {
        case .increaseWidth: increaseWidthShortcut
        case .decreaseWidth: decreaseWidthShortcut
        case .increaseHeight: increaseHeightShortcut
        case .decreaseHeight: decreaseHeightShortcut
        }
    }

    private func setResizeShortcut(_ shortcut: KeyboardShortcut?, for action: WindowResizeAction) {
        switch action {
        case .increaseWidth: increaseWidthShortcut = shortcut
        case .decreaseWidth: decreaseWidthShortcut = shortcut
        case .increaseHeight: increaseHeightShortcut = shortcut
        case .decreaseHeight: decreaseHeightShortcut = shortcut
        }
    }

    private func snapLabel(for direction: SnapDirection) -> String {
        switch direction {
        case .left: "the left"
        case .right: "the right"
        case .top: "the top"
        case .bottom: "the bottom"
        case .fullScreen: "full screen"
        case .topLeft: "the top-left"
        case .topRight: "the top-right"
        case .bottomLeft: "the bottom-left"
        case .bottomRight: "the bottom-right"
        }
    }

    private enum GlobalShortcutKind {
        case saveHome, restoreHome, undoHome, redoHome, restoreAll, centerAndSaveHome, moveToNextDisplay, moveToPreviousDisplay, snapLeft, snapRight, snapTop, snapBottom, snapFullScreen, snapTopLeft, snapTopRight, snapBottomLeft, snapBottomRight, increaseWidth, decreaseWidth, increaseHeight, decreaseHeight
    }

    private func isAvailableGlobalShortcut(_ shortcut: KeyboardShortcut, excluding kind: GlobalShortcutKind) -> Bool {
        let shortcuts: [(GlobalShortcutKind, KeyboardShortcut?)] = [
            (.saveHome, saveHomeShortcut),
            (.restoreHome, restoreHomeShortcut),
            (.undoHome, undoHomeShortcut),
            (.redoHome, redoHomeShortcut),
            (.restoreAll, restoreAllShortcut),
            (.centerAndSaveHome, centerAndSaveHomeShortcut),
            (.moveToNextDisplay, moveToNextDisplayShortcut),
            (.moveToPreviousDisplay, moveToPreviousDisplayShortcut),
            (.snapLeft, snapLeftShortcut),
            (.snapRight, snapRightShortcut),
            (.snapTop, snapTopShortcut),
            (.snapBottom, snapBottomShortcut),
            (.snapFullScreen, snapFullScreenShortcut),
            (.snapTopLeft, snapTopLeftShortcut),
            (.snapTopRight, snapTopRightShortcut),
            (.snapBottomLeft, snapBottomLeftShortcut),
            (.snapBottomRight, snapBottomRightShortcut),
            (.increaseWidth, increaseWidthShortcut),
            (.decreaseWidth, decreaseWidthShortcut),
            (.increaseHeight, increaseHeightShortcut),
            (.decreaseHeight, decreaseHeightShortcut)
        ]
        return shortcuts.allSatisfy { $0.0 == kind || $0.1 != shortcut }
    }

    private func perform(_ action: String, operation: (FocusedWindowSnapshot) throws -> Void) {
        do {
            let snapshot = try focusedWindowService.focusedWindow()
            lastSnapshot = snapshot
            try operation(snapshot)
        } catch {
            statusMessage = "Could not \(action): \(error.localizedDescription)"
        }
    }
}
