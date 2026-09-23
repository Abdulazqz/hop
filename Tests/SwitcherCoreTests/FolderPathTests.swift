import XCTest
@testable import SwitcherCore

final class FolderPathTests: XCTestCase {
    let home = "/Users/tester"

    func testExpandsTilde() {
        XCTAssertEqual(FolderPath.expand("~/Library/X", home: home), "/Users/tester/Library/X")
        XCTAssertEqual(FolderPath.expand("~", home: home), "/Users/tester")
        XCTAssertEqual(FolderPath.expand("/abs/path", home: home), "/abs/path")
    }

    func testNilMeansDefaultProfile() {
        XCTAssertEqual(FolderPath.normalize(nil, home: home), "/Users/tester/Library/Application Support/Claude")
        XCTAssertEqual(FolderPath.normalize(nil, home: home),
                       FolderPath.normalize("~/Library/Application Support/Claude", home: home))
    }

    func testTrailingSlashAndDotsAreIgnored() {
        XCTAssertEqual(FolderPath.normalize("~/Library/Application Support/Claude-acct2/", home: home),
                       FolderPath.normalize("/Users/tester/Library/Application Support/./Claude-acct2", home: home))
    }

    func testDifferentFoldersDiffer() {
        XCTAssertNotEqual(FolderPath.normalize("~/A", home: home), FolderPath.normalize("~/B", home: home))
    }

    func testEmptyOrWhitespaceFolderMeansDefaultProfile() {
        XCTAssertEqual(FolderPath.normalize("", home: home), FolderPath.normalize(nil, home: home))
        XCTAssertEqual(FolderPath.normalize("  ", home: home), FolderPath.normalize(nil, home: home))
    }

    func testIsTrashableAcceptsAClaudeDashFolderInApplicationSupport() {
        XCTAssertTrue(FolderPath.isTrashable("~/Library/Application Support/Claude-work", home: home))
    }

    func testIsTrashableRejectsNilEmptyDefaultAndOutsiders() {
        XCTAssertFalse(FolderPath.isTrashable(nil, home: home))
        XCTAssertFalse(FolderPath.isTrashable("", home: home))
        XCTAssertFalse(FolderPath.isTrashable("~/Library/Application Support/Claude", home: home))
        XCTAssertFalse(FolderPath.isTrashable("~/Library/Application Support", home: home))
        XCTAssertFalse(FolderPath.isTrashable("~/Library/Application Support/Claude-x/..", home: home))
        XCTAssertFalse(FolderPath.isTrashable("~/Library/Application Support/Claude-work/sub", home: home))
        XCTAssertFalse(FolderPath.isTrashable("/tmp/Claude-x", home: home))
        XCTAssertFalse(FolderPath.isTrashable("~/Library/Application Support/Other", home: home))
    }
}
