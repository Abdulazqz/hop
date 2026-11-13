import Foundation
import SwitcherCore

enum ActivePointerFile {
    static var url: URL { URL(fileURLWithPath: HopLoginFiles.pointer(home: NSHomeDirectory())) }
}

enum HopHelperScriptFile {
    static var url: URL { URL(fileURLWithPath: HopLoginFiles.helperScript(home: NSHomeDirectory())) }
}

enum BrowserProfileFile {
    /// This account's own browser profile for Get token, kept between runs.
    static func url(for id: UUID) -> URL {
        PrivateBrowser.profileDirectory(for: id, in: AccountStore.defaultURL.deletingLastPathComponent())
    }
}
