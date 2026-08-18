import AppKit

final class ApplicationLaunchObserver {
    private var observer: NSObjectProtocol?

    deinit { stop() }

    func start(onLaunch: @escaping (NSRunningApplication) -> Void) {
        stop()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            onLaunch(application)
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}
