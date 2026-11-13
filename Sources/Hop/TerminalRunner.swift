import AppKit

/// Opens a new Terminal.app window running a fixed command. No user input is ever interpolated.
@MainActor
enum TerminalRunner {
    static let bundleID = "com.apple.Terminal"

    enum Command {
        case claude
        var script: String {
            switch self {
            case .claude: "claude"
            }
        }
    }

    /// Returns false when AppleScript failed (usually: Automation permission denied).
    static func open(_ command: Command) -> Bool {
        let source = """
        tell application "Terminal"
            activate
            do script "\(command.script)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Hop: Terminal automation failed: %@", error) }
        return error == nil
    }
}
