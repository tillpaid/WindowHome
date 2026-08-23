import AppKit
import ApplicationServices

final class ApplicationLaunchObserver {
    private static let finderBundleIdentifier = "com.apple.finder"

    private var workspaceObserver: NSObjectProtocol?
    private var finderObserver: AXObserver?
    private var finderApplicationElement: AXUIElement?
    private var onFinderWindowCreated: ((NSRunningApplication, AXUIElement) -> Void)?

    deinit { stop() }

    func start(
        onLaunch: @escaping (NSRunningApplication) -> Void,
        onFinderWindowCreated: @escaping (NSRunningApplication, AXUIElement) -> Void
    ) {
        stop()
        self.onFinderWindowCreated = onFinderWindowCreated
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            onLaunch(application)
            if application.bundleIdentifier == Self.finderBundleIdentifier {
                self?.observeFinderWindows(for: application)
            }
        }
        refreshFinderObservation()
    }

    func refreshFinderObservation() {
        guard AccessibilityPermissionService.isTrusted,
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: Self.finderBundleIdentifier).first else {
            stopFinderObservation()
            return
        }
        observeFinderWindows(for: finder)
    }

    func stop() {
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        stopFinderObservation()
        onFinderWindowCreated = nil
    }

    fileprivate func handleFinderWindowCreated(_ window: AXUIElement) {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(window, &processIdentifier) == .success,
              let application = NSRunningApplication(processIdentifier: processIdentifier),
              application.bundleIdentifier == Self.finderBundleIdentifier else {
            return
        }
        onFinderWindowCreated?(application, window)
    }

    private func observeFinderWindows(for application: NSRunningApplication) {
        stopFinderObservation()

        var observer: AXObserver?
        guard AXObserverCreate(application.processIdentifier, finderWindowCreatedCallback, &observer) == .success,
              let observer else {
            return
        }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard AXObserverAddNotification(
            observer,
            applicationElement,
            kAXWindowCreatedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        ) == .success else {
            return
        }

        finderObserver = observer
        finderApplicationElement = applicationElement
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func stopFinderObservation() {
        guard let finderObserver else {
            finderApplicationElement = nil
            return
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(finderObserver), .commonModes)
        if let finderApplicationElement {
            AXObserverRemoveNotification(
                finderObserver,
                finderApplicationElement,
                kAXWindowCreatedNotification as CFString
            )
        }
        self.finderObserver = nil
        finderApplicationElement = nil
    }
}

private func finderWindowCreatedCallback(
    observer _: AXObserver,
    element: AXUIElement,
    notification: CFString,
    context: UnsafeMutableRawPointer?
) {
    guard notification as String == kAXWindowCreatedNotification,
          let context else {
        return
    }
    Unmanaged<ApplicationLaunchObserver>.fromOpaque(context).takeUnretainedValue().handleFinderWindowCreated(element)
}
