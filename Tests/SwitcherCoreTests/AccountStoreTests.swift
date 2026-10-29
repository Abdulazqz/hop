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

    func testVersionOneFileLoadsWithNilEmailsAndSavesAsVersionTwo() throws {
        let v1 = """
        {"version":1,"accounts":[{"color":"purple","id":"B3A47827-5F86-4DC6-8003-46C554E7BAEF","name":"Account 1"}]}
        """
        try Data(v1.utf8).write(to: file)
        let loaded = try AccountStore.load(from: file)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded[0].email)
        try AccountStore.save(loaded, to: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("\"version\" : 2"), text)
    }

    func testEmailRoundTrips() throws {
        var one = Account(name: "Work", color: .blue, folder: "~/w")
        one.email = "w@example.com"
        try AccountStore.save([one], to: file)
        XCTAssertEqual(try AccountStore.load(from: file)[0].email, "w@example.com")
    }

    func testSavedLoginExpiryRoundTripsAndIsOptional() throws {
        var one = Account(name: "Work", color: .blue, folder: "~/w", email: "w@example.com")
        one.savedLoginExpiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        try AccountStore.save([one], to: file)
        XCTAssertEqual(try AccountStore.load(from: file)[0].savedLoginExpiresAt, Date(timeIntervalSince1970: 1_800_000_000))
        let v2 = """
        {"version":2,"accounts":[{"color":"teal","id":"AB280B13-F794-44B6-B1F7-C0F32F1ED5D8","name":"Old","email":"o@example.com"}]}
        """
        try Data(v2.utf8).write(to: file)
        XCTAssertNil(try AccountStore.load(from: file)[0].savedLoginExpiresAt)
    }

    func testOrganizationRoundTripsAndIsOptional() throws {
        var one = Account(name: "Work", color: .blue, folder: "~/w", email: "w@example.com")
        one.organizationUuid = "org-1"
        one.organizationName = "One"
        try AccountStore.save([one], to: file)
        let loaded = try AccountStore.load(from: file)[0]
        XCTAssertEqual(loaded.organizationUuid, "org-1")
        XCTAssertEqual(loaded.organizationName, "One")
        let v2 = """
        {"version":2,"accounts":[{"color":"teal","id":"AB280B13-F794-44B6-B1F7-C0F32F1ED5D8","name":"Old","email":"o@example.com"}]}
        """
        try Data(v2.utf8).write(to: file)
        XCTAssertNil(try AccountStore.load(from: file)[0].organizationUuid)
        XCTAssertNil(try AccountStore.load(from: file)[0].organizationName)
    }
}
