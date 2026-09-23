import XCTest
@testable import SwitcherCore

final class AccountValidationTests: XCTestCase {
    let home = "/Users/tester"

    func acct(_ name: String, _ folder: String?) -> Account {
        Account(name: name, color: .gray, folder: folder)
    }

    func testValidSetPasses() throws {
        try AccountValidation.validate([acct("A", nil), acct("B", "~/Library/Application Support/Claude-b")], home: home)
    }

    func testEmptyNameRejected() {
        XCTAssertThrowsError(try AccountValidation.validate([acct("  ", nil)], home: home)) {
            XCTAssertEqual($0 as? AccountValidationError, .emptyName)
        }
    }

    func testDuplicateNameIsCaseInsensitiveAndTrimmed() {
        XCTAssertThrowsError(try AccountValidation.validate([acct("Work", nil), acct("work ", "~/x")], home: home)) {
            XCTAssertEqual($0 as? AccountValidationError, .duplicateName("work"))
        }
    }

    func testDefaultFolderWrittenTwoWaysIsDuplicate() {
        let accounts = [acct("A", nil), acct("B", "~/Library/Application Support/Claude/")]
        XCTAssertThrowsError(try AccountValidation.validate(accounts, home: home)) {
            XCTAssertEqual($0 as? AccountValidationError, .duplicateFolder("~/Library/Application Support/Claude/"))
        }
    }

    func testEmptyFolderIsDuplicateOfDefault() {
        let accounts = [acct("A", nil), acct("B", "")]
        XCTAssertThrowsError(try AccountValidation.validate(accounts, home: home)) {
            XCTAssertEqual($0 as? AccountValidationError, .duplicateFolder(""))
        }
    }

    func testRelativeFolderRejected() {
        XCTAssertThrowsError(try AccountValidation.validate([acct("A", "relative/dir")], home: home)) {
            XCTAssertEqual($0 as? AccountValidationError, .relativeFolder("relative/dir"))
        }
    }

    func testChildFolderInsideDefaultProfileIsOverlapping() {
        let accounts = [acct("A", nil), acct("B", "~/Library/Application Support/Claude/sub")]
        XCTAssertThrowsError(try AccountValidation.validate(accounts, home: home)) {
            XCTAssertEqual($0 as? AccountValidationError,
                           .overlappingFolders("~/Library/Application Support/Claude",
                                               "~/Library/Application Support/Claude/sub"))
        }
    }

    func testDefaultProfileInsideParentFolderIsOverlapping() {
        let accounts = [acct("A", "~/Library/Application Support"), acct("B", nil)]
        XCTAssertThrowsError(try AccountValidation.validate(accounts, home: home)) {
            XCTAssertEqual($0 as? AccountValidationError,
                           .overlappingFolders("~/Library/Application Support",
                                               "~/Library/Application Support/Claude"))
        }
    }

    func testSiblingFoldersSharingAStringPrefixAreNotOverlapping() throws {
        let accounts = [acct("A", nil), acct("B", "~/Library/Application Support/Claude-acct2")]
        try AccountValidation.validate(accounts, home: home)
    }

    func testCodableRoundTrip() throws {
        let account = acct("A", "~/x")
        let data = try JSONEncoder().encode(account)
        XCTAssertEqual(try JSONDecoder().decode(Account.self, from: data), account)
    }

    func testErrorsHaveReadableMessages() {
        XCTAssertEqual(AccountValidationError.duplicateName("Work").errorDescription,
                       "Another account is already called \u{201c}Work\u{201d}.")
    }
}
