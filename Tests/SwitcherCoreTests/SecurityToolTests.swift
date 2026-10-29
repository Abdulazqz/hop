import XCTest
@testable import SwitcherCore

final class SecurityToolTests: XCTestCase {
    let service = "Claude Code-credentials"
    let account = "tester"
    let prefix = "add-generic-password -U -a \"tester\" -s \"Claude Code-credentials\" "

    func testReadAsksForThePasswordOnly() {
        let read = SecurityTool.read(service: service, account: account)
        XCTAssertEqual(read.arguments, ["find-generic-password", "-a", account, "-w", "-s", service])
        XCTAssertNil(read.stdin)
    }

    func testSmallWriteGoesThroughStdinAsHex() throws {
        let write = try SecurityTool.write(Data("{\"a\":1}".utf8), service: service, account: account)
        XCTAssertEqual(write.arguments, ["-i"])
        XCTAssertEqual(write.stdin, prefix + "-X \"7b2261223a317d\"\n")
    }

    func testWriteTooLongForHexGoesThroughStdinAsQuotedText() throws {
        // Hex doubles the size; a login the size of Claude Code's (about 2.4 KB) only fits as text.
        let value = "{\"token\":\"" + String(repeating: "a", count: 2400) + "\",\"path\":\"c:\\\\x\"}"
        let write = try SecurityTool.write(Data(value.utf8), service: service, account: account)
        XCTAssertEqual(write.arguments, ["-i"])
        let escaped = "{\\\"token\\\":\\\"" + String(repeating: "a", count: 2400) + "\\\",\\\"path\\\":\\\"c:\\\\\\\\x\\\"}"
        XCTAssertEqual(write.stdin, prefix + "-w \"" + escaped + "\"\n")
    }

    func testWriteTooLongForStdinIsRefusedRatherThanPutInTheArguments() {
        let big = Data(repeating: 0x61, count: SecurityTool.stdinLineLimit)
        XCTAssertThrowsError(try SecurityTool.write(big, service: service, account: account)) { error in
            XCTAssertTrue(error.localizedDescription.contains("\(big.count) bytes"), "\(error)")
        }
    }

    func testLongValueWithAControlCharacterIsRefused() {
        // Only hex carries a newline, and hex doesn't fit; the text form can't quote it.
        var value = Data(repeating: 0x61, count: 2500)
        value[1000] = 0x0a
        XCTAssertThrowsError(try SecurityTool.write(value, service: service, account: account))
    }

    func testWriteEscapesQuotesInTheAccountName() throws {
        let write = try SecurityTool.write(Data("x".utf8), service: service, account: "o\"brien")
        XCTAssertEqual(write.arguments, ["-i"])
        XCTAssertEqual(write.stdin, "add-generic-password -U -a \"o\\\"brien\" -s \"Claude Code-credentials\" -X \"78\"\n")
    }

    func testWriteRefusesANameItCannotQuote() {
        XCTAssertThrowsError(try SecurityTool.write(Data("x".utf8), service: "a\nb", account: account))
    }

    func testDeleteNamesTheItem() {
        XCTAssertEqual(SecurityTool.delete(service: service, account: account).arguments,
                       ["delete-generic-password", "-a", account, "-s", service])
    }

    func testNotFoundExitReadsAsMissing() throws {
        XCTAssertNil(try SecurityTool.value(exit: SecurityTool.notFoundExit, stdout: Data(), stderr: "not found"))
    }

    func testReadOutputDropsOneTrailingNewline() throws {
        XCTAssertEqual(try SecurityTool.value(exit: 0, stdout: Data("abc\n".utf8), stderr: ""), Data("abc".utf8))
        XCTAssertEqual(try SecurityTool.value(exit: 0, stdout: Data("abc\n\n".utf8), stderr: ""), Data("abc\n".utf8))
    }

    func testEmptyOutputIsAnErrorNotMissing() {
        // An item that exists but yields no data must not read as "missing": rollback would then delete it.
        XCTAssertThrowsError(try SecurityTool.value(exit: 0, stdout: Data(), stderr: ""))
    }

    func testOtherExitCodesThrowWithTheToolsMessage() {
        XCTAssertThrowsError(try SecurityTool.value(exit: 36, stdout: Data(), stderr: "User interaction is not allowed.")) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("User interaction is not allowed"), "\(error)")
        }
    }

    func testDeleteOfAMissingItemIsNotAnError() throws {
        XCTAssertNoThrow(try SecurityTool.checkDelete(exit: SecurityTool.notFoundExit, stderr: "not found"))
        XCTAssertThrowsError(try SecurityTool.checkDelete(exit: 1, stderr: "boom"))
    }

    // MARK: - against the real login keychain (opt in: HOP_KEYCHAIN_TESTS=1)

    private func keychainItem() throws -> SecurityToolItem {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HOP_KEYCHAIN_TESTS"] == "1", "set HOP_KEYCHAIN_TESTS=1 to touch the login keychain")
        return SecurityToolItem(service: "local.hop.test", account: NSUserName(), timeout: 5)
    }

    /// End to end through the tool: write, update, read, delete on the real login keychain. (It can't catch a
    /// revert to a Security-framework write; that mechanism is recorded in the spec's 2026-10-27 revision.)
    func testItemWrittenByHopStaysReadableByTheSecurityTool() throws {
        let item = try keychainItem()
        defer { try? item.delete() }
        try item.write(Data("{\"v\":1}".utf8))
        try item.write(Data("{\"v\":2}".utf8))
        // A dialog would block the tool until the timeout, which surfaces as a thrown error here.
        XCTAssertEqual(try item.read(), Data("{\"v\":2}".utf8))
        try item.delete()
        XCTAssertNil(try item.read())
    }

    /// The text form on stdin, exercised with a value shaped and sized like Claude Code's real login.
    func testALoginTheSizeOfClaudeCodesRoundTripsThroughTheTool() throws {
        let item = try keychainItem()
        defer { try? item.delete() }
        let value = Data(("{\"claudeAiOauth\":{\"accessToken\":\"" + String(repeating: "A", count: 1300)
                          + "\",\"refreshToken\":\"" + String(repeating: "R", count: 1100)
                          + "\",\"expiresAt\":1,\"scopes\":[\"user:inference\"]}}").utf8)
        try item.write(value)
        XCTAssertEqual(try item.read(), value)
    }
}
