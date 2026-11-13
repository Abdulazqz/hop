import Foundation

/// What ⌃⌥1…⌃⌥9 do. Stored in UserDefaults under `defaultsKey`.
public enum HotkeyAction: String, CaseIterable, Codable {
    case off, switchLogin, openClaudeApp, openTerminal

    public static let defaultsKey = "hotkeyAction"
    public static let `default` = HotkeyAction.openClaudeApp

    public var label: String {
        switch self {
        case .off: "Off"
        case .switchLogin: "Switch login"
        case .openClaudeApp: "Open Claude app"
        case .openTerminal: "Open Terminal"
        }
    }
}
