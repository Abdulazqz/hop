# Terminal Login Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Hop account switch the machine-wide Claude Code login from the menu bar (or `hop switch N`), open a Terminal on it, or open its desktop profile, while always showing which account is active.

**Architecture:** All rules live in `SwitcherCore` as pure functions and a `SwitchCoordinator` that talks to three tiny protocols (Keychain, the `~/.claude.json` document, Hop's state file), so everything is unit-tested with in-memory fakes. The `Hop` target adds the real stores (Security framework, files), a Terminal runner (AppleScript), a `SwitchController` that glues the coordinator to alerts and the model, and menu/CLI/editor changes. The design is the spec below; read it first.

**Tech Stack:** Swift 5.9 package (`swift build` / `swift test`, XCTest), AppKit + SwiftUI, Security framework, CryptoKit, Carbon hotkeys. macOS 14+.

**Spec:** `docs/superpowers/specs/2026-09-23-terminal-login-switch-design.md`

## Global Constraints

- Platform floor stays `.macOS(.v14)`; no new package dependencies.
- Tokens are never written to files or logs. Tests use fake token strings like `"rt-1"`.
- Hop never performs a login and never "probes" a saved login by using it (a dead token wipes everyone's login).
- Every failure stops before any write; the only write that may need undoing is the Keychain write when the identity write fails afterwards.
- Existing behavior stays the default: hotkeys default to "Open Claude app"; version 1 `accounts.json` files load unchanged; `nil` folder still means the default desktop profile.
- Keychain names: live item service `Claude Code-credentials` (account = macOS user name); saved items service `local.hop.login` (account = the Hop account's UUID string).
- Keys in Claude Code's data: `claudeAiOauth` (Keychain value) and `oauthAccount` (in `~/.claude.json`); `expiresAt` and `refreshTokenExpiresAt` are Unix milliseconds.
- Run the whole suite with `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3` before every commit; it must end with `0 failures`.
- Commit messages: imperative subject, a short body, and end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Work on branch `feat/terminal-login-switch` (already exists, contains the spec).

---

## File map

SwitcherCore (pure, tested):

| File | Responsibility |
|---|---|
| `Sources/SwitcherCore/Account.swift` (modify) | `email` field; `duplicateEmail` validation |
| `Sources/SwitcherCore/AccountStore.swift` (modify) | file version 2 |
| `Sources/SwitcherCore/HotkeyAction.swift` (new) | the four hotkey behaviors |
| `Sources/SwitcherCore/LiveLogin.swift` (new) | parse Claude Code's Keychain value + identity; extract/replace the login section |
| `Sources/SwitcherCore/IdentityDocument.swift` (new) | extract/replace `oauthAccount` in `~/.claude.json`; atomic file write |
| `Sources/SwitcherCore/SavedLogin.swift` (new) | Hop's saved-login item format |
| `Sources/SwitcherCore/HopState.swift` (new) | active account + written-token hash |
| `Sources/SwitcherCore/LoginAttribution.swift` (new) | whose login is live right now |
| `Sources/SwitcherCore/SwitchCoordinator.swift` (new) | the switch procedure over three protocols |
| `Sources/SwitcherCore/MenuModel.swift` (new) | every label, checkmark, and header the menu shows |
| `Sources/SwitcherCore/RunningSessions.swift` (new) | count `claude` processes |

Hop (AppKit):

| File | Responsibility |
|---|---|
| `Sources/Hop/KeychainLoginStore.swift` (new) | `LoginStore` over the Security framework |
| `Sources/Hop/FileStores.swift` (new) | `IdentityDocumentFile`, `HopStateFile` |
| `Sources/Hop/TerminalRunner.swift` (new) | open Terminal.app running a command |
| `Sources/Hop/UnknownLoginDialog.swift` (new) | "Save the current login as…" dialog |
| `Sources/Hop/SwitchController.swift` (new) | coordinator + alerts + persistence + terminal |
| `Sources/Hop/MenuController.swift` (modify) | submenus, header, checkmark, icon color, Hotkeys submenu |
| `Sources/Hop/AppDelegate.swift` (modify) | wiring, hotkey setting |
| `Sources/Hop/EditAccountsWindow.swift` (modify) | email column, Forget saved login, delete on remove |
| `Sources/Hop/CLI.swift` (modify) | `switch <n>`, richer `status` |
| `Sources/Hop/Alerts.swift` (modify) | new alerts |
| `Resources/Info.plist`, `build.sh`, `README.md` (modify) | permission text, `~/bin/hop`, docs |

---

### Task 1: Account email and file version 2

**Files:**
- Modify: `Sources/SwitcherCore/Account.swift`
- Modify: `Sources/SwitcherCore/AccountStore.swift`
- Test: `Tests/SwitcherCoreTests/AccountValidationTests.swift`, `Tests/SwitcherCoreTests/AccountStoreTests.swift`

**Interfaces:**
- Produces: `Account.email: String?` (new stored property; `init(id:name:color:folder:email:)` with `email` defaulting to `nil`), `AccountValidationError.duplicateEmail(String)`, `AccountStore.currentVersion == 2`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwitcherCoreTests/AccountValidationTests.swift` inside the class:

```swift
    func testDuplicateEmailIsCaseInsensitiveAndTrimmed() {
        var a = acct("A", nil); a.email = "Me@Example.com"
        var b = acct("B", "~/x"); b.email = " me@example.com "
        XCTAssertThrowsError(try AccountValidation.validate([a, b], home: home)) {
            XCTAssertEqual($0 as? AccountValidationError, .duplicateEmail("me@example.com"))
        }
    }

    func testAccountsWithoutEmailNeverCollide() throws {
        try AccountValidation.validate([acct("A", nil), acct("B", "~/x"), acct("C", "~/y")], home: home)
    }
```

Append to `Tests/SwitcherCoreTests/AccountStoreTests.swift` inside the class:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter 'AccountValidationTests|AccountStoreTests' 2>&1 | grep -E "error:|failed|passed" | head`
Expected: compile errors mentioning `email` and `duplicateEmail`.

- [ ] **Step 3: Implement**

In `Sources/SwitcherCore/Account.swift` replace the `Account` struct with:

```swift
public struct Account: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: AccountColor
    /// Claude profile folder passed as --user-data-dir, stored with "~". `nil` = default profile.
    public var folder: String?
    /// claude.ai identity, set once a terminal login has been captured for this account.
    public var email: String?

    public init(id: UUID = UUID(), name: String, color: AccountColor, folder: String?, email: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.folder = folder
        self.email = email
    }

    /// Lower-cased, trimmed email for comparisons; nil when unset or blank.
    public var normalizedEmail: String? {
        guard let email else { return nil }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

Add to `AccountValidationError`: a case `duplicateEmail(String)` and in `errorDescription`:

```swift
        case .duplicateEmail(let email): return "Two accounts use the login \(email). Each account needs its own."
```

In `AccountValidation.validate`, add `var emails = Set<String>()` next to `names`, and inside the loop, right after the duplicate-name check:

```swift
            if let email = account.normalizedEmail, !emails.insert(email).inserted {
                throw AccountValidationError.duplicateEmail(email)
            }
```

In `Sources/SwitcherCore/AccountStore.swift` change `public static let currentVersion = 1` to `= 2`. Nothing else: `AccountsFile` decodes any version and `email` is optional, so version 1 files load unchanged.

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: all tests pass, `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/Account.swift Sources/SwitcherCore/AccountStore.swift Tests/SwitcherCoreTests/AccountValidationTests.swift Tests/SwitcherCoreTests/AccountStoreTests.swift
git commit -m "Give accounts an optional email and bump accounts.json to version 2

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: HotkeyAction

**Files:**
- Create: `Sources/SwitcherCore/HotkeyAction.swift`
- Test: `Tests/SwitcherCoreTests/HotkeyActionTests.swift`

**Interfaces:**
- Produces: `public enum HotkeyAction: String, CaseIterable, Codable { case off, switchLogin, openClaudeApp, openTerminal }`, `var label: String`, `static let defaultsKey = "hotkeyAction"`, `static let `default` = HotkeyAction.openClaudeApp`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import SwitcherCore

final class HotkeyActionTests: XCTestCase {
    func testDefaultKeepsTodaysBehavior() {
        XCTAssertEqual(HotkeyAction.default, .openClaudeApp)
    }

    func testLabels() {
        XCTAssertEqual(HotkeyAction.allCases.map(\.label), ["Off", "Switch login", "Open Claude app", "Open Terminal"])
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(HotkeyAction(rawValue: "switchLogin"), .switchLogin)
        XCTAssertEqual(HotkeyAction.defaultsKey, "hotkeyAction")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter HotkeyActionTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'HotkeyAction' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// What ⌃⌥1…⌃⌥9 do. Stored in UserDefaults under `defaultsKey`.
public enum HotkeyAction: String, CaseIterable, Codable {
    case off, switchLogin, openClaudeApp, openTerminal

    public static let defaultsKey = "hotkeyAction"
    public static let `default` = HotkeyAction.openClaudeApp

    public var label: String {
        switch self {
        case .off: "Off"
        case .switchLogin: "Switch login"
        case .openClaudeApp: "Open Claude app"
        case .openTerminal: "Open Terminal"
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/HotkeyAction.swift Tests/SwitcherCoreTests/HotkeyActionTests.swift
git commit -m "Add HotkeyAction setting values

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: LiveLogin parsing and login-section merge

**Files:**
- Create: `Sources/SwitcherCore/LiveLogin.swift`
- Create: `Tests/SwitcherCoreTests/LoginFixtures.swift`
- Test: `Tests/SwitcherCoreTests/LiveLoginTests.swift`

**Interfaces:**
- Produces:
  - `public struct LoginSummary: Equatable { email, refreshTokenSHA256: String; expiresAt, refreshTokenExpiresAt: Date }`
  - `public enum LiveLoginState: Equatable { case loggedIn(LoginSummary), loggedOut, unrecognized(String) }`
  - `LiveLogin.parse(keychainValue: Data?, identityDocument: Data?) -> LiveLoginState`
  - `LiveLogin.loginSection(of keychainValue: Data) throws -> Data` (the `claudeAiOauth` object alone)
  - `LiveLogin.replacingLoginSection(in keychainValue: Data?, with section: Data) throws -> Data` (nil base = new object)
  - `LiveLogin.refreshTokenExpiry(ofLoginSection: Data) -> Date?`, `LiveLogin.refreshTokenSHA256(ofLoginSection: Data) -> String?`
  - `LiveLogin.sha256Hex(_ string: String) -> String`
  - `LiveLogin.LoginError: Error, Equatable { case notAnObject, missingLoginSection }`
  - Test helper `LoginFixtures.keychainValue(...)` and `LoginFixtures.identityDocument(...)` used by later tasks.

- [ ] **Step 1: Write the fixtures and failing tests**

`Tests/SwitcherCoreTests/LoginFixtures.swift`:

```swift
import Foundation

/// Builds Claude Code-shaped data with fake tokens. Never real credentials.
enum LoginFixtures {
    /// 2100-01-01 in Unix ms: comfortably in the future.
    static let farFuture: Double = 4_102_444_800_000

    static func keychainValue(access: String = "at-1", refresh: String = "rt-1",
                              expiresAt: Double = farFuture, refreshTokenExpiresAt: Double = farFuture,
                              extra: [String: Any] = ["mcpOAuth": ["srv|1": ["accessToken": "m-1"]]]) -> Data {
        var object = extra
        object["claudeAiOauth"] = ["accessToken": access, "refreshToken": refresh, "expiresAt": expiresAt,
                                   "refreshTokenExpiresAt": refreshTokenExpiresAt, "scopes": ["user:inference"],
                                   "subscriptionType": "max", "rateLimitTier": "default"] as [String: Any]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func identityDocument(email: String? = "a@example.com", extra: [String: Any] = ["numStartups": 3]) -> Data {
        var object = extra
        if let email {
            object["oauthAccount"] = ["emailAddress": email, "organizationName": "Org", "accountUuid": "acc-\(email)"]
        }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func json(_ data: Data) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
```

`Tests/SwitcherCoreTests/LiveLoginTests.swift`:

```swift
import XCTest
@testable import SwitcherCore

final class LiveLoginTests: XCTestCase {
    func testValidLoginIsSummarized() {
        let state = LiveLogin.parse(keychainValue: LoginFixtures.keychainValue(refresh: "rt-7"),
                                    identityDocument: LoginFixtures.identityDocument(email: "Me@Example.com"))
        guard case .loggedIn(let s) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(s.email, "Me@Example.com")
        XCTAssertEqual(s.refreshTokenSHA256, LiveLogin.sha256Hex("rt-7"))
        XCTAssertEqual(s.expiresAt, Date(timeIntervalSince1970: LoginFixtures.farFuture / 1000))
        XCTAssertEqual(s.refreshTokenExpiresAt, Date(timeIntervalSince1970: LoginFixtures.farFuture / 1000))
    }

    func testMissingItemIsLoggedOut() {
        XCTAssertEqual(LiveLogin.parse(keychainValue: nil, identityDocument: LoginFixtures.identityDocument()), .loggedOut)
    }

    func testExpiresAtZeroIsLoggedOut() {
        let wiped = LoginFixtures.keychainValue(expiresAt: 0)
        XCTAssertEqual(LiveLogin.parse(keychainValue: wiped, identityDocument: LoginFixtures.identityDocument()), .loggedOut)
    }

    func testEmptyTokensAreLoggedOut() {
        let empty = LoginFixtures.keychainValue(access: "", refresh: "")
        XCTAssertEqual(LiveLogin.parse(keychainValue: empty, identityDocument: LoginFixtures.identityDocument()), .loggedOut)
    }

    func testValueWithoutLoginKeyIsUnrecognized() {
        let odd = try! JSONSerialization.data(withJSONObject: ["somethingElse": 1])
        guard case .unrecognized = LiveLogin.parse(keychainValue: odd, identityDocument: LoginFixtures.identityDocument()) else {
            return XCTFail("expected unrecognized")
        }
    }

    func testNonJSONValueIsUnrecognized() {
        guard case .unrecognized = LiveLogin.parse(keychainValue: Data("nope".utf8), identityDocument: nil) else {
            return XCTFail("expected unrecognized")
        }
    }

    func testTokensWithoutIdentityEmailAreUnrecognized() {
        guard case .unrecognized = LiveLogin.parse(keychainValue: LoginFixtures.keychainValue(),
                                                   identityDocument: LoginFixtures.identityDocument(email: nil)) else {
            return XCTFail("expected unrecognized")
        }
    }

    func testTokensWithUnreadableIdentityDocumentAreUnrecognized() {
        guard case .unrecognized = LiveLogin.parse(keychainValue: LoginFixtures.keychainValue(),
                                                   identityDocument: Data("{broken".utf8)) else {
            return XCTFail("expected unrecognized")
        }
    }

    func testLoginSectionExtractsOnlyTheOAuthObject() throws {
        let section = try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: "rt-2"))
        let object = LoginFixtures.json(section)
        XCTAssertEqual(object["refreshToken"] as? String, "rt-2")
        XCTAssertNil(object["mcpOAuth"])
    }

    func testReplacingLoginSectionKeepsEveryOtherKey() throws {
        let base = LoginFixtures.keychainValue(refresh: "rt-old", extra: ["mcpOAuth": ["x": 1], "futureKey": "keep"])
        let section = try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: "rt-new"))
        let merged = LoginFixtures.json(try LiveLogin.replacingLoginSection(in: base, with: section))
        XCTAssertEqual((merged["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String, "rt-new")
        XCTAssertEqual((merged["mcpOAuth"] as? [String: Any])?["x"] as? Int, 1)
        XCTAssertEqual(merged["futureKey"] as? String, "keep")
    }

    func testReplacingLoginSectionWithNoBaseMakesAFreshObject() throws {
        let section = try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: "rt-new"))
        let merged = LoginFixtures.json(try LiveLogin.replacingLoginSection(in: nil, with: section))
        XCTAssertEqual(Array(merged.keys), ["claudeAiOauth"])
    }

    func testSectionHelpers() throws {
        let section = try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: "rt-3", refreshTokenExpiresAt: 1_000))
        XCTAssertEqual(LiveLogin.refreshTokenExpiry(ofLoginSection: section), Date(timeIntervalSince1970: 1))
        XCTAssertEqual(LiveLogin.refreshTokenSHA256(ofLoginSection: section), LiveLogin.sha256Hex("rt-3"))
        XCTAssertNil(LiveLogin.refreshTokenExpiry(ofLoginSection: Data("[]".utf8)))
    }

    func testSha256IsHexOfUTF8() {
        XCTAssertEqual(LiveLogin.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter LiveLoginTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'LiveLogin' in scope`.

- [ ] **Step 3: Implement `Sources/SwitcherCore/LiveLogin.swift`**

```swift
import CryptoKit
import Foundation

/// What Claude Code's shared terminal login looks like right now.
public struct LoginSummary: Equatable {
    public let email: String
    public let refreshTokenSHA256: String
    public let expiresAt: Date
    public let refreshTokenExpiresAt: Date

    public init(email: String, refreshTokenSHA256: String, expiresAt: Date, refreshTokenExpiresAt: Date) {
        self.email = email
        self.refreshTokenSHA256 = refreshTokenSHA256
        self.expiresAt = expiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }
}

public enum LiveLoginState: Equatable {
    case loggedIn(LoginSummary)
    case loggedOut
    /// The data isn't shaped the way Hop knows. The string says what was wrong; Hop touches nothing.
    case unrecognized(String)
}

/// Reads and rewrites the value of Claude Code's Keychain item ("Claude Code-credentials").
/// Only the `claudeAiOauth` object is ever replaced; every other key is carried over untouched.
public enum LiveLogin {
    public static let loginKey = "claudeAiOauth"
    public static let identityKey = "oauthAccount"
    public static let emailKey = "emailAddress"

    public enum LoginError: Error, Equatable {
        case notAnObject
        case missingLoginSection
    }

    public static func parse(keychainValue: Data?, identityDocument: Data?) -> LiveLoginState {
        guard let keychainValue else { return .loggedOut }
        guard let object = jsonObject(keychainValue) else { return .unrecognized("the Keychain item isn't a JSON object") }
        guard let login = object[loginKey] as? [String: Any] else { return .unrecognized("no \(loginKey) section") }
        let access = login["accessToken"] as? String ?? ""
        let refresh = login["refreshToken"] as? String ?? ""
        let expiresAt = millis(login["expiresAt"])
        if access.isEmpty || refresh.isEmpty || expiresAt == nil || expiresAt == 0 { return .loggedOut }
        guard let refreshExpiresAt = millis(login["refreshTokenExpiresAt"]) else {
            return .unrecognized("\(loginKey) has no refreshTokenExpiresAt")
        }
        guard let identityDocument, let document = jsonObject(identityDocument) else {
            return .unrecognized("~/.claude.json is missing or isn't valid JSON")
        }
        guard let identity = document[identityKey] as? [String: Any],
              let email = identity[emailKey] as? String, !email.isEmpty else {
            return .unrecognized("~/.claude.json has no \(identityKey).\(emailKey)")
        }
        return .loggedIn(LoginSummary(email: email, refreshTokenSHA256: sha256Hex(refresh),
                                      expiresAt: Date(timeIntervalSince1970: expiresAt! / 1000),
                                      refreshTokenExpiresAt: Date(timeIntervalSince1970: refreshExpiresAt / 1000)))
    }

    public static func loginSection(of keychainValue: Data) throws -> Data {
        guard let object = jsonObject(keychainValue) else { throw LoginError.notAnObject }
        guard let login = object[loginKey] as? [String: Any] else { throw LoginError.missingLoginSection }
        return try JSONSerialization.data(withJSONObject: login)
    }

    public static func replacingLoginSection(in keychainValue: Data?, with section: Data) throws -> Data {
        var object: [String: Any] = [:]
        if let keychainValue {
            guard let existing = jsonObject(keychainValue) else { throw LoginError.notAnObject }
            object = existing
        }
        guard let login = jsonObject(section) else { throw LoginError.notAnObject }
        object[loginKey] = login
        return try JSONSerialization.data(withJSONObject: object)
    }

    public static func refreshTokenExpiry(ofLoginSection section: Data) -> Date? {
        guard let login = jsonObject(section), let ms = millis(login["refreshTokenExpiresAt"]) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    public static func refreshTokenSHA256(ofLoginSection section: Data) -> String? {
        guard let login = jsonObject(section), let refresh = login["refreshToken"] as? String, !refresh.isEmpty else { return nil }
        return sha256Hex(refresh)
    }

    public static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - helpers

    static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func millis(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/LiveLogin.swift Tests/SwitcherCoreTests/LoginFixtures.swift Tests/SwitcherCoreTests/LiveLoginTests.swift
git commit -m "Parse Claude Code's live login and merge only its login section

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: IdentityDocument merge and atomic file write

**Files:**
- Create: `Sources/SwitcherCore/IdentityDocument.swift`
- Test: `Tests/SwitcherCoreTests/IdentityDocumentTests.swift`

**Interfaces:**
- Produces:
  - `IdentityDocument.identity(of document: Data) throws -> Data?` (the `oauthAccount` object alone; nil if absent)
  - `IdentityDocument.email(inIdentity identity: Data) -> String?`
  - `IdentityDocument.replacingIdentity(in document: Data?, with identity: Data) throws -> Data` (nil = `{}`)
  - `IdentityDocument.DocumentError: Error, Equatable { case notAnObject }`
  - `AtomicFile.write(_ data: Data, to url: URL) throws` (temp file in same directory, mode 0600, rename)

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SwitcherCore

final class IdentityDocumentTests: XCTestCase {
    func testIdentityExtractsOnlyTheAccountObject() throws {
        let identity = try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: "x@y.z")))
        let object = LoginFixtures.json(identity)
        XCTAssertEqual(object["emailAddress"] as? String, "x@y.z")
        XCTAssertNil(object["numStartups"])
        XCTAssertEqual(IdentityDocument.email(inIdentity: identity), "x@y.z")
    }

    func testMissingIdentityIsNil() throws {
        XCTAssertNil(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: nil)))
    }

    func testNotAnObjectThrows() {
        XCTAssertThrowsError(try IdentityDocument.identity(of: Data("[1]".utf8))) {
            XCTAssertEqual($0 as? IdentityDocument.DocumentError, .notAnObject)
        }
        XCTAssertThrowsError(try IdentityDocument.replacingIdentity(in: Data("{broken".utf8), with: Data("{}".utf8)))
    }

    func testReplacingIdentityPreservesEveryOtherKey() throws {
        let document = LoginFixtures.identityDocument(email: "old@example.com",
                                                      extra: ["numStartups": 3, "cachedThing": ["deep": true]])
        let newIdentity = try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: "new@example.com")))
        let merged = LoginFixtures.json(try IdentityDocument.replacingIdentity(in: document, with: newIdentity))
        XCTAssertEqual((merged["oauthAccount"] as? [String: Any])?["emailAddress"] as? String, "new@example.com")
        XCTAssertEqual(merged["numStartups"] as? Int, 3)
        XCTAssertEqual((merged["cachedThing"] as? [String: Any])?["deep"] as? Bool, true)
    }

    func testReplacingIdentityInMissingDocumentStartsEmpty() throws {
        let identity = try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument()))
        let merged = LoginFixtures.json(try IdentityDocument.replacingIdentity(in: nil, with: identity))
        XCTAssertEqual(Array(merged.keys), ["oauthAccount"])
    }

    func testAtomicWriteReplacesContentAndRestrictsMode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("doc.json")
        try Data("old".utf8).write(to: url)
        try AtomicFile.write(Data("new".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["doc.json"], "no temp file left behind")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter IdentityDocumentTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'IdentityDocument' in scope`.

- [ ] **Step 3: Implement `Sources/SwitcherCore/IdentityDocument.swift`**

```swift
import Foundation

/// Claude Code's `~/.claude.json`. Hop only ever touches its `oauthAccount` object.
public enum IdentityDocument {
    public enum DocumentError: Error, Equatable {
        case notAnObject
    }

    public static func identity(of document: Data) throws -> Data? {
        guard let object = LiveLogin.jsonObject(document) else { throw DocumentError.notAnObject }
        guard let identity = object[LiveLogin.identityKey] as? [String: Any] else { return nil }
        return try JSONSerialization.data(withJSONObject: identity)
    }

    public static func email(inIdentity identity: Data) -> String? {
        guard let object = LiveLogin.jsonObject(identity), let email = object[LiveLogin.emailKey] as? String,
              !email.isEmpty else { return nil }
        return email
    }

    public static func replacingIdentity(in document: Data?, with identity: Data) throws -> Data {
        var object: [String: Any] = [:]
        if let document {
            guard let existing = LiveLogin.jsonObject(document) else { throw DocumentError.notAnObject }
            object = existing
        }
        guard let identityObject = LiveLogin.jsonObject(identity) else { throw DocumentError.notAnObject }
        object[LiveLogin.identityKey] = identityObject
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}

/// Write-to-temp-then-rename, so readers never see a half-written file.
public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).hop-\(UUID().uuidString)")
        try data.write(to: temp, options: [])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}
```

Note: `replaceItemAt` handles the case where `url` doesn't exist yet on APFS; if the test for a missing target ever matters, `moveItem` is the fallback. The tests above only cover an existing target.

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: `0 failures`. If `testAtomicWriteReplacesContentAndRestrictsMode` fails on the mode, check whether `replaceItemAt` preserved the original's permissions instead of the temp's: then `setAttributes` on `url` after the replace.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/IdentityDocument.swift Tests/SwitcherCoreTests/IdentityDocumentTests.swift
git commit -m "Replace only oauthAccount in ~/.claude.json, atomically

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: SavedLogin item format

**Files:**
- Create: `Sources/SwitcherCore/SavedLogin.swift`
- Test: `Tests/SwitcherCoreTests/SavedLoginTests.swift`

**Interfaces:**
- Produces:
  - `public struct SavedLogin: Equatable { public static let formatVersion = 1; public let loginSection: Data; public let identity: Data; public let capturedAt: Date; init(loginSection:identity:capturedAt:) }`
  - computed `email: String?`, `refreshTokenExpiresAt: Date?`, `refreshTokenSHA256: String?`
  - `func encoded() throws -> Data`, `static func decode(_ data: Data) throws -> SavedLogin`
  - `SavedLogin.FormatError: Error, Equatable { case notAnObject, unsupportedVersion(Int), missingField(String) }`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SwitcherCore

final class SavedLoginTests: XCTestCase {
    let captured = Date(timeIntervalSince1970: 1_800_000_000)

    func sample(refresh: String = "rt-s", refreshExpiresAt: Double = LoginFixtures.farFuture) throws -> SavedLogin {
        SavedLogin(loginSection: try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: refresh, refreshTokenExpiresAt: refreshExpiresAt)),
                   identity: try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: "s@example.com"))),
                   capturedAt: captured)
    }

    func testRoundTrip() throws {
        let saved = try sample()
        let decoded = try SavedLogin.decode(try saved.encoded())
        XCTAssertEqual(decoded.email, "s@example.com")
        XCTAssertEqual(decoded.capturedAt.timeIntervalSince1970, captured.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.refreshTokenSHA256, LiveLogin.sha256Hex("rt-s"))
        XCTAssertEqual(LoginFixtures.json(decoded.loginSection)["refreshToken"] as? String, "rt-s")
    }

    func testEncodedShape() throws {
        let object = LoginFixtures.json(try sample().encoded())
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertNotNil(object["claudeAiOauth"] as? [String: Any])
        XCTAssertNotNil(object["oauthAccount"] as? [String: Any])
        XCTAssertNotNil(object["capturedAt"] as? String)
    }

    func testDerivedValues() throws {
        XCTAssertEqual(try sample(refreshExpiresAt: 2_000).refreshTokenExpiresAt, Date(timeIntervalSince1970: 2))
    }

    func testRejectsUnsupportedVersionAndMissingFields() throws {
        let future = try JSONSerialization.data(withJSONObject: ["version": 9, "claudeAiOauth": [:], "oauthAccount": [:], "capturedAt": "x"])
        XCTAssertThrowsError(try SavedLogin.decode(future)) { XCTAssertEqual($0 as? SavedLogin.FormatError, .unsupportedVersion(9)) }
        let missing = try JSONSerialization.data(withJSONObject: ["version": 1, "oauthAccount": [:], "capturedAt": "x"])
        XCTAssertThrowsError(try SavedLogin.decode(missing)) { XCTAssertEqual($0 as? SavedLogin.FormatError, .missingField("claudeAiOauth")) }
        XCTAssertThrowsError(try SavedLogin.decode(Data("[]".utf8))) { XCTAssertEqual($0 as? SavedLogin.FormatError, .notAnObject) }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter SavedLoginTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'SavedLogin' in scope`.

- [ ] **Step 3: Implement `Sources/SwitcherCore/SavedLogin.swift`**

```swift
import Foundation

/// The value Hop stores in its own Keychain items: one captured terminal login plus its identity.
public struct SavedLogin: Equatable {
    public static let formatVersion = 1

    public let loginSection: Data   // the claudeAiOauth object, serialized
    public let identity: Data       // the oauthAccount object, serialized
    public let capturedAt: Date

    public init(loginSection: Data, identity: Data, capturedAt: Date) {
        self.loginSection = loginSection
        self.identity = identity
        self.capturedAt = capturedAt
    }

    public enum FormatError: Error, Equatable {
        case notAnObject
        case unsupportedVersion(Int)
        case missingField(String)
    }

    public var email: String? { IdentityDocument.email(inIdentity: identity) }
    public var refreshTokenExpiresAt: Date? { LiveLogin.refreshTokenExpiry(ofLoginSection: loginSection) }
    public var refreshTokenSHA256: String? { LiveLogin.refreshTokenSHA256(ofLoginSection: loginSection) }

    public func encoded() throws -> Data {
        guard let login = LiveLogin.jsonObject(loginSection), let identityObject = LiveLogin.jsonObject(identity) else {
            throw FormatError.notAnObject
        }
        let object: [String: Any] = [
            "version": Self.formatVersion,
            LiveLogin.loginKey: login,
            LiveLogin.identityKey: identityObject,
            "capturedAt": ISO8601DateFormatter().string(from: capturedAt),
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    public static func decode(_ data: Data) throws -> SavedLogin {
        guard let object = LiveLogin.jsonObject(data) else { throw FormatError.notAnObject }
        let version = (object["version"] as? NSNumber)?.intValue ?? 0
        guard version == formatVersion else { throw FormatError.unsupportedVersion(version) }
        guard let login = object[LiveLogin.loginKey] as? [String: Any] else { throw FormatError.missingField(LiveLogin.loginKey) }
        guard let identity = object[LiveLogin.identityKey] as? [String: Any] else { throw FormatError.missingField(LiveLogin.identityKey) }
        guard let stamp = object["capturedAt"] as? String else { throw FormatError.missingField("capturedAt") }
        return SavedLogin(loginSection: try JSONSerialization.data(withJSONObject: login),
                          identity: try JSONSerialization.data(withJSONObject: identity),
                          capturedAt: ISO8601DateFormatter().date(from: stamp) ?? .distantPast)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/SavedLogin.swift Tests/SwitcherCoreTests/SavedLoginTests.swift
git commit -m "Define the saved-login Keychain item format

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: HopState

**Files:**
- Create: `Sources/SwitcherCore/HopState.swift`
- Test: `Tests/SwitcherCoreTests/HopStateTests.swift`

**Interfaces:**
- Produces: `public struct HopState: Codable, Equatable { var version = 1; var activeAccountID: UUID?; var writtenRefreshTokenSHA256: String?; init(activeAccountID: UUID? = nil, writtenRefreshTokenSHA256: String? = nil); static let empty; static func load(from url: URL) -> HopState; func save(to url: URL) throws }`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter HopStateTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'HopState' in scope`.

- [ ] **Step 3: Implement `Sources/SwitcherCore/HopState.swift`**

```swift
import Foundation

/// What Hop last did to the shared login. Lets Hop recognize its own write later without storing the token.
public struct HopState: Codable, Equatable {
    public var version: Int = 1
    public var activeAccountID: UUID?
    public var writtenRefreshTokenSHA256: String?

    public init(activeAccountID: UUID? = nil, writtenRefreshTokenSHA256: String? = nil) {
        self.activeAccountID = activeAccountID
        self.writtenRefreshTokenSHA256 = writtenRefreshTokenSHA256
    }

    public static let empty = HopState()

    /// Missing or unreadable state means "Hop hasn't switched yet".
    public static func load(from url: URL) -> HopState {
        guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(HopState.self, from: data) else {
            return .empty
        }
        return state
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/HopState.swift Tests/SwitcherCoreTests/HopStateTests.swift
git commit -m "Record which account Hop last activated

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: LoginAttribution

**Files:**
- Create: `Sources/SwitcherCore/LoginAttribution.swift`
- Test: `Tests/SwitcherCoreTests/LoginAttributionTests.swift`

**Interfaces:**
- Produces: `public enum LoginAttribution: Equatable { case hopWrote(UUID), emailMatch(UUID), unknown(email: String); static func attribute(_ live: LoginSummary, accounts: [Account], state: HopState) -> LoginAttribution; var accountID: UUID? }`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SwitcherCore

final class LoginAttributionTests: XCTestCase {
    let work = Account(name: "Work", color: .teal, folder: "~/w", email: "work@example.com")
    let home = Account(name: "Home", color: .blue, folder: "~/h", email: "home@example.com")
    func live(email: String, refresh: String = "rt") -> LoginSummary {
        LoginSummary(email: email, refreshTokenSHA256: LiveLogin.sha256Hex(refresh), expiresAt: .distantFuture, refreshTokenExpiresAt: .distantFuture)
    }

    func testHashMatchBeatsEmail() {
        let state = HopState(activeAccountID: work.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt"))
        XCTAssertEqual(LoginAttribution.attribute(live(email: "home@example.com"), accounts: [work, home], state: state), .hopWrote(work.id))
    }

    func testHashMatchForUnknownAccountFallsBackToEmail() {
        let state = HopState(activeAccountID: UUID(), writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt"))
        XCTAssertEqual(LoginAttribution.attribute(live(email: "home@example.com"), accounts: [work, home], state: state), .emailMatch(home.id))
    }

    func testEmailMatchIsCaseInsensitive() {
        XCTAssertEqual(LoginAttribution.attribute(live(email: "WORK@example.com"), accounts: [work, home], state: .empty), .emailMatch(work.id))
    }

    func testUnknownEmail() {
        let result = LoginAttribution.attribute(live(email: "new@example.com"), accounts: [work], state: .empty)
        XCTAssertEqual(result, .unknown(email: "new@example.com"))
        XCTAssertNil(result.accountID)
        XCTAssertEqual(LoginAttribution.emailMatch(work.id).accountID, work.id)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter LoginAttributionTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'LoginAttribution' in scope`.

- [ ] **Step 3: Implement `Sources/SwitcherCore/LoginAttribution.swift`**

```swift
import Foundation

/// Which Hop account the live terminal login belongs to.
public enum LoginAttribution: Equatable {
    /// The token is the one Hop last wrote, so it belongs to that account even if a stale session rewrote the identity file.
    case hopWrote(UUID)
    case emailMatch(UUID)
    case unknown(email: String)

    public var accountID: UUID? {
        switch self {
        case .hopWrote(let id), .emailMatch(let id): id
        case .unknown: nil
        }
    }

    public static func attribute(_ live: LoginSummary, accounts: [Account], state: HopState) -> LoginAttribution {
        if let hash = state.writtenRefreshTokenSHA256, hash == live.refreshTokenSHA256,
           let id = state.activeAccountID, accounts.contains(where: { $0.id == id }) {
            return .hopWrote(id)
        }
        let wanted = live.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let match = accounts.first(where: { $0.normalizedEmail == wanted }) {
            return .emailMatch(match.id)
        }
        return .unknown(email: live.email)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/LoginAttribution.swift Tests/SwitcherCoreTests/LoginAttributionTests.swift
git commit -m "Attribute the live login to an account

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: SwitchCoordinator

**Files:**
- Create: `Sources/SwitcherCore/SwitchCoordinator.swift`
- Create: `Tests/SwitcherCoreTests/FakeStores.swift`
- Test: `Tests/SwitcherCoreTests/SwitchCoordinatorTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public protocol LoginStore {
      func readLive() throws -> Data?
      func writeLive(_ value: Data) throws
      func readSaved(_ accountID: UUID) throws -> Data?
      func writeSaved(_ value: Data, for accountID: UUID) throws
      func deleteSaved(_ accountID: UUID) throws
  }
  public protocol IdentityDocumentStore {
      func read() throws -> Data?
      func write(_ document: Data) throws
  }
  public enum UnknownLoginChoice: Equatable { case attach(UUID), create }
  public enum SwitchError: Error, Equatable, LocalizedError {
      case unrecognizedLogin(String), targetHasNoLogin(String), targetLoginExpired(name: String, on: Date),
           alreadyActive(String), cancelled(email: String), store(String), rolledBack(String)
  }
  public struct SwitchResult: Equatable { public let from: UUID?; public let to: UUID; public let accounts: [Account]; public let state: HopState }
  public struct SwitchCoordinator {
      public init(logins: LoginStore, identityDocument: IdentityDocumentStore, home: String, now: @escaping () -> Date = Date.init)
      public func switchTo(_ targetID: UUID, accounts: [Account], state: HopState,
                           resolveUnknown: (String) -> UnknownLoginChoice?) throws -> SwitchResult
      public func saveCurrentLogin(accounts: [Account], state: HopState, choice: UnknownLoginChoice) throws -> (accounts: [Account], state: HopState)
      public func savedLoginExpiry(for accounts: [Account]) -> [UUID: Date]
      public static func newAccount(email: String, accounts: [Account], home: String) -> Account
  }
  ```

- [ ] **Step 1: Write the fakes and failing tests**

`Tests/SwitcherCoreTests/FakeStores.swift`:

```swift
import Foundation
@testable import SwitcherCore

final class FakeLoginStore: LoginStore {
    var live: Data?
    var saved: [UUID: Data] = [:]
    var liveWrites: [Data] = []
    var failLiveWrite = false
    func readLive() throws -> Data? { live }
    func writeLive(_ value: Data) throws {
        if failLiveWrite { throw SwitchError.store("keychain write failed") }
        live = value; liveWrites.append(value)
    }
    func readSaved(_ accountID: UUID) throws -> Data? { saved[accountID] }
    func writeSaved(_ value: Data, for accountID: UUID) throws { saved[accountID] = value }
    func deleteSaved(_ accountID: UUID) throws { saved[accountID] = nil }
}

final class FakeIdentityStore: IdentityDocumentStore {
    var document: Data?
    var failWrite = false
    var writes = 0
    func read() throws -> Data? { document }
    func write(_ document: Data) throws {
        if failWrite { throw SwitchError.store("disk full") }
        self.document = document; writes += 1
    }
}
```

`Tests/SwitcherCoreTests/SwitchCoordinatorTests.swift`:

```swift
import XCTest
@testable import SwitcherCore

final class SwitchCoordinatorTests: XCTestCase {
    let home = "/Users/tester"
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var logins: FakeLoginStore!
    var identity: FakeIdentityStore!
    var coordinator: SwitchCoordinator!
    var work: Account!
    var play: Account!

    override func setUp() {
        logins = FakeLoginStore()
        identity = FakeIdentityStore()
        coordinator = SwitchCoordinator(logins: logins, identityDocument: identity, home: home) { [now] in now }
        work = Account(name: "Work", color: .teal, folder: "~/w", email: "work@example.com")
        play = Account(name: "Play", color: .coral, folder: "~/p", email: "play@example.com")
    }

    /// Live login = `email` with refresh token `refresh`; identity document carries the same email.
    func setLive(email: String, refresh: String) {
        logins.live = LoginFixtures.keychainValue(refresh: refresh, extra: ["mcpOAuth": ["srv": ["accessToken": "m"]]])
        identity.document = LoginFixtures.identityDocument(email: email, extra: ["numStartups": 7])
    }

    func save(_ account: Account, refresh: String, refreshExpiresAt: Double = LoginFixtures.farFuture) throws {
        let saved = SavedLogin(loginSection: try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: refresh, refreshTokenExpiresAt: refreshExpiresAt)),
                               identity: try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: account.email))),
                               capturedAt: now)
        logins.saved[account.id] = try saved.encoded()
    }

    func testHappyPathSavesOutgoingAndWritesTarget() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in XCTFail("no dialog"); return nil }
        XCTAssertEqual(result.from, work.id)
        XCTAssertEqual(result.to, play.id)
        // outgoing saved under Work with its live identity
        let savedWork = try SavedLogin.decode(try XCTUnwrap(logins.saved[work.id]))
        XCTAssertEqual(savedWork.refreshTokenSHA256, LiveLogin.sha256Hex("rt-work"))
        XCTAssertEqual(savedWork.email, "work@example.com")
        // live now holds Play's login section, mcpOAuth preserved
        let live = LoginFixtures.json(try XCTUnwrap(logins.live))
        XCTAssertEqual((live["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String, "rt-play")
        XCTAssertNotNil(live["mcpOAuth"])
        // identity document: only oauthAccount replaced
        let doc = LoginFixtures.json(try XCTUnwrap(identity.document))
        XCTAssertEqual((doc["oauthAccount"] as? [String: Any])?["emailAddress"] as? String, "play@example.com")
        XCTAssertEqual(doc["numStartups"] as? Int, 7)
        // state records the write
        XCTAssertEqual(result.state, HopState(activeAccountID: play.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt-play")))
        XCTAssertEqual(result.accounts, [work, play])
    }

    func testAlreadyActiveWritesNothing() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        try save(work, refresh: "rt-old")
        XCTAssertThrowsError(try coordinator.switchTo(work.id, accounts: [work, play], state: .empty) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .alreadyActive("Work"))
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
        XCTAssertEqual(identity.writes, 0)
    }

    func testTargetWithoutSavedLoginIsRefusedBeforeSaving() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .targetHasNoLogin("Play"))
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testExpiredTargetIsRefusedWithDate() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        let past = (now.timeIntervalSince1970 - 10) * 1000
        try save(play, refresh: "rt-play", refreshExpiresAt: past)
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .targetLoginExpired(name: "Play", on: Date(timeIntervalSince1970: now.timeIntervalSince1970 - 10)))
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testUnknownEmailCancelledWritesNothing() throws {
        setLive(email: "new@example.com", refresh: "rt-new")
        try save(play, refresh: "rt-play")
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .cancelled(email: "new@example.com"))
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
        XCTAssertTrue(logins.saved[work.id] == nil)
    }

    func testUnknownEmailCreatesAccountWithFolder() throws {
        setLive(email: "new@example.com", refresh: "rt-new")
        try save(play, refresh: "rt-play")
        var asked: String?
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { email in asked = email; return .create }
        XCTAssertEqual(asked, "new@example.com")
        XCTAssertEqual(result.accounts.count, 3)
        let created = result.accounts[2]
        XCTAssertEqual(created.name, "new@example.com")
        XCTAssertEqual(created.email, "new@example.com")
        XCTAssertEqual(created.folder, "~/Library/Application Support/Claude-newexamplecom")
        XCTAssertEqual(result.from, created.id)
        XCTAssertNotNil(logins.saved[created.id])
        XCTAssertNoThrow(try AccountValidation.validate(result.accounts, home: home))
    }

    func testUnknownEmailAttachesToAccountWithoutEmail() throws {
        let bare = Account(name: "Third", color: .gray, folder: "~/t")
        setLive(email: "new@example.com", refresh: "rt-new")
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [work, play, bare], state: .empty) { _ in .attach(bare.id) }
        XCTAssertEqual(result.accounts[2].email, "new@example.com")
        XCTAssertNotNil(logins.saved[bare.id])
        XCTAssertEqual(result.from, bare.id)
    }

    func testLoggedOutSkipsCapture() throws {
        logins.live = nil
        identity.document = LoginFixtures.identityDocument(email: nil)
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }
        XCTAssertNil(result.from)
        XCTAssertEqual(LoginFixtures.json(try XCTUnwrap(logins.live)).keys.sorted(), ["claudeAiOauth"])
        XCTAssertEqual((LoginFixtures.json(try XCTUnwrap(identity.document))["oauthAccount"] as? [String: Any])?["emailAddress"] as? String, "play@example.com")
    }

    func testUnrecognizedShapeStops() throws {
        logins.live = Data("{\"weird\":1}".utf8)
        identity.document = LoginFixtures.identityDocument()
        try save(play, refresh: "rt-play")
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            guard case .unrecognizedLogin = $0 as? SwitchError else { return XCTFail("\($0)") }
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testHopWroteHashSavesUnderStateAccountWithItsOwnIdentity() throws {
        // Hop wrote Work's token; a stale session then rewrote the identity file as Play.
        setLive(email: "play@example.com", refresh: "rt-work")
        try save(work, refresh: "rt-work")   // Work's saved identity = work@example.com
        try save(play, refresh: "rt-play")
        let state = HopState(activeAccountID: work.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt-work"))
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: state) { _ in nil }
        XCTAssertEqual(result.from, work.id)
        XCTAssertEqual(try SavedLogin.decode(try XCTUnwrap(logins.saved[work.id])).email, "work@example.com")
    }

    func testIdentityWriteFailureRestoresKeychain() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        let before = logins.live
        try save(play, refresh: "rt-play")
        identity.failWrite = true
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            guard case .rolledBack = $0 as? SwitchError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(logins.live, before)
        XCTAssertEqual(logins.liveWrites.count, 2, "target write then restore")
    }

    func testSaveCurrentLoginWithoutSwitching() throws {
        setLive(email: "new@example.com", refresh: "rt-new")
        let (accounts, state) = try coordinator.saveCurrentLogin(accounts: [work], state: .empty, choice: .create)
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(state.activeAccountID, accounts[1].id)
        XCTAssertEqual(state.writtenRefreshTokenSHA256, LiveLogin.sha256Hex("rt-new"))
        XCTAssertTrue(logins.liveWrites.isEmpty)
        XCTAssertNotNil(logins.saved[accounts[1].id])
    }

    func testSavedLoginExpiry() throws {
        try save(play, refresh: "rt-play", refreshExpiresAt: 5_000)
        XCTAssertEqual(coordinator.savedLoginExpiry(for: [work, play]), [play.id: Date(timeIntervalSince1970: 5)])
    }

    func testNewAccountPicksUnusedColor() {
        let account = SwitchCoordinator.newAccount(email: "x@example.com", accounts: [work, play], home: home)
        XCTAssertEqual(account.color, .purple)
        XCTAssertEqual(account.folder, "~/Library/Application Support/Claude-xexamplecom")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter SwitchCoordinatorTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find type 'LoginStore' in scope`.

- [ ] **Step 3: Implement `Sources/SwitcherCore/SwitchCoordinator.swift`**

```swift
import Foundation

public protocol LoginStore {
    /// Claude Code's own item; nil when it doesn't exist.
    func readLive() throws -> Data?
    func writeLive(_ value: Data) throws
    func readSaved(_ accountID: UUID) throws -> Data?
    func writeSaved(_ value: Data, for accountID: UUID) throws
    func deleteSaved(_ accountID: UUID) throws
}

public protocol IdentityDocumentStore {
    /// `~/.claude.json`; nil when the file doesn't exist.
    func read() throws -> Data?
    func write(_ document: Data) throws
}

public enum UnknownLoginChoice: Equatable {
    case attach(UUID)
    case create
}

public enum SwitchError: Error, Equatable, LocalizedError {
    case unrecognizedLogin(String)
    case targetHasNoLogin(String)
    case targetLoginExpired(name: String, on: Date)
    case alreadyActive(String)
    case cancelled(email: String)
    case store(String)
    case rolledBack(String)

    public var errorDescription: String? {
        switch self {
        case .unrecognizedLogin(let why): "Claude Code's login format changed (\(why)). Hop won't touch it."
        case .targetHasNoLogin(let name): "\(name) has no saved terminal login yet. Log in as it once, then switch to any other account so Hop can save it."
        case .targetLoginExpired(let name, let on):
            "\(name)'s saved login expired on \(on.formatted(date: .abbreviated, time: .omitted)). Log in as it once in Terminal."
        case .alreadyActive(let name): "\(name) is already the active account."
        case .cancelled(let email): "The current login (\(email)) isn't saved. Save it first, or the switch would lose it."
        case .store(let why): why
        case .rolledBack(let why): "Couldn't finish the switch (\(why)). The previous login was restored."
        }
    }
}

public struct SwitchResult: Equatable {
    public let from: UUID?
    public let to: UUID
    public let accounts: [Account]
    public let state: HopState
}

/// The switch procedure from the spec. Pure apart from the two stores it is given.
public struct SwitchCoordinator {
    private let logins: LoginStore
    private let identityDocument: IdentityDocumentStore
    private let home: String
    private let now: () -> Date

    public init(logins: LoginStore, identityDocument: IdentityDocumentStore, home: String, now: @escaping () -> Date = Date.init) {
        self.logins = logins
        self.identityDocument = identityDocument
        self.home = home
        self.now = now
    }

    public func switchTo(_ targetID: UUID, accounts: [Account], state: HopState,
                         resolveUnknown: (String) -> UnknownLoginChoice?) throws -> SwitchResult {
        guard let target = accounts.first(where: { $0.id == targetID }) else { throw SwitchError.store("unknown account") }
        // 1. Read everything before writing anything.
        let liveValue = try logins.readLive()
        let document = try identityDocument.read()
        let live = LiveLogin.parse(keychainValue: liveValue, identityDocument: document)
        if case .unrecognized(let why) = live { throw SwitchError.unrecognizedLogin(why) }

        // 3 (early). The target must be usable, so a refused switch never captures anything either.
        guard let savedData = try logins.readSaved(targetID) else { throw SwitchError.targetHasNoLogin(target.name) }
        let saved = try SavedLogin.decode(savedData)
        guard let refreshExpiry = saved.refreshTokenExpiresAt else { throw SwitchError.unrecognizedLogin("saved login has no expiry") }
        if refreshExpiry <= now().addingTimeInterval(60) { throw SwitchError.targetLoginExpired(name: target.name, on: refreshExpiry) }

        // 2. Attribute and save the outgoing login.
        var accounts = accounts
        var from: UUID?
        if case .loggedIn(let summary) = live, let liveValue, let document {
            let (outgoingID, updated) = try captureLive(summary: summary, liveValue: liveValue, document: document,
                                                        accounts: accounts, state: state, resolveUnknown: resolveUnknown)
            accounts = updated
            from = outgoingID
            if outgoingID == targetID { throw SwitchError.alreadyActive(target.name) }
        }

        // 4. Write: Keychain, then identity; undo the Keychain if the identity write fails.
        let newLive = try LiveLogin.replacingLoginSection(in: liveValue, with: saved.loginSection)
        let newDocument = try IdentityDocument.replacingIdentity(in: document, with: saved.identity)
        try logins.writeLive(newLive)
        do {
            try identityDocument.write(newDocument)
        } catch {
            if let liveValue { try? logins.writeLive(liveValue) }
            throw SwitchError.rolledBack(error.localizedDescription)
        }
        let newState = HopState(activeAccountID: targetID, writtenRefreshTokenSHA256: saved.refreshTokenSHA256)
        return SwitchResult(from: from, to: targetID, accounts: accounts, state: newState)
    }

    /// Menu action "Save current login as…": capture without switching.
    public func saveCurrentLogin(accounts: [Account], state: HopState, choice: UnknownLoginChoice) throws -> (accounts: [Account], state: HopState) {
        let liveValue = try logins.readLive()
        let document = try identityDocument.read()
        guard case .loggedIn(let summary) = LiveLogin.parse(keychainValue: liveValue, identityDocument: document),
              let liveValue, let document else {
            throw SwitchError.unrecognizedLogin("nothing is logged in")
        }
        let (id, updated) = try captureLive(summary: summary, liveValue: liveValue, document: document,
                                            accounts: accounts, state: state, resolveUnknown: { _ in choice })
        return (updated, HopState(activeAccountID: id, writtenRefreshTokenSHA256: summary.refreshTokenSHA256))
    }

    public func savedLoginExpiry(for accounts: [Account]) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for account in accounts {
            if let data = try? logins.readSaved(account.id), let saved = try? SavedLogin.decode(data), let expiry = saved.refreshTokenExpiresAt {
                result[account.id] = expiry
            }
        }
        return result
    }

    public static func newAccount(email: String, accounts: [Account], home: String) -> Account {
        let used = Set(accounts.map(\.color))
        let color = AccountColor.allCases.first { !used.contains($0) } ?? .gray
        let folder = NewAccountFolder.candidate(forName: email, accounts: accounts, home: home)
        return Account(name: email, color: color, folder: folder, email: email)
    }

    // MARK: - capture

    /// Saves the live login under the account it belongs to, creating or attaching when unknown.
    /// Returns that account's id and the (possibly extended) account list.
    private func captureLive(summary: LoginSummary, liveValue: Data, document: Data, accounts: [Account], state: HopState,
                             resolveUnknown: (String) -> UnknownLoginChoice?) throws -> (UUID, [Account]) {
        var accounts = accounts
        let section = try LiveLogin.loginSection(of: liveValue)
        var identity = try IdentityDocument.identity(of: document) ?? Data("{}".utf8)
        let outgoingID: UUID
        switch LoginAttribution.attribute(summary, accounts: accounts, state: state) {
        case .hopWrote(let id):
            outgoingID = id
            // A stale session may have rewritten the identity file; prefer the identity we saved for this account.
            if let data = try logins.readSaved(id), let previous = try? SavedLogin.decode(data),
               previous.email?.lowercased() != summary.email.lowercased() {
                identity = previous.identity
            }
        case .emailMatch(let id):
            outgoingID = id
        case .unknown(let email):
            switch resolveUnknown(email) {
            case .attach(let id)?:
                guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw SwitchError.store("unknown account") }
                accounts[index].email = email
                outgoingID = id
            case .create?:
                let created = Self.newAccount(email: email, accounts: accounts, home: home)
                accounts.append(created)
                outgoingID = created.id
            case nil:
                throw SwitchError.cancelled(email: email)
            }
        }
        if let index = accounts.firstIndex(where: { $0.id == outgoingID }), accounts[index].email == nil {
            accounts[index].email = summary.email
        }
        let saved = SavedLogin(loginSection: section, identity: identity, capturedAt: now())
        try logins.writeSaved(try saved.encoded(), for: outgoingID)
        return (outgoingID, accounts)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: `0 failures`. If `testUnknownEmailCreatesAccountWithFolder` fails on the folder string, check `NewAccountFolder.slug("new@example.com")`: `@` and `.` are dropped, giving `newexamplecom`. Adjust the expectation only if the slug function's documented behavior differs.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/SwitchCoordinator.swift Tests/SwitcherCoreTests/FakeStores.swift Tests/SwitcherCoreTests/SwitchCoordinatorTests.swift
git commit -m "Add the switch procedure over Keychain and identity-file protocols

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: MenuModel

**Files:**
- Create: `Sources/SwitcherCore/MenuModel.swift`
- Test: `Tests/SwitcherCoreTests/MenuModelTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum SwitchLabel: Equatable { case active, switchLogin, logInFirst }
  public enum TerminalLabel: Equatable { case openTerminal, logInFirst }
  public struct MenuRow: Equatable { accountID: UUID; title: String; hint: String?; isActive: Bool; desktopRunning: Bool;
                                     switchLabel: SwitchLabel; terminalLabel: TerminalLabel; desktopLabel: String }
  public struct MenuModel: Equatable {
      header: String; sessionsLine: String?; rows: [MenuRow]; saveCurrentLoginEmail: String?; activeAccountID: UUID?
      static func build(accounts: [Account], live: LiveLoginState, state: HopState, savedLoginExpiry: [UUID: Date],
                        hasSavedLogin: Set<UUID>, desktopRunning: Set<UUID>, runningSessions: Int,
                        hotkeyAction: HotkeyAction, hotkeyPositions: Set<Int>, now: Date) -> MenuModel
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SwitcherCore

final class MenuModelTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let work = Account(name: "Work", color: .teal, folder: "~/w", email: "work@example.com")
    let play = Account(name: "Play", color: .coral, folder: "~/p", email: "play@example.com")
    let bare = Account(name: "Bare", color: .gray, folder: "~/b")

    func live(_ email: String, refresh: String = "rt") -> LiveLoginState {
        .loggedIn(LoginSummary(email: email, refreshTokenSHA256: LiveLogin.sha256Hex(refresh), expiresAt: .distantFuture, refreshTokenExpiresAt: .distantFuture))
    }

    func build(live: LiveLoginState, state: HopState = .empty, expiry: [UUID: Date] = [:], saved: Set<UUID>? = nil,
               running: Set<UUID> = [], sessions: Int = 0, hotkeys: HotkeyAction = .openClaudeApp, positions: Set<Int> = [0, 1, 2]) -> MenuModel {
        MenuModel.build(accounts: [work, play, bare], live: live, state: state, savedLoginExpiry: expiry,
                        hasSavedLogin: saved ?? [work.id, play.id], desktopRunning: running, runningSessions: sessions,
                        hotkeyAction: hotkeys, hotkeyPositions: positions, now: now)
    }

    func testHeaderAndCheckmarkFollowTheLiveEmail() {
        let model = build(live: live("play@example.com"))
        XCTAssertEqual(model.header, "Active: Play (play@example.com)")
        XCTAssertEqual(model.activeAccountID, play.id)
        XCTAssertEqual(model.rows.map(\.isActive), [false, true, false])
        XCTAssertEqual(model.rows[1].switchLabel, .active)
        XCTAssertEqual(model.rows[0].switchLabel, .switchLogin)
        XCTAssertNil(model.saveCurrentLoginEmail)
    }

    func testHopsOwnWriteWinsOverARewrittenIdentity() {
        let state = HopState(activeAccountID: work.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt"))
        let model = build(live: live("play@example.com"), state: state)
        XCTAssertEqual(model.activeAccountID, work.id)
        XCTAssertEqual(model.header, "Active: Work (work@example.com)")
    }

    func testUnknownLoginOffersToSaveIt() {
        let model = build(live: live("new@example.com"))
        XCTAssertNil(model.activeAccountID)
        XCTAssertEqual(model.header, "Active: new@example.com (not saved)")
        XCTAssertEqual(model.saveCurrentLoginEmail, "new@example.com")
        XCTAssertTrue(model.rows.allSatisfy { !$0.isActive })
    }

    func testLoggedOutAndUnrecognized() {
        XCTAssertEqual(build(live: .loggedOut).header, "Not logged in")
        XCTAssertEqual(build(live: .unrecognized("x")).header, "Login format not recognized")
        XCTAssertNil(build(live: .loggedOut).saveCurrentLoginEmail)
    }

    func testAccountWithoutSavedLoginSaysLogInFirst() {
        let model = build(live: live("work@example.com"))
        XCTAssertEqual(model.rows[2].switchLabel, .logInFirst)
        XCTAssertEqual(model.rows[2].terminalLabel, .logInFirst)
        XCTAssertEqual(model.rows[0].terminalLabel, .openTerminal)
    }

    func testDesktopLabelsAndRunningFlag() {
        let model = build(live: live("work@example.com"), running: [play.id])
        XCTAssertEqual(model.rows[1].desktopLabel, "Bring Claude app to front")
        XCTAssertEqual(model.rows[0].desktopLabel, "Open Claude app")
        XCTAssertTrue(model.rows[1].desktopRunning)
    }

    func testSessionsLine() {
        XCTAssertNil(build(live: .loggedOut).sessionsLine)
        XCTAssertEqual(build(live: .loggedOut, sessions: 1).sessionsLine, "1 terminal session running · it follows within 8 hours")
        XCTAssertEqual(build(live: .loggedOut, sessions: 3).sessionsLine, "3 terminal sessions running · they follow within 8 hours")
    }

    func testExpirySuffixOnlyWithinSevenDays() {
        let soon = now.addingTimeInterval(3 * 86_400 + 60)
        let far = now.addingTimeInterval(30 * 86_400)
        let gone = now.addingTimeInterval(-60)
        let model = build(live: .loggedOut, expiry: [work.id: soon, play.id: far, bare.id: gone])
        XCTAssertEqual(model.rows[0].title, "Work · login expires in 3 days")
        XCTAssertEqual(model.rows[1].title, "Play")
        XCTAssertEqual(model.rows[2].title, "Bare · login expired")
    }

    func testHintsFollowHotkeySetting() {
        XCTAssertEqual(build(live: .loggedOut).rows.map(\.hint), ["⌃⌥1", "⌃⌥2", "⌃⌥3"])
        XCTAssertEqual(build(live: .loggedOut, hotkeys: .off).rows.map(\.hint), [nil, nil, nil])
        XCTAssertEqual(build(live: .loggedOut, positions: [0]).rows.map(\.hint), ["⌃⌥1", nil, nil])
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter MenuModelTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'MenuModel' in scope`.

- [ ] **Step 3: Implement `Sources/SwitcherCore/MenuModel.swift`**

```swift
import Foundation

public enum SwitchLabel: Equatable { case active, switchLogin, logInFirst }
public enum TerminalLabel: Equatable { case openTerminal, logInFirst }

public struct MenuRow: Equatable {
    public let accountID: UUID
    public let title: String
    public let hint: String?
    public let isActive: Bool
    public let desktopRunning: Bool
    public let switchLabel: SwitchLabel
    public let terminalLabel: TerminalLabel
    public let desktopLabel: String
}

/// Everything the status menu shows, computed without AppKit so it can be tested.
public struct MenuModel: Equatable {
    public let header: String
    public let sessionsLine: String?
    public let rows: [MenuRow]
    /// Set when the live login matches no account: show "Save current login (email) as new account…".
    public let saveCurrentLoginEmail: String?
    public let activeAccountID: UUID?

    public static func build(accounts: [Account], live: LiveLoginState, state: HopState, savedLoginExpiry: [UUID: Date],
                             hasSavedLogin: Set<UUID>, desktopRunning: Set<UUID>, runningSessions: Int,
                             hotkeyAction: HotkeyAction, hotkeyPositions: Set<Int>, now: Date) -> MenuModel {
        var activeID: UUID?
        var unknownEmail: String?
        let header: String
        switch live {
        case .loggedIn(let summary):
            let attribution = LoginAttribution.attribute(summary, accounts: accounts, state: state)
            activeID = attribution.accountID
            if let activeID, let account = accounts.first(where: { $0.id == activeID }) {
                header = "Active: \(account.name) (\(account.email ?? summary.email))"
            } else {
                unknownEmail = summary.email
                header = "Active: \(summary.email) (not saved)"
            }
        case .loggedOut:
            header = "Not logged in"
        case .unrecognized:
            header = "Login format not recognized"
        }

        let rows = accounts.enumerated().map { position, account -> MenuRow in
            let isActive = account.id == activeID
            let running = desktopRunning.contains(account.id)
            let saved = hasSavedLogin.contains(account.id)
            return MenuRow(
                accountID: account.id,
                title: account.name + expirySuffix(savedLoginExpiry[account.id], now: now),
                hint: hotkeyAction != .off && hotkeyPositions.contains(position) ? "⌃⌥\(position + 1)" : nil,
                isActive: isActive,
                desktopRunning: running,
                switchLabel: isActive ? .active : (saved ? .switchLogin : .logInFirst),
                terminalLabel: saved ? .openTerminal : .logInFirst,
                desktopLabel: running ? "Bring Claude app to front" : "Open Claude app")
        }

        let sessionsLine: String? = runningSessions == 0 ? nil
            : runningSessions == 1 ? "1 terminal session running · it follows within 8 hours"
            : "\(runningSessions) terminal sessions running · they follow within 8 hours"

        return MenuModel(header: header, sessionsLine: sessionsLine, rows: rows,
                         saveCurrentLoginEmail: unknownEmail, activeAccountID: activeID)
    }

    static func expirySuffix(_ expiry: Date?, now: Date) -> String {
        guard let expiry else { return "" }
        let seconds = expiry.timeIntervalSince(now)
        if seconds <= 0 { return " · login expired" }
        let days = Int(seconds / 86_400)
        return days < 7 ? " · login expires in \(days) day\(days == 1 ? "" : "s")" : ""
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/MenuModel.swift Tests/SwitcherCoreTests/MenuModelTests.swift
git commit -m "Compute the status menu's labels and active account without AppKit

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: RunningSessions

**Files:**
- Create: `Sources/SwitcherCore/RunningSessions.swift`
- Test: `Tests/SwitcherCoreTests/RunningSessionsTests.swift`

**Interfaces:**
- Produces: `RunningSessions.count(processNames: [String]) -> Int` (pure filter) and `RunningSessions.count() -> Int` (lists this user's processes with libproc).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SwitcherCore

final class RunningSessionsTests: XCTestCase {
    func testCountsOnlyProcessesNamedClaude() {
        XCTAssertEqual(RunningSessions.count(processNames: ["claude", "Claude", "node", "claude", "claude-helper"]), 2)
    }

    func testLiveCountDoesNotCrash() {
        XCTAssertGreaterThanOrEqual(RunningSessions.count(), 0)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter RunningSessionsTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'RunningSessions' in scope`.

- [ ] **Step 3: Implement `Sources/SwitcherCore/RunningSessions.swift`**

```swift
import Darwin
import Foundation

/// How many Claude Code terminal sessions this user is running. A hint for the menu, nothing more.
public enum RunningSessions {
    public static let processName = "claude"

    public static func count(processNames: [String]) -> Int {
        processNames.filter { $0 == processName }.count
    }

    public static func count() -> Int {
        let uid = getuid()
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), uid, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return 0 }
        let found = Int(bytes) / MemoryLayout<pid_t>.size
        var names: [String] = []
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for pid in pids.prefix(found) where pid > 0 {
            if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
                names.append(String(cString: buffer))
            }
        }
        return count(processNames: names)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: `0 failures`. If `proc_listpids` or `proc_name` is not visible, add `import Darwin.libproc` isn't a module; instead the symbols come from `<libproc.h>` which Swift exposes through `Darwin` on macOS. If they still fail to resolve, create `Sources/SwitcherCore/include/libproc_shim.h` containing `#include <libproc.h>` with a module map, or fall back to `sysctl(KERN_PROC, KERN_PROC_UID)` reading `kp_proc.p_comm`; either is acceptable as long as the two tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/RunningSessions.swift Tests/SwitcherCoreTests/RunningSessionsTests.swift
git commit -m "Count running claude terminal sessions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: Real stores in the Hop target

**Files:**
- Create: `Sources/Hop/KeychainLoginStore.swift`
- Create: `Sources/Hop/FileStores.swift`
- Modify: `Sources/Hop/CLI.swift` (add a hidden `probe-login` command used only to smoke-test the stores)

**Interfaces:**
- Produces: `final class KeychainLoginStore: LoginStore`, `struct IdentityDocumentFile: IdentityDocumentStore`, `enum HopStateFile { static var url: URL }`, `struct KeychainError: LocalizedError { let status: OSStatus }`.

There are no unit tests for this task (it is the Security framework); the deliverable is verified with the smoke command below and again in Task 17.

- [ ] **Step 1: Implement `Sources/Hop/KeychainLoginStore.swift`**

```swift
import Foundation
import Security
import SwitcherCore

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
    }
}

/// Claude Code's live login item plus Hop's own saved-login items, via the Security framework.
final class KeychainLoginStore: LoginStore {
    static let liveService = "Claude Code-credentials"
    static let savedService = "local.hop.login"

    func readLive() throws -> Data? { try read(service: Self.liveService, account: NSUserName()) }
    func writeLive(_ value: Data) throws { try write(value, service: Self.liveService, account: NSUserName()) }
    func readSaved(_ accountID: UUID) throws -> Data? { try read(service: Self.savedService, account: accountID.uuidString) }
    func writeSaved(_ value: Data, for accountID: UUID) throws { try write(value, service: Self.savedService, account: accountID.uuidString) }
    func deleteSaved(_ accountID: UUID) throws { try delete(service: Self.savedService, account: accountID.uuidString) }

    private func query(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func read(service: String, account: String) throws -> Data? {
        var q = query(service: service, account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    private func write(_ data: Data, service: String, account: String) throws {
        let q = query(service: service, account: account)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
            return
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func delete(service: String, account: String) throws {
        let status = SecItemDelete(query(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
```

- [ ] **Step 2: Implement `Sources/Hop/FileStores.swift`**

```swift
import Foundation
import SwitcherCore

/// `~/.claude.json`, the file Claude Code keeps its identity block in.
struct IdentityDocumentFile: IdentityDocumentStore {
    let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")

    func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func write(_ document: Data) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try AtomicFile.write(document, to: url)
        } else {
            try document.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

enum HopStateFile {
    static var url: URL { AccountStore.defaultURL.deletingLastPathComponent().appendingPathComponent("state.json") }
}
```

- [ ] **Step 3: Add a smoke command to `Sources/Hop/CLI.swift`**

Change `static let commands: Set<String> = ["status", "open", "quit"]` to `["status", "open", "quit", "probe-login"]` and add, as the first `if` inside `run`, before the `status` branch:

```swift
        if args[0] == "probe-login" {
            // Read-only. Prints what Hop can see, never a token.
            let live = LiveLogin.parse(keychainValue: try? KeychainLoginStore().readLive(),
                                       identityDocument: try? IdentityDocumentFile().read())
            switch live {
            case .loggedIn(let s): print("logged in as \(s.email); login expires \(s.expiresAt); refresh expires \(s.refreshTokenExpiresAt)")
            case .loggedOut: print("logged out")
            case .unrecognized(let why): print("unrecognized: \(why)")
            }
            print("running claude sessions: \(RunningSessions.count())")
            return 0
        }
```

- [ ] **Step 4: Build and smoke-test**

Run: `swift build -c release --product Hop 2>&1 | grep -E "error:|Build of product"` — expected `Build of product 'Hop' complete!`.
Run: `./build.sh >/dev/null && ./build/Hop.app/Contents/MacOS/Hop probe-login`
Expected: a line starting `logged in as ` with the current email, or `logged out`. macOS may show a Keychain prompt "Hop wants to use your confidential information stored in Claude Code-credentials": click **Always Allow**. If the output is `unrecognized: …`, stop and report the reason; the format assumptions in the spec no longer hold.

- [ ] **Step 5: Run the suite and commit**

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3` — expected `0 failures`.

```bash
git add Sources/Hop/KeychainLoginStore.swift Sources/Hop/FileStores.swift Sources/Hop/CLI.swift
git commit -m "Add Keychain and file stores plus a read-only probe-login command

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: TerminalRunner, new alerts, and the unknown-login dialog

**Files:**
- Create: `Sources/Hop/TerminalRunner.swift`
- Create: `Sources/Hop/UnknownLoginDialog.swift`
- Modify: `Sources/Hop/Alerts.swift`
- Modify: `Resources/Info.plist`

**Interfaces:**
- Produces: `TerminalRunner.open(_ command: TerminalRunner.Command) -> Bool` with `enum Command { case claude, login }`; `UnknownLoginDialog.ask(email: String, candidates: [Account]) -> UnknownLoginChoice?`; `Alerts.terminalAutomationDenied()`, `Alerts.logInFirst()`, `Alerts.switchFailed(_ error: Error)`, `Alerts.switched(to name: String, sessions: Int)`.

- [ ] **Step 1: Implement `Sources/Hop/TerminalRunner.swift`**

```swift
import AppKit

/// Opens a new Terminal.app window running one of two fixed commands. No user input is ever interpolated.
@MainActor
enum TerminalRunner {
    static let bundleID = "com.apple.Terminal"

    enum Command {
        case claude, login
        var script: String {
            switch self {
            case .claude: "claude"
            case .login: "claude auth login"
            }
        }
    }

    /// Returns false when AppleScript failed (usually: Automation permission denied).
    static func open(_ command: Command) -> Bool {
        let source = """
        tell application "Terminal"
            activate
            do script "\(command.script)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Hop: Terminal automation failed: %@", error) }
        return error == nil
    }
}
```

- [ ] **Step 2: Implement `Sources/Hop/UnknownLoginDialog.swift`**

```swift
import AppKit
import SwitcherCore

@MainActor
enum UnknownLoginDialog {
    /// "Save the current login as…": a new account, or one of the accounts that has no email yet. nil = cancel.
    static func ask(email: String, candidates: [Account]) -> UnknownLoginChoice? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Save the current login?"
        alert.informativeText = "Terminal is logged in as \(email), which Hop hasn't saved. Switching away would lose that login, so save it first."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        popup.addItem(withTitle: "New account")
        for account in candidates { popup.addItem(withTitle: "Attach to \(account.name)") }
        alert.accessoryView = popup
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let index = popup.indexOfSelectedItem
        return index == 0 ? .create : .attach(candidates[index - 1].id)
    }
}
```

- [ ] **Step 3: Add alerts to `Sources/Hop/Alerts.swift`** (inside `enum Alerts`, after `claudeMissing()`):

```swift
    static func terminalAutomationDenied() {
        show("Hop can't open Terminal",
             "Allow Hop to control Terminal in System Settings › Privacy & Security › Automation, then try again.")
    }

    static func logInFirst() {
        show("Log in, then switch once",
             "Terminal is opening so you can run claude auth login. After you log in, switch to any other account once and Hop will save this one.")
    }

    static func switchFailed(_ error: Error) {
        show("Couldn't switch", error.localizedDescription)
    }
```

- [ ] **Step 4: Update `Resources/Info.plist`**

Replace the `NSAppleEventsUsageDescription` string with:

```xml
    <string>Hop uses this to bring the right Claude window to the front and to open Terminal on the account you pick.</string>
```

- [ ] **Step 5: Build, run the suite, commit**

Run: `swift build -c release --product Hop 2>&1 | grep -E "error:|Build of product"` — expected complete.
Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3` — expected `0 failures`.

```bash
git add Sources/Hop/TerminalRunner.swift Sources/Hop/UnknownLoginDialog.swift Sources/Hop/Alerts.swift Resources/Info.plist
git commit -m "Add Terminal runner, unknown-login dialog, and switch alerts

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: SwitchController and CLI `switch`

**Files:**
- Create: `Sources/Hop/SwitchController.swift`
- Modify: `Sources/Hop/CLI.swift`
- Modify: `Sources/Hop/AppDelegate.swift` (construct the controller; no menu wiring yet)

**Interfaces:**
- Produces:
  ```swift
  @MainActor final class SwitchController {
      init(model: AppModel, logins: LoginStore = KeychainLoginStore(), identityDocument: IdentityDocumentStore = IdentityDocumentFile(), stateURL: URL = HopStateFile.url)
      private(set) var state: HopState
      private(set) var live: LiveLoginState
      var onChange: (() -> Void)?
      func refreshLive()
      func menuModel(desktopRunning: Set<UUID>, hotkeyAction: HotkeyAction, hotkeyPositions: Set<Int>) -> MenuModel
      func hasSavedLogin(_ id: UUID) -> Bool
      func switchTo(_ account: Account)          // alerts on failure
      func openTerminal(_ account: Account)      // switch if needed, then Terminal
      func logInFirst()                          // Terminal running claude auth login + alert
      func saveCurrentLogin()                    // dialog + capture without switching
      func forgetSavedLogin(_ account: Account) throws
      func deleteSavedLogins(for ids: [UUID])
      var activeAccountID: UUID?
  }
  ```

- [ ] **Step 1: Implement `Sources/Hop/SwitchController.swift`**

```swift
import AppKit
import SwitcherCore

/// Glues SwitchCoordinator to the model, the stores, alerts, and Terminal.
@MainActor
final class SwitchController {
    private let model: AppModel
    private let logins: LoginStore
    private let coordinator: SwitchCoordinator
    private let stateURL: URL
    private(set) var state: HopState
    private(set) var live: LiveLoginState = .loggedOut
    /// Set once the live data was unrecognized; Switch stays disabled until relaunch.
    private(set) var loginFormatBroken = false
    var onChange: (() -> Void)?
    /// Where failures go: an alert in the app, a printed line in the CLI.
    var reportError: (Error) -> Void = { Alerts.switchFailed($0) }

    init(model: AppModel, logins: LoginStore = KeychainLoginStore(),
         identityDocument: IdentityDocumentStore = IdentityDocumentFile(), stateURL: URL = HopStateFile.url) {
        self.model = model
        self.logins = logins
        self.stateURL = stateURL
        self.state = HopState.load(from: stateURL)
        self.coordinator = SwitchCoordinator(logins: logins, identityDocument: identityDocument, home: NSHomeDirectory())
        refreshLive()
    }

    func refreshLive() {
        let value = try? logins.readLive()
        let document = try? IdentityDocumentFile().read()
        live = LiveLogin.parse(keychainValue: value, identityDocument: document)
        if case .unrecognized = live, !loginFormatBroken {
            loginFormatBroken = true
            reportError(SwitchError.unrecognizedLogin(reason(of: live)))
        }
    }

    var activeAccountID: UUID? {
        guard case .loggedIn(let summary) = live else { return nil }
        return LoginAttribution.attribute(summary, accounts: model.accounts, state: state).accountID
    }

    func hasSavedLogin(_ id: UUID) -> Bool { (try? logins.readSaved(id)) != nil }

    func menuModel(desktopRunning: Set<UUID>, hotkeyAction: HotkeyAction, hotkeyPositions: Set<Int>) -> MenuModel {
        MenuModel.build(accounts: model.accounts, live: live, state: state,
                        savedLoginExpiry: coordinator.savedLoginExpiry(for: model.accounts),
                        hasSavedLogin: Set(model.accounts.map(\.id).filter(hasSavedLogin)),
                        desktopRunning: desktopRunning, runningSessions: RunningSessions.count(),
                        hotkeyAction: hotkeyAction, hotkeyPositions: hotkeyPositions, now: Date())
    }

    /// Returns true when the account is now active (was already, or the switch succeeded).
    @discardableResult
    func switchTo(_ account: Account) -> Bool {
        guard !loginFormatBroken else { reportError(SwitchError.unrecognizedLogin("see the earlier alert")); return false }
        refreshLive()
        if activeAccountID == account.id { return true }
        do {
            let result = try coordinator.switchTo(account.id, accounts: model.accounts, state: state) { [self] email in
                UnknownLoginDialog.ask(email: email, candidates: model.accounts.filter { $0.email == nil })
            }
            try persist(accounts: result.accounts, state: result.state)
            return true
        } catch {
            reportError(error)
            refreshLive()
            onChange?()
            return false
        }
    }

    func openTerminal(_ account: Account) {
        guard hasSavedLogin(account.id) else { logInFirst(); return }
        guard switchTo(account) else { return }
        if !TerminalRunner.open(.claude) { Alerts.terminalAutomationDenied() }
    }

    func logInFirst() {
        if TerminalRunner.open(.login) { Alerts.logInFirst() } else { Alerts.terminalAutomationDenied() }
    }

    func saveCurrentLogin() {
        refreshLive()
        guard case .loggedIn(let summary) = live else { return }
        guard let choice = UnknownLoginDialog.ask(email: summary.email, candidates: model.accounts.filter { $0.email == nil }) else { return }
        do {
            let (accounts, newState) = try coordinator.saveCurrentLogin(accounts: model.accounts, state: state, choice: choice)
            try persist(accounts: accounts, state: newState)
        } catch {
            reportError(error)
        }
    }

    func forgetSavedLogin(_ account: Account) throws {
        if activeAccountID == account.id { throw SwitchError.store("\(account.name) is the active account. Switch to another account first.") }
        try logins.deleteSaved(account.id)
        var accounts = model.accounts
        if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index].email = nil }
        try model.setAccounts(accounts)
        onChange?()
    }

    func deleteSavedLogins(for ids: [UUID]) {
        for id in ids { try? logins.deleteSaved(id) }
    }

    private func persist(accounts: [Account], state newState: HopState) throws {
        if accounts != model.accounts { try model.setAccounts(accounts) }
        state = newState
        try state.save(to: stateURL)
        refreshLive()
        onChange?()
    }

    private func reason(of state: LiveLoginState) -> String {
        if case .unrecognized(let why) = state { return why }
        return ""
    }
}
```

- [ ] **Step 2: Extend `Sources/Hop/CLI.swift`**

Change `commands` to `["status", "open", "quit", "probe-login", "switch"]`. Replace the `status` branch body with:

```swift
        if args[0] == "status" {
            let switcher = SwitchController(model: model)
            let active = switcher.activeAccountID
            for (i, account) in model.accounts.enumerated() {
                let app = model.tracker.running[account.id]
                let desktop = app.map { "running\tpid \($0.processIdentifier)" } ?? "closed\t-"
                let mark = account.id == active ? "*" : " "
                print("\(i + 1)\t\(mark)\t\(account.name)\t\(account.email ?? "-")\t\(desktop)\t\(account.folder ?? FolderPath.defaultProfile)")
            }
            if case .loggedIn(let s) = switcher.live, active == nil { print("terminal login \(s.email) isn't saved in Hop") }
            return 0
        }
```

After the `guard args.count == 2 …` block and the `quit` branch, add before the desktop `open` code:

```swift
        if args[0] == "switch" {
            let switcher = SwitchController(model: model)
            let live = switcher.live
            if case .loggedIn(let s) = live, switcher.activeAccountID == nil {
                print("error: current login (\(s.email)) isn't saved; save it from the menu first")
                return 1
            }
            let ok = switcher.switchTo(account)
            print(ok ? "active: \(account.name)" : "switch failed")
            return ok ? 0 : 1
        }
```

The CLI must stay headless, so in the `switch` branch above, insert this line right after `let switcher = SwitchController(model: model)`:

```swift
            switcher.reportError = { print("error: \($0.localizedDescription)") }
```

- [ ] **Step 3: Construct the controller in `Sources/Hop/AppDelegate.swift`**

Add `private var switcher: SwitchController!` next to the other properties, and right after `launcher = Launcher(model: model)` in `applicationDidFinishLaunching`:

```swift
        switcher = SwitchController(model: model)
        switcher.onChange = { [unowned self] in self.menu.rebuild() }
```

- [ ] **Step 4: Build, smoke-test, commit**

Run: `swift build -c release --product Hop 2>&1 | grep -E "error:|Build of product"` — expected complete.
Run: `./build.sh >/dev/null && ./build/Hop.app/Contents/MacOS/Hop status` — expected: one line per account with `*` on the active one, or the "isn't saved" line.
Do **not** run `Hop switch` yet; that is Task 17 with the user present.

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3` — expected `0 failures`.

```bash
git add Sources/Hop/SwitchController.swift Sources/Hop/CLI.swift Sources/Hop/AppDelegate.swift
git commit -m "Add SwitchController and the hop switch command

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 14: Menu rebuild with submenus, header, checkmark, icon color, Hotkeys

**Files:**
- Modify: `Sources/Hop/MenuController.swift`
- Modify: `Sources/Hop/AppDelegate.swift`

**Interfaces:**
- Consumes: `SwitchController.menuModel(desktopRunning:hotkeyAction:hotkeyPositions:)`, `MenuModel`, `MenuRow`, `HotkeyAction`.
- Produces: `MenuActions` gains `switchLogin: (Account) -> Void`, `openTerminal: (Account) -> Void`, `logInFirst: () -> Void`, `saveCurrentLogin: () -> Void`, `setHotkeyAction: (HotkeyAction) -> Void`; `MenuController` gains `var modelProvider: (() -> MenuModel)?` and `var hotkeyAction: HotkeyAction`.

- [ ] **Step 1: Rewrite `MenuActions` and the menu build in `Sources/Hop/MenuController.swift`**

Replace `struct MenuActions` with:

```swift
struct MenuActions {
    var open: (Account) -> Void
    var quit: (Account) -> Void
    var switchLogin: (Account) -> Void
    var openTerminal: (Account) -> Void
    var logInFirst: () -> Void
    var saveCurrentLogin: () -> Void
    var setHotkeyAction: (HotkeyAction) -> Void
    var addAccount: (() -> Void)? = nil
    var editAccounts: (() -> Void)? = nil
}
```

Add these properties to `MenuController` after `hotkeyPositions`:

```swift
    /// Supplies the computed menu each rebuild; set by AppDelegate.
    var modelProvider: (() -> MenuModel)?
    var hotkeyAction: HotkeyAction = .default
    private static let symbolIcon = NSImage(systemSymbolName: "person.2", accessibilityDescription: "Claude accounts")
```

Replace the whole `rebuild()` and `addRows(for:position:)` with:

```swift
    func rebuild() {
        menu.removeAllItems()
        let computed = modelProvider?() ?? MenuModel(header: "", sessionsLine: nil, rows: [], saveCurrentLoginEmail: nil, activeAccountID: nil)
        updateIcon(activeID: computed.activeAccountID)

        if !computed.header.isEmpty {
            let header = NSMenuItem(title: computed.header, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            if let line = computed.sessionsLine {
                let sessions = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                sessions.isEnabled = false
                menu.addItem(sessions)
            }
            menu.addItem(.separator())
        }
        if ClaudeApp.url == nil {
            let missing = NSMenuItem(title: "Claude app not found", action: nil, keyEquivalent: "")
            missing.isEnabled = false
            menu.addItem(missing)
        }
        for row in computed.rows {
            guard let account = model.accounts.first(where: { $0.id == row.accountID }) else { continue }
            menu.addItem(accountItem(account, row: row))
        }
        menu.addItem(.separator())
        if let email = computed.saveCurrentLoginEmail {
            menu.addItem(ClosureMenuItem(title: "Save current login (\(email)) as new account…") { [weak self] in self?.actions.saveCurrentLogin() })
        }
        if let add = actions.addAccount { menu.addItem(ClosureMenuItem(title: "Add account…", handler: add)) }
        if let edit = actions.editAccounts { menu.addItem(ClosureMenuItem(title: "Edit accounts…", handler: edit)) }
        menu.addItem(hotkeysItem())
        let login = ClosureMenuItem(title: "Launch at login") { LoginItem.toggle() }
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit Hop", keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    /// One account row: color dot, checkmark when active, and a submenu with the three actions.
    private func accountItem(_ account: Account, row: MenuRow) -> NSMenuItem {
        let dot = Dot.image(color: account.color.nsColor, filled: row.desktopRunning)
        let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
        item.attributedTitle = Self.title(row.title, hint: row.hint)
        item.image = dot
        item.state = row.isActive ? .on : .off
        item.toolTip = row.isActive ? "Active terminal login" : nil

        let sub = NSMenu()
        sub.autoenablesItems = false
        switch row.switchLabel {
        case .active:
            let active = NSMenuItem(title: "Active", action: nil, keyEquivalent: "")
            active.isEnabled = false
            active.state = .on
            sub.addItem(active)
        case .switchLogin:
            sub.addItem(ClosureMenuItem(title: "Switch terminal login") { [weak self] in self?.actions.switchLogin(account) })
        case .logInFirst:
            sub.addItem(ClosureMenuItem(title: "Log in first…") { [weak self] in self?.actions.logInFirst() })
        }
        sub.addItem(ClosureMenuItem(title: "Open Terminal") { [weak self] in self?.actions.openTerminal(account) })
        sub.addItem(.separator())
        if ClaudeApp.url != nil {
            let open = ClosureMenuItem(title: row.desktopLabel) { [weak self] in self?.actions.open(account) }
            open.keyEquivalentModifierMask = []
            sub.addItem(open)
            let quit = ClosureMenuItem(title: "Quit Claude app") { [weak self] in self?.actions.quit(account) }
            quit.isAlternate = true
            quit.keyEquivalentModifierMask = .option
            quit.isEnabled = row.desktopRunning
            sub.addItem(quit)
        }
        item.submenu = sub
        return item
    }

    private func hotkeysItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Hotkeys", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for action in HotkeyAction.allCases {
            let choice = ClosureMenuItem(title: action.label) { [weak self] in self?.actions.setHotkeyAction(action) }
            choice.state = action == hotkeyAction ? .on : .off
            sub.addItem(choice)
        }
        item.submenu = sub
        return item
    }

    /// Filled circle in the active account's color; the gray symbol when nothing is active.
    private func updateIcon(activeID: UUID?) {
        if let activeID, let account = model.accounts.first(where: { $0.id == activeID }) {
            let image = Dot.image(color: account.color.nsColor, filled: true)
            image.isTemplate = false
            statusItem.button?.image = image
            statusItem.button?.toolTip = "Hop · \(account.name)"
        } else {
            statusItem.button?.image = Self.symbolIcon
            statusItem.button?.toolTip = "Hop"
        }
    }
```

Keep `Self.title(_:hint:)` as it is. In `init`, keep `statusItem.button?.image = …` (the symbol); `rebuild()` overrides it.

Note: `Dot.image` is 10pt; for the menu bar make it 14pt: change `Dot.image` in `Sources/Hop/Appearance.swift` to take `size: CGFloat = 10` and use `NSSize(width: size, height: size)`; call it with `size: 14` in `updateIcon`.

- [ ] **Step 2: Wire it in `Sources/Hop/AppDelegate.swift`**

Replace the `menu = MenuController(...)` construction with:

```swift
        menu = MenuController(model: model, actions: MenuActions(
            open: { [unowned self] in self.launcher.open($0) },
            quit: { [unowned self] in self.launcher.quit($0) },
            switchLogin: { [unowned self] in self.switcher.switchTo($0) },
            openTerminal: { [unowned self] in self.switcher.openTerminal($0) },
            logInFirst: { [unowned self] in self.switcher.logInFirst() },
            saveCurrentLogin: { [unowned self] in self.switcher.saveCurrentLogin() },
            setHotkeyAction: { [unowned self] in self.setHotkeyAction($0) },
            addAccount: { [unowned self] in self.addAccount() },
            editAccounts: { [unowned self] in self.editWindow.show() }
        ))
        menu.hotkeyAction = hotkeyAction
        menu.modelProvider = { [unowned self] in
            self.switcher.menuModel(desktopRunning: Set(self.model.tracker.running.keys),
                                    hotkeyAction: self.hotkeyAction, hotkeyPositions: self.hotkeys.registered)
        }
```

Add the setting and the hotkey dispatch:

```swift
    private var hotkeyAction: HotkeyAction {
        get { HotkeyAction(rawValue: UserDefaults.standard.string(forKey: HotkeyAction.defaultsKey) ?? "") ?? .default }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: HotkeyAction.defaultsKey) }
    }

    private func setHotkeyAction(_ action: HotkeyAction) {
        hotkeyAction = action
        menu.hotkeyAction = action
        accountsChanged()
    }
```

and change `accountsChanged()` to:

```swift
    private func accountsChanged() {
        let actions: [() -> Void]
        switch hotkeyAction {
        case .off: actions = []
        case .switchLogin: actions = model.accounts.map { account in { [unowned self] in self.switcher.switchTo(account) } }
        case .openClaudeApp: actions = model.accounts.map { account in { [unowned self] in self.launcher.open(account) } }
        case .openTerminal: actions = model.accounts.map { account in { [unowned self] in self.switcher.openTerminal(account) } }
        }
        hotkeys.register(actions)
        menu.hotkeyPositions = hotkeys.registered
        menu.rebuild()
    }
```

Also make `menuWillOpen` in `MenuController` call `model.tracker.refresh()` then `rebuild()` (already does), and have `AppDelegate` refresh the live login before each open: in `MenuController.menuWillOpen` there is no reference to the switcher, so instead set `menu.modelProvider` to call `self.switcher.refreshLive()` first:

```swift
        menu.modelProvider = { [unowned self] in
            self.switcher.refreshLive()
            return self.switcher.menuModel(desktopRunning: Set(self.model.tracker.running.keys),
                                           hotkeyAction: self.hotkeyAction, hotkeyPositions: self.hotkeys.registered)
        }
```

- [ ] **Step 3: Build, install, check the menu by eye**

Run: `swift build -c release --product Hop 2>&1 | grep -E "error:|Build of product"` — expected complete.
Run: `./build.sh --install` then open the menu. Expected: header line with the active email (or "not saved"), each account as a submenu with the three actions, checkmark on the active row if one matches, a Hotkeys submenu with the current choice checked, and the menu bar icon as a colored dot when an account is active. Only *look*; do not click Switch.

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3` — expected `0 failures`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Hop/MenuController.swift Sources/Hop/AppDelegate.swift Sources/Hop/Appearance.swift
git commit -m "Show the active account, per-account submenus, and a Hotkeys setting

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 15: Edit accounts: email column, Forget saved login, delete on remove

**Files:**
- Modify: `Sources/Hop/EditAccountsWindow.swift`
- Modify: `Sources/Hop/AppDelegate.swift` (pass the switcher)

**Interfaces:**
- Consumes: `SwitchController.forgetSavedLogin(_:)`, `SwitchController.deleteSavedLogins(for:)`, `Account.email`.

- [ ] **Step 1: Thread the switcher through**

`EditAccountsWindow.init` becomes `init(model: AppModel, switcher: SwitchController)`, stores it, and passes it to `EditAccountsView(model:switcher:close:)`. In `AppDelegate`, construct with `editWindow = EditAccountsWindow(model: model, switcher: switcher)` (move this line after `switcher` is created).

- [ ] **Step 2: Add the email caption and Forget button to each row**

In `EditAccountsView`, add `let switcher: SwitchController` and `@State private var forgetPending: Account?`. In the row `HStack`, after `Text(folderLabel(account))`, add:

```swift
                        if let email = account.email {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                            Button { forgetPending = account } label: { Image(systemName: "key.slash") }
                                .buttonStyle(.borderless)
                                .help("Forget saved login")
                        }
```

Add a confirmation using SwiftUI's `.confirmationDialog` on the outer `VStack`:

```swift
        .confirmationDialog("Forget the saved login for \(forgetPending?.name ?? "")?", isPresented: Binding(get: { forgetPending != nil }, set: { if !$0 { forgetPending = nil } })) {
            Button("Forget", role: .destructive) {
                guard let account = forgetPending else { return }
                do {
                    try switcher.forgetSavedLogin(account)
                    if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index].email = nil }
                } catch {
                    self.error = error.localizedDescription
                }
                forgetPending = nil
            }
        } message: {
            Text("Hop deletes its copy of that terminal login. Log in again as that account and switch once to save it again.")
        }
```

- [ ] **Step 3: Delete saved logins for removed accounts on Save**

In `save()`, capture the original ids before anything changes, and delete the saved logins of accounts that are gone once the new list is saved. The first line goes at the very top of `save()`; the second right after `try model.setAccounts(trimmed)` succeeds:

```swift
        let originalIDs = Set(model.accounts.map(\.id))          // top of save()
        // ... existing trimming, tracker refresh, setAccounts ...
        switcher.deleteSavedLogins(for: Array(originalIDs.subtracting(trimmed.map(\.id))))   // after setAccounts
```

Also update the `RemoveAccountSheet` text to: "It leaves Hop. Its desktop sign-in stays in its folder unless you move the folder to the Trash; its saved terminal login is deleted."

- [ ] **Step 4: Build, look, commit**

Run: `swift build -c release --product Hop 2>&1 | grep -E "error:|Build of product"` — expected complete.
Run: `./build.sh --install`, open Edit accounts: accounts with an email show it with a key icon. Don't click Forget on the active account except to confirm the refusal message.

Run: `swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3` — expected `0 failures`.

```bash
git add Sources/Hop/EditAccountsWindow.swift Sources/Hop/AppDelegate.swift
git commit -m "Show emails in Edit accounts and let users forget a saved login

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 16: build.sh link and README

**Files:**
- Modify: `build.sh`
- Modify: `README.md`

- [ ] **Step 1: `build.sh`**

Inside the `--install` block, after `cp -R "$APP" "$INSTALLED"`:

```bash
  if [[ -d "$HOME/bin" ]]; then
    ln -sfn "$INSTALLED/Contents/MacOS/Hop" "$HOME/bin/hop"
    echo "Linked $HOME/bin/hop"
  else
    echo "Command line: $INSTALLED/Contents/MacOS/Hop (make ~/bin to get a 'hop' link)"
  fi
```

- [ ] **Step 2: README**

Change the first paragraph to:

```markdown
A menu-bar app for running several Claude accounts side by side. Desktop
accounts each get their own profile folder, so signing into one never signs
another out. Terminal accounts switch the Claude Code login for the whole
machine with one click, with no `/login`.
```

Add a section after "## Use":

```markdown
## Terminal accounts

Click an account and choose **Switch terminal login**. Every new `claude` you
start uses that account at once. Terminals already running keep their current
login until it refreshes, up to about eight hours, then follow. The menu shows
how many are running.

Hop never logs in for you. It saves the login Claude Code already has whenever
you switch away from it, in the macOS Keychain. To add an account: choose
**Log in first…** (or run `claude auth login` yourself), sign in as the new
account, then switch to any other account once. Hop asks where to save the
login it found.

**Open Terminal** switches if needed and opens a Terminal window running
`claude`. macOS asks once to let Hop control Terminal; allow it. The first time
Hop reads Claude Code's login, macOS also asks about the Keychain item: choose
**Always Allow**, and again after each `./build.sh --install`, which re-signs
the app.

A saved login lasts as long as its refresh token, about four weeks. Rows warn
seven days before. Log in as that account once to renew it.

**Hotkeys** in the menu chooses what ⌃⌥1…9 do: nothing, switch the login, open
the Claude app (the default), or open Terminal.
```

Update the "## Command line" block to:

```bash
hop status      # accounts, with * on the active terminal login
hop switch 2    # make account 2 the terminal login
hop open 3      # open the desktop app for account 3
hop quit 3
```

with the note: "`./build.sh --install` links `hop` into `~/bin` when that folder exists; otherwise use the full path under `~/Applications/Hop.app/Contents/MacOS/Hop`."

Remove the "Nothing in `/Applications`" troubleshooting paragraph's duplication if it now repeats the install note; keep one mention.

- [ ] **Step 3: Verify and commit**

Run: `bash -n build.sh && ./build.sh --install | tail -3` — expected `Linked /Users/<you>/bin/hop` or the fallback line, and `hop status` works from a new shell.

```bash
git add build.sh README.md
git commit -m "Link hop into ~/bin and document terminal accounts

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 17: Manual end-to-end switch (needs the user)

**Files:** none. This is verification of the whole branch on a real machine.

Do this only after the user says go in the conversation. Before starting, tell them what will happen: one switch each way between two accounts, each freshly logged in; the account they log in as last is the one left active.

- [ ] **Step 1: Back up**

```bash
cp -p ~/.claude.json "$TMPDIR/claude.json.backup" && chmod 600 "$TMPDIR/claude.json.backup"
hop probe-login
```

Expected: `logged in as <A>`.

- [ ] **Step 2: Save account A**

Ask the user which Hop account should hold the current login, or use "Save current login … as new account" from the menu. Then `hop status` must show `*` on that account with A's email.

- [ ] **Step 3: Log in as B by hand**

User runs `claude auth login` in a fresh Terminal and signs in as B. Then `hop probe-login` shows `logged in as <B>`, and `hop status` shows the "isn't saved" line.

- [ ] **Step 4: Switch to A from the menu**

The unknown-login dialog appears for B: choose New account. Then:
- the menu header reads `Active: <A's account>`, the icon is A's color;
- a new terminal's `claude auth status` shows A's email;
- `hop status` shows `*` on A and an email on B's row.

- [ ] **Step 5: Switch back to B (`hop switch <n>`)**

- `claude auth status` in a new terminal shows B;
- `hop probe-login` shows B with a future refresh expiry.

- [ ] **Step 6: Wrong-path checks that write nothing**

- Choose Switch on the active account: nothing happens beyond "already active" (menu shows Active).
- Edit accounts → Forget on the active account: refused with the "switch first" message.

- [ ] **Step 7: Report**

Tell the user exactly which account is active and that the backup at `$TMPDIR/claude.json.backup` can be deleted. If anything failed, restore with `cp "$TMPDIR/claude.json.backup" ~/.claude.json` only if the identity file was corrupted; a failed switch has already restored the Keychain by design.

- [ ] **Step 8: Remove the smoke command?**

Keep `probe-login`; it is read-only and useful for support. Update the README's command-line block to list it: `hop probe-login  # what Hop sees in Claude Code's login, no secrets`. Commit:

```bash
git add README.md
git commit -m "Document hop probe-login

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage.** Account model and version 2: Task 1. Keychain item format: Task 5. State file: Task 6. Hotkey setting: Tasks 2 and 14. Reading the live login, shape check, logged-out handling: Task 3. Switch procedure steps 1 to 5, attribution rules, undo on identity failure: Tasks 7 and 8 (write order: target checked before capture so a refused switch captures nothing; the spec's step order is otherwise kept). Running sessions: Task 10. Menu layout, checkmark, icon color, Save current login, Hotkeys submenu, expiry suffix: Tasks 9 and 14. Terminal integration and Automation alert: Task 12. CLI `switch` and `status`: Task 13. Edit accounts email and Forget: Task 15. `build.sh` link and README: Task 16. Error table: unrecognized (Task 8/13), identity unreadable (Task 3 parse → unrecognized), Keychain failure with restore (Task 8), expired target (Task 8), cancel (Task 8), automation denied (Task 12/13), logged out (Task 8). Manual test: Task 17.

**Deviation from the spec worth knowing:** the coordinator checks the target (saved login present, not expired) *before* capturing the outgoing login, so a refused switch never writes a saved item either. The spec listed the check after capture; this ordering is strictly safer and the tests encode it.

**Placeholders.** None; every code step shows the code.

**Type consistency.** `LoginStore`, `IdentityDocumentStore`, `UnknownLoginChoice`, `SwitchError`, `SwitchResult`, `SwitchCoordinator` (Task 8) are used unchanged in Tasks 11, 13. `MenuModel.build` signature (Task 9) matches the call in Task 13's `menuModel(...)`. `HotkeyAction.defaultsKey` / `.default` (Task 2) used in Task 14. `Dot.image(color:filled:size:)` gains a defaulted `size` in Task 14 and existing callers keep compiling.
