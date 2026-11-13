import Foundation
import SwitcherCore

enum ActivePointerFile {
    static var url: URL { URL(fileURLWithPath: HopLoginFiles.pointer(home: NSHomeDirectory())) }
}

enum HopHelperScriptFile {
    static var url: URL { URL(fileURLWithPath: HopLoginFiles.helperScript(home: NSHomeDirectory())) }
}
