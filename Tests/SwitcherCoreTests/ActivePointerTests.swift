import XCTest
@testable import SwitcherCore

final class ActivePointerTests: XCTestCase {
    func testContentRoundTrips() {
        let id = UUID()
        XCTAssertEqual(ActivePointer.parse(ActivePointer.content(for: id)), id)
    }

    func testParseTrimsWhitespace() {
        let id = UUID()
        XCTAssertEqual(ActivePointer.parse("  \(id.uuidString)\n"), id)
    }

    func testParseGarbageIsNil() {
        XCTAssertNil(ActivePointer.parse("garbage"))
    }

    func testParseEmptyIsNil() {
        XCTAssertNil(ActivePointer.parse(""))
    }
}
