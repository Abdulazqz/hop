import AppKit

@MainActor
enum TokenPrompt {
    /// Asks the user to paste a setup-token for an account. Returns the raw entered text, or nil if cancelled.
    static func paste(accountName: String) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Setup-token for \u{201c}\(accountName)\u{201d}"
        alert.informativeText = "Run  claude setup-token  signed in as this account, then paste the sk-ant-oat01\u{2026} token here. "
            + "Hop keeps it in the Keychain, never in a file."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-ant-oat01-\u{2026}"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
