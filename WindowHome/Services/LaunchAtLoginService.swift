import Foundation
import ServiceManagement

@MainActor
protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemManaging {}

@MainActor
final class LaunchAtLoginService {
    private static let defaultAppliedKey = "launchAtLoginDefaultApplied"
    private let defaults: UserDefaults
    private let loginItem: any LoginItemManaging

    var status: SMAppService.Status { loginItem.status }

    init(defaults: UserDefaults = .standard, loginItem: any LoginItemManaging = SMAppService.mainApp) {
        self.defaults = defaults
        self.loginItem = loginItem
    }

    func applyDefaultIfNeeded() throws {
        guard !defaults.bool(forKey: Self.defaultAppliedKey) else { return }
        // Keep an existing registration, including a choice made in System Settings.
        if status == .enabled || status == .requiresApproval {
            defaults.set(true, forKey: Self.defaultAppliedKey)
            return
        }
        try setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if status != .enabled && status != .requiresApproval {
                try loginItem.register()
            }
        } else if status == .enabled || status == .requiresApproval {
            try loginItem.unregister()
        }
        // Apply the default only once so disabling autostart survives future launches.
        defaults.set(true, forKey: Self.defaultAppliedKey)
    }
}
