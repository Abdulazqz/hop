import XCTest
@testable import SwitcherCore

final class AccountTokenTests: XCTestCase {
    /// An accounts.json written before Hop stored setup-tokens (v2) has no `tokenAddedAt` key.
    /// The optional must decode to nil, not fail.
    func testDecodesV2AccountWithoutTokenField() throws {
        let json = Data("""
        {"id":"\(UUID().uuidString)","name":"Work","color":"purple"}
        """.utf8)
        let account = try JSONDecoder().decode(Account.self, from: json)
        XCTAssertNil(account.tokenAddedAt)
    }

    func testTokenAddedAtRoundTrips() throws {
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        var account = Account(name: "Work", color: .purple, folder: nil)
        account.tokenAddedAt = date
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        XCTAssertEqual(decoded.tokenAddedAt, date)
        XCTAssertEqual(decoded, account)
    }
}
