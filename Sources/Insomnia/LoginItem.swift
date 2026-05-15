import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` for the "Launch at Login" menu toggle.
///
/// Requires a real `.app` bundle (works from `dist/Insomnia.app`, not from a
/// bare `swift run`). The ad-hoc code signature applied by `bundle.sh` gives
/// the bundle a stable identity so the registration survives rebuilds.
enum LoginItem {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Turn launch-at-login on or off.
    ///
    /// If macOS requires the user to approve the item in System Settings,
    /// this opens the Login Items pane and returns `false` (not yet enabled).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    return false
                }
                try service.register()
            } else {
                try service.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
