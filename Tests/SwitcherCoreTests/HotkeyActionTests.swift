import XCTest
@testable import SwitcherCore

final class HotkeyActionTests: XCTestCase {
    func testDefaultKeepsTodaysBehavior() {
        XCTAssertEqual(HotkeyAction.default, .openClaudeApp)
    }

    func testLabels() {
        XCTAssertEqual(HotkeyAction.allCases.map(\.label), ["Off", "Switch login", "Open Claude app", "Open Terminal"])
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(HotkeyAction(rawValue: "switchLogin"), .switchLogin)
        XCTAssertEqual(HotkeyAction.defaultsKey, "hotkeyAction")
    }
}
