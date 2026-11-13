import XCTest
@testable import SwitcherCore

final class HopLoginGateTests: XCTestCase {
    func acct(_ name: String, token: Bool) -> Account {
        Account(name: name, color: .gray, folder: nil, tokenAddedAt: token ? Date() : nil)
    }

    func testBlockedWhenNoAccountHasToken() {
        XCTAssertNotNil(HopLoginGate.blockReason(accounts: [acct("A", token: false)], initialActive: nil))
    }

    func testBlockedWhenInitialActiveIsNilOrTokenless() {
        let a = acct("A", token: true)
        XCTAssertNotNil(HopLoginGate.blockReason(accounts: [a], initialActive: nil))
        let b = acct("B", token: false)
        XCTAssertNotNil(HopLoginGate.blockReason(accounts: [a, b], initialActive: b.id))
    }

    func testAllowedWhenInitialActiveIsTokenBacked() {
        let a = acct("A", token: true)
        XCTAssertNil(HopLoginGate.blockReason(accounts: [a], initialActive: a.id))
    }
}
