import AppKit
import Carbon

enum StartupPolicy {
    static func shouldOpenSettings(permissionsGranted: Bool, launchedInBackground: Bool) -> Bool {
        !permissionsGranted && !launchedInBackground
    }

    static func isBackgroundLaunch(_ launchEvent: NSAppleEventDescriptor?) -> Bool {
        guard let launchEvent, launchEvent.eventClass == kCoreEventClass,
              launchEvent.eventID == kAEOpenApplication else { return false }
        let reason = launchEvent.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        // Login Item не должен перехватывать фокус окном настроек при входе в macOS.
        return reason == keyAELaunchedAsLogInItem || reason == keyAELaunchedAsServiceItem
            || launchEvent.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
            || launchEvent.paramDescriptor(forKeyword: keyAELaunchedAsServiceItem) != nil
    }
}
