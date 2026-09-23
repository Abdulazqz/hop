import XCTest
@testable import SwitcherCore

final class AccountStoreTests: XCTestCase {
    let home = "/Users/tester"
    var dir: URL!
    var file: URL { dir.appendingPathComponent("accounts.json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testSeedIsTheThreeKnownProfiles() {
        let seed = AccountStore.seed()
        XCTAssertEqual(seed.map(\.name), ["Account 1", "Account 2", "Account 3"])
        XCTAssertEqual(seed.map(\.folder), [nil,
                                            "~/Library/Application Support/Claude-acct2",
                                            "~/Library/Application Support/Claude-acct3"])
        XCTAssertNoThrow(try AccountValidation.validate(seed, home: home))
    }

    func testSaveThenLoadRoundTrips() throws {
        let accounts = AccountStore.seed()
        try AccountStore.save(accounts, to: file)
        XCTAssertEqual(try AccountStore.load(from: file), accounts)
    }

    func testMissingFileIsSeededAndWritten() throws {
        let result = AccountStore.loadOrSeed(from: file, home: home)
        XCTAssertFalse(result.recovered)
        XCTAssertEqual(result.accounts.map(\.name), ["Account 1", "Account 2", "Account 3"])
        XCTAssertEqual(try AccountStore.load(from: file), result.accounts)
    }

    func testCorruptFileIsKeptAsBadAndReseeded() throws {
        try Data("not json".utf8).write(to: file)
        let result = AccountStore.loadOrSeed(from: file, home: home)
        XCTAssertTrue(result.recovered)
        XCTAssertEqual(result.accounts.count, 3)
        XCTAssertEqual(try String(contentsOf: file.appendingPathExtension("bad"), encoding: .utf8), "not json")
        XCTAssertEqual(try AccountStore.load(from: file), result.accounts)
    }

    func testInvalidAccountsAreTreatedAsCorrupt() throws {
        let dupes = [Account(name: "A", color: .gray, folder: nil), Account(name: "B", color: .gray, folder: nil)]
        try AccountStore.save(dupes, to: file)
        XCTAssertTrue(AccountStore.loadOrSeed(from: file, home: home).recovered)
    }

    func testValidFileIsReturnedAsIs() throws {
        let one = [Account(name: "Solo", color: .blue, folder: nil)]
        try AccountStore.save(one, to: file)
        let result = AccountStore.loadOrSeed(from: file, home: home)
        XCTAssertFalse(result.recovered)
        XCTAssertEqual(result.accounts, one)
    }
}
