import XCTest
@testable import SwitcherCore

final class TokenStoreTests: XCTestCase {
    func testWriteThenReadRoundTrips() throws {
        let store = FakeTokenStore()
        let id = UUID()
        try store.writeToken("sk-ant-oat01-abc", for: id)
        XCTAssertEqual(try store.readToken(id), "sk-ant-oat01-abc")
    }

    func testReadUnknownIdIsNil() throws {
        XCTAssertNil(try FakeTokenStore().readToken(UUID()))
    }

    func testDeleteRemovesToken() throws {
        let store = FakeTokenStore()
        let id = UUID()
        try store.writeToken("t", for: id)
        try store.deleteToken(id)
        XCTAssertNil(try store.readToken(id))
    }

    func testServiceNameIsHopNamespaced() {
        XCTAssertEqual(TokenStoreConst.service, "local.hop.token")
    }
}
