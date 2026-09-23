import AppKit

enum ClaudeApp {
    static let bundleID = "com.anthropic.claudefordesktop"
    static var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
}
