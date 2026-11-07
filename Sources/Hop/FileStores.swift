import Foundation
import SwitcherCore

enum HopStateFile {
    static var url: URL { AccountStore.defaultURL.deletingLastPathComponent().appendingPathComponent("state.json") }
}

enum ActivePointerFile {
    static var url: URL { AccountStore.defaultURL.deletingLastPathComponent().appendingPathComponent("active-account") }
}

enum HopHelperScriptFile {
    static var url: URL { AccountStore.defaultURL.deletingLastPathComponent().appendingPathComponent("hop-apikeyhelper.sh") }
}
