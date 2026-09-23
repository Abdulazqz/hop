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

    static func claudeMissing() {
        show("Claude app not found",
             "Hop opens the Claude desktop app, which isn't installed on this Mac. "
             + "Install it from claude.ai/download, then open Hop again.")
    }

    static func terminalAutomationDenied() {
        show("Hop can't open Terminal",
             "Allow Hop to control Terminal in System Settings › Privacy & Security › Automation, then try again.")
    }

    static func logInFirst() {
        show("Log in, then switch once",
             "Terminal is opening so you can run claude auth login. After you log in, switch to any other account once and Hop will save this one.")
    }

    static func switchFailed(_ error: Error) {
        show("Couldn't switch", error.localizedDescription)
    }

    /// Explains that the menu bar is full. Returns `true` if the user asked not to be told again.
    static func hiddenByNotch() -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Hop is running, but its menu bar icon is hidden"
        alert.informativeText = "This Mac's menu bar is full, so macOS put Hop's icon behind the notch, where nothing is drawn. "
            + "Free some space in System Settings (Menu Bar, or Control Center on older macOS) by setting items you don't need "
            + "to \u{201c}Don't Show in Menu Bar\u{201d}. Until then, \u{2303}\u{2325}1 \u{2026} \u{2303}\u{2325}9 still open your accounts by position."
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't tell me again"
        alert.runModal()
        return alert.suppressionButton?.state == .on
    }

    static func recovered() {
        show("Your accounts file couldn't be read",
             "It was saved as accounts.json.bad and replaced with the default three accounts.")
    }
}
