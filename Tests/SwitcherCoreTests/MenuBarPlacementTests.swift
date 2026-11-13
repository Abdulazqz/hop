import CoreGraphics
import XCTest
@testable import SwitcherCore

final class MenuBarPlacementTests: XCTestCase {
    /// Geometry from a 13" MacBook Air: the area right of the notch starts at x = 825.
    let safeTopRight = CGRect(x: 825, y: 924, width: 645, height: 32)

    func testItemRightOfNotchIsVisible() {
        let frame = CGRect(x: 839, y: 923, width: 38, height: 33)
        XCTAssertFalse(MenuBarPlacement.isHiddenByNotch(itemFrame: frame, safeTopRight: safeTopRight))
    }

    func testItemUnderNotchIsHidden() {
        let frame = CGRect(x: 649, y: 923, width: 38, height: 33)
        XCTAssertTrue(MenuBarPlacement.isHiddenByNotch(itemFrame: frame, safeTopRight: safeTopRight))
    }

    func testItemLeftOfNotchIsHidden() {
        let frame = CGRect(x: 100, y: 923, width: 38, height: 33)
        XCTAssertTrue(MenuBarPlacement.isHiddenByNotch(itemFrame: frame, safeTopRight: safeTopRight))
    }

    func testItemStraddlingSafeEdgeIsHidden() {
        let frame = CGRect(x: 810, y: 923, width: 38, height: 33)
        XCTAssertTrue(MenuBarPlacement.isHiddenByNotch(itemFrame: frame, safeTopRight: safeTopRight))
    }

    func testItemStartingAtSafeEdgeIsVisible() {
        let frame = CGRect(x: 825, y: 923, width: 38, height: 33)
        XCTAssertFalse(MenuBarPlacement.isHiddenByNotch(itemFrame: frame, safeTopRight: safeTopRight))
    }

    func testScreenWithoutNotchNeverHides() {
        let frame = CGRect(x: 100, y: 923, width: 38, height: 33)
        XCTAssertFalse(MenuBarPlacement.isHiddenByNotch(itemFrame: frame, safeTopRight: nil))
    }
}
