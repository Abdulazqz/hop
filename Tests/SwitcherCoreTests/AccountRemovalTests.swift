import XCTest
@testable import SwitcherCore

final class AccountRemovalTests: XCTestCase {
    func acct(_ token: Bool) -> Account { Account(name: UUID().uuidString, color: .gray, folder: nil, tokenAddedAt: token ? Date() : nil) }

    func testCollectsOnlyRemovedTokenBackedAccounts() {
        let a = acct(true), b = acct(true), c = acct(false)
        let (removed, clear) = AccountRemoval.cleanup(before: [a, b, c], after: [a], active: a.id)
        XCTAssertEqual(Set(removed), [b.id])   // c had no token, a stayed
        XCTAssertFalse(clear)                  // active account a still present
    }

    func testClearsPointerWhenActiveAccountRemoved() {
        let a = acct(true), b = acct(true)
        let (_, clear) = AccountRemoval.cleanup(before: [a, b], after: [b], active: a.id)
        XCTAssertTrue(clear)
    }

    func testRemovedIDsIncludesAccountsWithoutTokens() {
        let a = acct(true), b = acct(false), c = acct(true)
        XCTAssertEqual(Set(AccountRemoval.removedIDs(before: [a, b, c], after: [a])), [b.id, c.id])
    }

    func testNoClearWhenNothingActive() {
        let a = acct(true)
        let (_, clear) = AccountRemoval.cleanup(before: [a], after: [], active: nil)
        XCTAssertFalse(clear)
    }
}
