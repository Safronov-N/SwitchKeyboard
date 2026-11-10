import Foundation
import ServiceManagement
import XCTest
@testable import SwitchKeyboard

final class LoginItemControllerTests: XCTestCase {
    @MainActor
    func testDefaultRegistrationIsAttemptedOnlyOnce() async {
        let service = FakeLoginItemService()
        let defaults = MemoryLoginItemDefaults()
        let controller = LoginItemController(service: service, defaults: defaults)
        controller.enableByDefaultIfNeeded()
        controller.enableByDefaultIfNeeded()
        controller.refresh()
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: "launchAtLoginDefaultApplied"))
    }

    @MainActor
    func testFreshInstallNotFoundStatusRegistersByDefaultOnce() async {
        let service = FakeLoginItemService(status: .notFound)
        let controller = LoginItemController(service: service, defaults: MemoryLoginItemDefaults())
        controller.enableByDefaultIfNeeded()
        controller.enableByDefaultIfNeeded()
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
    }

    @MainActor
    func testUserDisablingAutostartIsRespected() async {
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service, defaults: MemoryLoginItemDefaults())
        controller.enableByDefaultIfNeeded()
        controller.setEnabled(false)
        controller.enableByDefaultIfNeeded()
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertFalse(controller.isEnabled)
    }

    @MainActor
    func testFailedDefaultRegistrationDoesNotClaimEnabledOrRepeat() async {
        let service = FakeLoginItemService()
        service.registrationError = LoginItemTestError.denied
        let controller = LoginItemController(service: service, defaults: MemoryLoginItemDefaults())
        controller.enableByDefaultIfNeeded()
        controller.refresh()
        controller.enableByDefaultIfNeeded()
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertTrue(controller.statusMessage.contains("Не удалось включить"))
    }

    @MainActor
    func testManualRetryAfterFailureCanEnableAutostart() async {
        let service = FakeLoginItemService()
        service.registrationError = LoginItemTestError.denied
        let controller = LoginItemController(service: service, defaults: MemoryLoginItemDefaults())
        controller.enableByDefaultIfNeeded()
        service.registrationError = nil
        controller.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 2)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(controller.statusMessage, "Запуск при входе включён.")
    }

    @MainActor
    func testUnregisterFailureKeepsActualEnabledStatus() async {
        let service = FakeLoginItemService(status: .enabled)
        service.unregistrationError = LoginItemTestError.denied
        let controller = LoginItemController(service: service, defaults: MemoryLoginItemDefaults())
        controller.setEnabled(false)
        controller.refresh()
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(controller.statusMessage.contains("Не удалось выключить"))
    }

    @MainActor
    func testPendingApprovalAndLaterDenialDoNotReregisterAutomatically() async {
        let service = FakeLoginItemService(status: .requiresApproval)
        let controller = LoginItemController(service: service, defaults: MemoryLoginItemDefaults())
        controller.enableByDefaultIfNeeded()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(controller.requiresApproval)
        XCTAssertEqual(service.registerCalls, 0)
        controller.openSystemSettings()
        XCTAssertEqual(service.openSettingsCalls, 1)
        service.status = .notRegistered
        controller.refresh()
        controller.enableByDefaultIfNeeded()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertEqual(service.registerCalls, 0)
    }

    @MainActor
    func testRefreshReadsExternalChangesWithoutRegistration() async {
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service, defaults: MemoryLoginItemDefaults())
        service.status = .enabled
        controller.refresh()
        XCTAssertTrue(controller.isEnabled)
        service.status = .notRegistered
        controller.refresh()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    @MainActor
    func testExplicitDisableBeforeDefaultAttemptPreventsRegistration() async {
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service, defaults: MemoryLoginItemDefaults())
        controller.setEnabled(false)
        controller.enableByDefaultIfNeeded()
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
        XCTAssertFalse(controller.isEnabled)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status
    var registrationError: Error?
    var unregistrationError: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var openSettingsCalls = 0

    init(status: SMAppService.Status = .notRegistered) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registrationError { throw registrationError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }

    func openSystemSettings() {
        openSettingsCalls += 1
    }
}

private final class MemoryLoginItemDefaults: UserDefaults, @unchecked Sendable {
    private var flags: [String: Bool] = [:]

    override func bool(forKey defaultName: String) -> Bool {
        flags[defaultName] ?? false
    }

    override func set(_ value: Bool, forKey defaultName: String) {
        flags[defaultName] = value
    }
}

private enum LoginItemTestError: LocalizedError {
    case denied

    var errorDescription: String? { "Тестовая служба отказала в операции" }
}
