import AppKit
import Carbon
import XCTest
@testable import SwitchKeyboard

final class StartupPolicyTests: XCTestCase {
    func testManualLaunchIsNotBackground() {
        XCTAssertFalse(StartupPolicy.isBackgroundLaunch(nil))
        XCTAssertFalse(StartupPolicy.isBackgroundLaunch(event()))
    }

    func testLoginLaunchPropertyDataIsBackground() {
        XCTAssertTrue(StartupPolicy.isBackgroundLaunch(event(reason: keyAELaunchedAsLogInItem)))
    }

    func testServiceLaunchPropertyDataIsBackground() {
        XCTAssertTrue(StartupPolicy.isBackgroundLaunch(event(reason: keyAELaunchedAsServiceItem)))
    }

    func testDirectLoginKeywordIsBackground() {
        let event = event()
        event.setParam(NSAppleEventDescriptor.null(), forKeyword: keyAELaunchedAsLogInItem)
        XCTAssertTrue(StartupPolicy.isBackgroundLaunch(event))
    }

    func testDirectServiceKeywordIsBackground() {
        let event = event()
        event.setParam(NSAppleEventDescriptor(boolean: false), forKeyword: keyAELaunchedAsServiceItem)
        XCTAssertTrue(StartupPolicy.isBackgroundLaunch(event))
    }

    func testReopenIsNotLoginLaunch() {
        XCTAssertFalse(StartupPolicy.isBackgroundLaunch(
            event(reason: keyAELaunchedAsLogInItem, eventID: kAEReopenApplication)
        ))
    }

    func testOnlyManualSetupWithMissingPermissionsShowsWindow() {
        XCTAssertTrue(StartupPolicy.shouldOpenSettings(permissionsGranted: false, launchedInBackground: false))
        XCTAssertFalse(StartupPolicy.shouldOpenSettings(permissionsGranted: false, launchedInBackground: true))
        XCTAssertFalse(StartupPolicy.shouldOpenSettings(permissionsGranted: true, launchedInBackground: false))
        XCTAssertFalse(StartupPolicy.shouldOpenSettings(permissionsGranted: true, launchedInBackground: true))
    }

    private func event(reason: OSType? = nil, eventID: AEEventID = kAEOpenApplication) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: kCoreEventClass,
            eventID: eventID,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let reason { event.setParam(NSAppleEventDescriptor(enumCode: reason), forKeyword: keyAEPropData) }
        return event
    }
}
