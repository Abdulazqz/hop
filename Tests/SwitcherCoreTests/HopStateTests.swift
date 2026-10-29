import XCTest
@testable import SwitcherCore

final class HopStateTests: XCTestCase {
    var dir: URL!
    var file: URL { dir.appendingPathComponent("state.json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testMissingFileIsEmpty() {
        XCTAssertEqual(HopState.load(from: file), .empty)
        XCTAssertNil(HopState.empty.activeAccountID)
    }

    func testCorruptFileIsEmpty() throws {
        try Data("nope".utf8).write(to: file)
        XCTAssertEqual(HopState.load(from: file), .empty)
    }

    func testRoundTrip() throws {
        let id = UUID()
        let state = HopState(activeAccountID: id, writtenRefreshTokenSHA256: "abc")
        try state.save(to: file)
        XCTAssertEqual(HopState.load(from: file), state)
        XCTAssertEqual(HopState.load(from: file).version, 1)
    }
}
