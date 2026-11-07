import Foundation
import SwitcherCore

enum HopStateFile {
    static var url: URL { AccountStore.defaultURL.deletingLastPathComponent().appendingPathComponent("state.json") }
}

enum ActivePointerFile {
    static var url: URL { URL(fileURLWithPath: HopLoginFiles.pointer(home: NSHomeDirectory())) }
}

enum HopHelperScriptFile {
    static var url: URL { URL(fileURLWithPath: HopLoginFiles.helperScript(home: NSHomeDirectory())) }
}
