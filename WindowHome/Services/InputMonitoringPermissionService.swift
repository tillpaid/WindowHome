import CoreGraphics

enum InputMonitoringPermissionService {
    static var isGranted: Bool { CGPreflightListenEventAccess() }

    /// macOS asks the user to approve listen-only keyboard event access in Privacy & Security.
    static func requestPermission() {
        _ = CGRequestListenEventAccess()
    }
}
