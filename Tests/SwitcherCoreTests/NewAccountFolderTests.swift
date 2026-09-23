import XCTest
@testable import SwitcherCore

final class NewAccountFolderTests: XCTestCase {
    let home = "/Users/tester"

    func testSlug() {
        XCTAssertEqual(NewAccountFolder.slug("My Work  Acct"), "my-work-acct")
        XCTAssertEqual(NewAccountFolder.slug(" Side_project-2 "), "side-project-2")
        XCTAssertEqual(NewAccountFolder.slug("عمل"), "account")
        XCTAssertEqual(NewAccountFolder.slug("---"), "account")
    }

    func testUsesSlugFolder() {
        XCTAssertEqual(NewAccountFolder.candidate(forName: "Work", accounts: [], home: home, fileExists: { _ in false }),
                       "~/Library/Application Support/Claude-work")
    }

    func testSkipsFoldersClaimedByAccounts() {
        let taken = [Account(name: "Old", color: .gray, folder: "~/Library/Application Support/Claude-work")]
        XCTAssertEqual(NewAccountFolder.candidate(forName: "Work", accounts: taken, home: home, fileExists: { _ in false }),
                       "~/Library/Application Support/Claude-work-2")
    }

    func testExistingOnDiskIsOnlySkippedWhenAsked() {
        let onDisk: (String) -> Bool = { $0 == "/Users/tester/Library/Application Support/Claude-work" }
        XCTAssertEqual(NewAccountFolder.candidate(forName: "Work", accounts: [], home: home, fileExists: onDisk),
                       "~/Library/Application Support/Claude-work")
        XCTAssertEqual(NewAccountFolder.candidate(forName: "Work", accounts: [], home: home,
                                                  skipExistingOnDisk: true, fileExists: onDisk),
                       "~/Library/Application Support/Claude-work-2")
    }
}
