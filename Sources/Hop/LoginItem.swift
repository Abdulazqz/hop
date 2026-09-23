import ServiceManagement

@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    Alerts.show("Allow Hop in System Settings",
                                "Turn it on under Login Items so it opens when you log in.")
                }
            }
        } catch {
            Alerts.show("Couldn't change Launch at login", error.localizedDescription)
        }
    }
}
