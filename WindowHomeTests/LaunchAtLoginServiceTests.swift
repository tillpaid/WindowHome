import Foundation
import ServiceManagement
import Testing
@testable import WindowHome

@MainActor
struct LaunchAtLoginServiceTests {
    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let name = "WindowHomeTests.launchAtLogin.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func firstLaunchRegistersOnce() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = MockLoginItem()
        let service = LaunchAtLoginService(defaults: defaults, loginItem: item)
        try service.applyDefaultIfNeeded()
        try service.applyDefaultIfNeeded()
        #expect(item.registerCount == 1)
        #expect(service.status == .enabled)
    }

    @Test func disabledChoiceSurvivesRestartAndCanBeEnabledAgain() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = MockLoginItem()
        let service = LaunchAtLoginService(defaults: defaults, loginItem: item)
        try service.applyDefaultIfNeeded()
        try service.setEnabled(false)
        let restarted = LaunchAtLoginService(defaults: defaults, loginItem: item)
        try restarted.applyDefaultIfNeeded()
        #expect(item.registerCount == 1)
        #expect(item.unregisterCount == 1)
        #expect(restarted.status == .notRegistered)
        try restarted.setEnabled(true)
        #expect(item.registerCount == 2)
        #expect(restarted.status == .enabled)
    }

    @Test(arguments: [SMAppService.Status.enabled, .requiresApproval])
    func existingRegistrationIsPreserved(status: SMAppService.Status) throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = MockLoginItem(status: status)
        let service = LaunchAtLoginService(defaults: defaults, loginItem: item)
        try service.applyDefaultIfNeeded()
        try service.setEnabled(true)
        #expect(item.registerCount == 0)
        #expect(service.status == status)
        try service.setEnabled(false)
        #expect(item.unregisterCount == 1)
    }

    @Test func systemRemovalDoesNotCauseAutomaticReregistration() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = MockLoginItem()
        let service = LaunchAtLoginService(defaults: defaults, loginItem: item)
        try service.applyDefaultIfNeeded()
        item.status = .notRegistered
        try LaunchAtLoginService(defaults: defaults, loginItem: item).applyDefaultIfNeeded()
        #expect(item.registerCount == 1)
        #expect(service.status == .notRegistered)
    }

    @Test func registrationFailureCanBeRetried() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = MockLoginItem()
        let service = LaunchAtLoginService(defaults: defaults, loginItem: item)
        item.shouldFail = true
        #expect(throws: MockLoginItem.Failure.self) { try service.applyDefaultIfNeeded() }
        #expect(service.status == .notRegistered)
        item.shouldFail = false
        try service.applyDefaultIfNeeded()
        #expect(item.registerCount == 2)
        #expect(service.status == .enabled)
    }

    @Test func failedDisableRetainsActualSystemState() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = MockLoginItem(status: .enabled)
        let service = LaunchAtLoginService(defaults: defaults, loginItem: item)
        item.shouldFail = true
        #expect(throws: MockLoginItem.Failure.self) { try service.setEnabled(false) }
        #expect(service.status == .enabled)
    }

    @Test func disablingUnregisteredItemPreventsFirstLaunchDefault() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = MockLoginItem()
        let service = LaunchAtLoginService(defaults: defaults, loginItem: item)
        try service.setEnabled(false)
        try service.applyDefaultIfNeeded()
        #expect(item.registerCount == 0)
        #expect(item.unregisterCount == 0)
    }
}

@MainActor
private final class MockLoginItem: LoginItemManaging {
    struct Failure: Error {}
    var status: SMAppService.Status
    var registerCount = 0
    var unregisterCount = 0
    var shouldFail = false

    init(status: SMAppService.Status = .notRegistered) { self.status = status }

    func register() throws {
        registerCount += 1
        if shouldFail { throw Failure() }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if shouldFail { throw Failure() }
        status = .notRegistered
    }
}
