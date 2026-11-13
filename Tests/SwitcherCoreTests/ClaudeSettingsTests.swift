import XCTest
@testable import SwitcherCore

final class ClaudeSettingsTests: XCTestCase {
    let helper = "/Users/me/Library/Application Support/Hop/hop-apikeyhelper.sh"
    let ttlKey = "CLAUDE_CODE_API_KEY_HELPER_TTL_MS"

    func nsdict(_ data: Data) -> NSDictionary {
        try! JSONSerialization.jsonObject(with: data) as! NSDictionary
    }

    func testEnablePreservesOtherKeysAndEnvEntries() throws {
        let input = Data(#"{"model":"x","env":{"FOO":"1"}}"#.utf8)
        let out = nsdict(try ClaudeSettings.enableHelper(input, helperPath: helper, ttlMs: 3000))
        XCTAssertEqual(out["model"] as? String, "x")
        XCTAssertEqual(out["apiKeyHelper"] as? String, helper)
        let env = out["env"] as? [String: Any]
        XCTAssertEqual(env?["FOO"] as? String, "1")
        XCTAssertEqual(env?[ttlKey] as? String, "3000")
    }

    func testEnableFromNilStartsFromEmpty() throws {
        let out = nsdict(try ClaudeSettings.enableHelper(nil, helperPath: helper, ttlMs: 3000))
        XCTAssertEqual(out["apiKeyHelper"] as? String, helper)
        XCTAssertEqual((out["env"] as? [String: Any])?[ttlKey] as? String, "3000")
        XCTAssertEqual(out.count, 2)
    }

    func testEnableDisableRoundTripsPreservingEnv() throws {
        let input = Data(#"{"model":"x","env":{"FOO":"1"}}"#.utf8)
        let enabled = try ClaudeSettings.enableHelper(input, helperPath: helper, ttlMs: 3000)
        let disabled = try ClaudeSettings.disableHelper(enabled)
        XCTAssertEqual(nsdict(disabled), nsdict(input))
    }

    func testDisableDropsEnvWhenItBecomesEmpty() throws {
        let enabled = try ClaudeSettings.enableHelper(nil, helperPath: helper, ttlMs: 3000)
        let disabled = try ClaudeSettings.disableHelper(enabled)
        XCTAssertEqual(nsdict(disabled), NSDictionary())
    }

    func testEnableOnInvalidJSONThrows() {
        XCTAssertThrowsError(try ClaudeSettings.enableHelper(Data("not json".utf8), helperPath: helper, ttlMs: 3000))
    }

    func testRewriteDoesNotEscapeSlashes() throws {
        let input = Data(#"{"statusLine":{"command":"/usr/local/bin/status"}}"#.utf8)
        let text = String(decoding: try ClaudeSettings.enableHelper(input, helperPath: helper, ttlMs: 3000), as: UTF8.self)
        XCTAssertFalse(text.contains(#"\/"#), text)
        XCTAssertTrue(text.contains("/usr/local/bin/status"), text)
    }

    func testInvalidJSONHasAReadableMessage() {
        XCTAssertThrowsError(try ClaudeSettings.disableHelper(Data("{,}".utf8))) {
            XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("settings.json") == true)
        }
    }

    func testIsHelperEnabled() throws {
        let enabled = try ClaudeSettings.enableHelper(nil, helperPath: helper, ttlMs: 3000)
        XCTAssertTrue(ClaudeSettings.isHelperEnabled(enabled, helperPath: helper))
        let disabled = try ClaudeSettings.disableHelper(enabled)
        XCTAssertFalse(ClaudeSettings.isHelperEnabled(disabled, helperPath: helper))
    }

    func testForeignHelperDetected() {
        let mine = Data(#"{"apiKeyHelper":"/me/.config/hop/x.sh"}"#.utf8)
        XCTAssertNil(ClaudeSettings.foreignHelper(mine, hopPath: "/me/.config/hop/x.sh"))
        let theirs = Data(#"{"apiKeyHelper":"/usr/local/bin/other.sh"}"#.utf8)
        XCTAssertEqual(ClaudeSettings.foreignHelper(theirs, hopPath: "/me/.config/hop/x.sh"), "/usr/local/bin/other.sh")
        XCTAssertNil(ClaudeSettings.foreignHelper(nil, hopPath: "/me/.config/hop/x.sh"))
    }
}
