import XCTest
@testable import SwitcherCore

final class AtomicFileTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// The pointer lives in ~/.config/hop, which doesn't exist until something creates it.
    func testCreatesMissingParentDirectory() throws {
        let url = dir.appendingPathComponent("a/b/active-account")
        try AtomicFile.write(Data("x".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "x")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testOverwritesAndAppliesPermissions() throws {
        let url = dir.appendingPathComponent("helper.sh")
        try AtomicFile.write(Data("old".utf8), to: url)
        try AtomicFile.write(Data("new".utf8), to: url, permissions: 0o700)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o700)
    }

    /// A dotfiles-managed settings.json is a symlink; the write must land in the target, keeping the link.
    func testWritesThroughASymlink() throws {
        let real = dir.appendingPathComponent("dotfiles/settings.json")
        try AtomicFile.write(Data("{}".utf8), to: real)
        let link = dir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try AtomicFile.write(Data(#"{"a":1}"#.utf8), to: link)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))
        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8), #"{"a":1}"#)
    }
}
