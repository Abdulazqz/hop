import AppKit

@MainActor
enum Alerts {
    static func show(_ message: String, _ info: String = "") {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }

    static func recovered() {
        show("Your accounts file couldn't be read",
             "It was saved as accounts.json.bad and replaced with the default three accounts.")
    }
}
