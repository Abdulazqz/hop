# Hop Secure Login & Live Switch — Implementation Plan (Plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Hop authenticate every `claude` session through a Keychain-backed `apiKeyHelper`, so switching the active account flips one small pointer file and all running sessions follow on their next turn — a secure replacement for `/login`, with no account token ever in a plaintext file.

**Architecture:** Each account's `claude setup-token` is stored in a Hop-owned Keychain item (`service "local.hop.token"`, account = account UUID), read/written through the existing `SecurityTool` (`security` CLI). A generated helper script reads an active-account **pointer file** (UUID only) and prints that account's token. Hop writes `apiKeyHelper` + a `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` `env` entry into the user's existing `~/.claude/settings.json` (no config-dir move). Switching = rewrite the pointer. All new decision logic is pure code in `SwitcherCore`; `Hop` does the file/Keychain IO.

**Tech Stack:** Swift 5.9, SwiftPM, macOS 14+. Two targets: `SwitcherCore` (pure, unit-tested with XCTest) and `Hop` (AppKit app). Keychain via `/usr/bin/security` only.

**Spec:** `docs/superpowers/specs/2026-11-07-hop-secure-multi-account-control-center-design.md`

**Spike result (2026-11-07 — de-risks this whole plan):** the live-switch mechanism is proven in isolation against Claude Code v2.1.319 (see the spec's "How it works"). Four facts the implementation must honor: (a) the TTL is delivered via the settings `env` block and drives a **lazy, request-time** refetch, not a background timer; (b) the helper re-reads the pointer on every invocation, so a flip is adopted on the next request whose cred is older than the TTL (possibly mid-turn); (c) `apiKeyHelper` **overrides `CLAUDE_CODE_OAUTH_TOKEN`** — the only opt-out is a separate `CLAUDE_CONFIG_DIR`; (d) the pointer is read on every stale request, so its write **must be atomic** (temp + `rename`) or a torn read makes the helper emit nothing.

## Global Constraints

- macOS 14+; SwiftPM; `SwitcherCore` stays pure and unit-testable, `Hop` holds all IO/AppKit. (verbatim from spec "Constraints")
- **No account token in any plaintext file at rest.** Tokens live only in the Keychain; the only on-disk artifacts are the account-name/UUID pointer and the secret-free helper script. (spec anti-goals)
- **Do not relocate `~/.claude`.** `apiKeyHelper` is set in the user's existing `~/.claude/settings.json`. (spec goals/anti-goals)
- Keychain access goes through the Apple `security` CLI (`SecurityTool`), never a Security-framework write to Claude's items. (spec constraints)
- Tokens reach Claude Code only via the helper's **stdout**, never argv. (spec constraints)
- The **pointer file and `~/.claude/settings.json` are written atomically** (temp file + `rename`); the helper reads the pointer on every stale request, so a torn read must be impossible. (2026-11-07 spike)
- A switch is adopted on the next API request whose cached cred is older than the TTL — effectively the next turn, and possibly **mid-turn** (one turn = many requests); never a retroactive change to an in-flight request. (spec non-goals, corrected by the 2026-11-07 spike)
- Full pivot: the old captured-login-blob terminal switch is removed; desktop-profile (`folder`) switching is untouched. (spec decision #1)

## Review Focus

Inputs the spec implies but a happy-path task might not exercise — each gets a test in the owning task:
- **An existing `~/.claude/settings.json` with unrelated keys** must keep every other key when Hop adds/removes `apiKeyHelper`. → Task 6.
- **A pasted token with surrounding whitespace/newlines** must be accepted (trimmed), and a non-`sk-ant-oat01` string rejected. → Task 2.
- **The pointer naming an account with no stored token (or a deleted one)** → the helper prints nothing and exits 0 (Claude falls back to its last working token; never a partial token). → Task 5.
- **A `~/.claude/settings.json` that is absent or empty** → enable starts from `{}`; **one that is invalid JSON** → enable fails loudly without clobbering it. → Task 6.
- **Disable/revert leaves the Keychain login intact**, so removing `apiKeyHelper` returns Claude to its normal login. → Task 7.

---

## File Structure

New in `SwitcherCore` (pure):
- `SetupToken.swift` — validate/normalize a pasted setup-token.
- `TokenStore.swift` — `TokenStore` protocol + token Keychain service name.
- `ActivePointer.swift` — pointer file content ⇄ UUID.
- `HelperScript.swift` — generate the helper bash script text.
- `ClaudeSettings.swift` — enable/disable `apiKeyHelper` in a settings JSON blob.

New in `Hop` (IO):
- `KeychainTokenStore.swift` — `TokenStore` over `SecurityToolItem`.
- `HopLoginInstall.swift` — install/revert helper script, settings, pointer.

Modified:
- `Account.swift` (+`tokenAddedAt`), `MenuModel.swift` (active = pointer/state; new row labels), `SwitchController.swift` (switch = pointer flip), `CLI.swift`, `MenuController.swift`, `AddAccountFlow.swift`/`EditAccountsWindow.swift` (add/renew/remove a token).
- Removed at the end (Task 10): `SavedLogin.swift`, `UnknownLoginDialog.swift`, saved-login paths in `KeychainLoginStore`/`SwitchCoordinator`/`LoginAttribution`, and `saveCurrentLogin`/`logInFirst`/`forgetSavedLogin`.

---

### Task 1: Account carries a stored-token marker

**Files:** Modify `Sources/SwitcherCore/Account.swift`; Test `Tests/SwitcherCoreTests/AccountValidationTests.swift` (or a new `AccountTokenTests.swift`).

**Interfaces — Produces:** `Account.tokenAddedAt: Date?` (nil = no setup-token stored for this account). Backward-compatible decoding: old `accounts.json` (v2, no field) decodes with `tokenAddedAt == nil`.

- [ ] **Step 1: Failing test** — `testDecodesV2AccountWithoutTokenField` decodes a JSON account object lacking `tokenAddedAt` and asserts `account.tokenAddedAt == nil`; `testTokenAddedAtRoundTrips` encodes then decodes an account with a set date and asserts equality.
- [ ] **Step 2: Run** `swift test --filter AccountTokenTests` → FAIL (no such property).
- [ ] **Step 3:** Add `public var tokenAddedAt: Date?` to `Account` with a default of `nil` in `init`. Because Swift synthesises `Codable` and the property is optional, a missing key decodes to `nil` — verify, and only if decoding of a missing key throws, add a custom `init(from:)` that defaults it.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: Account.tokenAddedAt marks a stored setup-token`.

### Task 2: Validate a pasted setup-token

**Files:** Create `Sources/SwitcherCore/SetupToken.swift`; Test `Tests/SwitcherCoreTests/SetupTokenTests.swift`.

**Interfaces — Produces:** `enum SetupToken { static func normalize(_ raw: String) throws -> String }` returning the trimmed token; `enum SetupTokenError: Error, Equatable { case empty, wrongPrefix, tooShort }`.

- [ ] **Step 1: Failing test** — assert `normalize("  sk-ant-oat01-" + String(repeating:"x",count:90) + "\n") ` returns the trimmed token; `normalize("")` throws `.empty`; `normalize("sk-ant-api-…")` throws `.wrongPrefix`; `normalize("sk-ant-oat01-short")` throws `.tooShort`.
- [ ] **Step 2: Run** `swift test --filter SetupTokenTests` → FAIL.
- [ ] **Step 3:** Implement `normalize`: strip whitespace/newlines; require prefix `sk-ant-oat01-` and length > 80 (matches `claude-as`).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: validate pasted setup-tokens`.

### Task 3: Token Keychain store

**Files:** Create `Sources/SwitcherCore/TokenStore.swift` (protocol + constant); Create `Sources/Hop/KeychainTokenStore.swift`; Test `Tests/SwitcherCoreTests/TokenStoreTests.swift` + a fake in `Tests/SwitcherCoreTests/FakeStores.swift`.

**Interfaces — Produces:** `protocol TokenStore { func readToken(_ id: UUID) throws -> String?; func writeToken(_ token: String, for id: UUID) throws; func deleteToken(_ id: UUID) throws }`; `enum TokenStoreConst { static let service = "local.hop.token" }`. `Hop.KeychainTokenStore` conforms using `SecurityToolItem(service: TokenStoreConst.service, account: id.uuidString)` with the token as UTF-8 `Data`.
**Consumes:** `SecurityToolItem` (existing).

- [ ] **Step 1: Failing test** — add `FakeTokenStore` (dictionary-backed) to `FakeStores.swift`; test round-trips write→read, read of an unknown id is `nil`, delete removes it.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3:** Define the protocol + `FakeTokenStore`; implement `KeychainTokenStore` (UTF-8 encode on write; `String(decoding:as:)` on read; `nil` when the item is absent). No new `security` plumbing — reuse `SecurityToolItem`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: per-account setup-token Keychain store`.

### Task 4: Active-account pointer

**Files:** Create `Sources/SwitcherCore/ActivePointer.swift`; Test `Tests/SwitcherCoreTests/ActivePointerTests.swift`. (File IO + path live in `Hop`; add `static var url` beside `HopStateFile` in `Sources/Hop/FileStores.swift`.)

**Interfaces — Produces:** `enum ActivePointer { static func content(for id: UUID) -> String; static func parse(_ text: String) -> UUID? }`. Content is the UUID string + trailing newline; `parse` trims then `UUID(uuidString:)`. `Hop`: pointer file at `~/Library/Application Support/Hop/active-account`.

- [ ] **Step 1: Failing test** — `parse(content(for: id)) == id`; `parse("  \(id)\n") == id`; `parse("garbage") == nil`; `parse("") == nil`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3:** Implement `content`/`parse`; add `ActivePointerFile.url` in `FileStores.swift`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: active-account pointer`.

### Task 5: Helper script generation

**Files:** Create `Sources/SwitcherCore/HelperScript.swift`; Test `Tests/SwitcherCoreTests/HelperScriptTests.swift`.

**Interfaces — Produces:** `enum HelperScript { static func contents(pointerPath: String, tokenService: String) -> String }` — a bash script that: reads `pointerPath`; if absent/empty, `exit 0` with no output; else runs `/usr/bin/security find-generic-password -s <tokenService> -a "<pointer contents>" -w 2>/dev/null`. It must print **only** the token (no diagnostics) and never a partial value.

- [ ] **Step 1: Failing test** — assert the output starts with `#!/bin/bash`, contains `pointerPath` and `find-generic-password -s "local.hop.token"`, contains `-a "$id"` reading the pointer, and contains an early `exit 0` guard for a missing pointer/empty id. (Pure string assertions; the live behavior is proven in the spec.)
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3:** Implement `contents`. Quote all interpolated paths. Guard: `[ -f "$P" ] || exit 0`, `id=$(cat "$P")`, `[ -n "$id" ] || exit 0`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: generate the apiKeyHelper script`.

### Task 6: Enable/disable apiKeyHelper in Claude settings JSON (pure)

**Files:** Create `Sources/SwitcherCore/ClaudeSettings.swift`; Test `Tests/SwitcherCoreTests/ClaudeSettingsTests.swift`.

**Interfaces — Produces:**
`enum ClaudeSettings { static func enableHelper(_ json: Data?, helperPath: String, ttlMs: Int) throws -> Data; static func disableHelper(_ json: Data?) throws -> Data; static func isHelperEnabled(_ json: Data?, helperPath: String) -> Bool }`.
`enableHelper` sets `apiKeyHelper = helperPath` and `env["CLAUDE_CODE_API_KEY_HELPER_TTL_MS"] = String(ttlMs)`, preserving all other top-level keys and other `env` entries; `nil`/empty input starts from `{}`. `disableHelper` removes exactly `apiKeyHelper` and that one `env` key (dropping `env` only if it becomes empty), preserving everything else. Invalid-JSON input throws (does not silently discard).

- [ ] **Step 1: Failing tests** — enable on `{"model":"x","env":{"FOO":"1"}}` yields a blob with `model`, `env.FOO`, `env.CLAUDE_CODE_API_KEY_HELPER_TTL_MS`, and `apiKeyHelper` all present; enable on `nil` yields `{apiKeyHelper, env:{TTL}}`; `disableHelper(enableHelper(x))` deep-equals `x` for a representative `x` (round-trip); `enableHelper(invalidJSON)` throws.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3:** Implement with `JSONSerialization` into `[String: Any]`; compare in tests by re-parsing (don't assert key order).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: merge apiKeyHelper into Claude settings JSON`.

### Task 7: Install / revert Hop-as-login

**Files:** Create `Sources/Hop/HopLoginInstall.swift`; Modify `Sources/Hop/FileStores.swift` (helper-script URL), `Sources/Hop/MenuController.swift` (menu item), `Sources/Hop/Alerts.swift` (explain the global effect). Test: the pure parts are already covered (Tasks 5, 6); add `Tests/SwitcherCoreTests/ClaudeSettingsTests.swift::testIsHelperEnabled`.

**Interfaces — Consumes:** `HelperScript`, `ClaudeSettings`, `ActivePointerFile`. **Produces:** `HopLoginInstall.enable(initialActive: UUID?) throws` (writes the helper script `chmod 0700`, writes the pointer, merges settings via an atomic write of `~/.claude/settings.json`) and `HopLoginInstall.disable() throws` (removes the two settings keys; leaves the helper script and Keychain items in place; the Keychain **login** item is never touched). `HopLoginInstall.isEnabled() -> Bool`.

- [ ] **Step 1: Failing test** — `testIsHelperEnabled` asserts `isHelperEnabled` is true after `enableHelper` with the same path and false after `disableHelper`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3:** Implement `HopLoginInstall` (IO only; all transforms delegate to Tasks 5–6). Add a menu item "Enable Hop as my Claude login…" that explains (via `Alerts`) the global effect and that removing the setting reverts, then calls `enable`. The default TTL constant lives here (choose a few-second value; document it in a comment).
- [ ] **Step 4: Run** → PASS; manually: enabling writes the three files, `claude auth status` shows `authMethod: api_key_helper`, disabling restores the normal login.
- [ ] **Step 5: Commit** `feat: enable/revert Hop as the Claude login source`.

### Task 8: Add / renew / remove a setup-token for an account

**Files:** Modify `Sources/Hop/AddAccountFlow.swift` and/or `Sources/Hop/EditAccountsWindow.swift`, `Sources/Hop/AppModel.swift`; Test `Tests/SwitcherCoreTests/*` for any pure helper added.

**Interfaces — Consumes:** `SetupToken.normalize`, `TokenStore`, `Account.tokenAddedAt`. **Produces:** a Hop flow: paste a token for an account → `normalize` → `TokenStore.writeToken` → set `account.tokenAddedAt = Date()` and save via `AppModel.setAccounts`; "remove token" → `deleteToken` + clear `tokenAddedAt`. Reuses the existing paste UI pattern from the old login flow.

- [ ] **Step 1: Failing test** — if a pure "apply token result to account" helper is introduced, test it sets/clears `tokenAddedAt`; otherwise this task is UI wiring over tested units and its check is the manual step below.
- [ ] **Step 2: Run** the relevant filter → FAIL (if a unit was added).
- [ ] **Step 3:** Implement the add/renew/remove flow; on a `normalize` error show it inline; store through `TokenStore`.
- [ ] **Step 4:** Manual: add a token to an account → the Keychain item `local.hop.token / <uuid>` exists and the menu shows the account as token-backed; remove → item gone.
- [ ] **Step 5: Commit** `feat: add/renew/remove a per-account setup-token`.

### Task 9: Switch = flip the pointer

**Files:** Modify `Sources/Hop/SwitchController.swift`, `Sources/SwitcherCore/MenuModel.swift`, `Sources/Hop/MenuController.swift`, `Sources/Hop/CLI.swift`; Test `Tests/SwitcherCoreTests/MenuModelTests.swift`.

**Interfaces — Consumes:** `ActivePointer`, `HopState.activeAccountID`, `Account.tokenAddedAt`. **Produces:** `SwitchController.switchTo(_ account:) -> Bool` writes `ActivePointerFile` with `account.id` and sets `HopState.activeAccountID`, returning true; a row's active state comes from `HopState.activeAccountID` (the pointer), not from reading the live Keychain. `MenuModel.build` gains the active id from state and sets each row's `switchLabel` to `.active` (active), `.switchLogin` (has `tokenAddedAt`), or a new `.needsToken` (no token).

- [ ] **Step 1: Failing test** — `MenuModelTests`: given accounts where one is `activeAccountID` and one has `tokenAddedAt == nil`, assert the active row is `.active`, a token-backed non-active row is `.switchLogin`, and the tokenless row is `.needsToken`. Add `.needsToken` to `SwitchLabel`.
- [ ] **Step 2: Run** `swift test --filter MenuModelTests` → FAIL.
- [ ] **Step 3:** Update `MenuModel.build`'s signature to take `activeAccountID: UUID?` (from state) and `tokenBacked: Set<UUID>` (accounts with `tokenAddedAt != nil`) in place of the live-login attribution and `hasSavedLogin`; set labels. Update `SwitchController.switchTo` to write the pointer (atomic temp-file + `rename`) + state and `menuModel(...)`/`activeAccountID` to read from state. Wire `CLI switch`/`status` to the pointer. Keep desktop-profile rows unchanged.
- [ ] **Step 4: Run** → PASS; manual: with two token-backed accounts and a live `claude` session, switching in Hop moves the session to the other account on its next turn.
- [ ] **Step 5: Commit** `feat: switch the active account by flipping the pointer`.

### Task 10: Retire the old captured-login terminal switch

**Files:** Remove `Sources/SwitcherCore/SavedLogin.swift`, `Sources/Hop/UnknownLoginDialog.swift`; strip saved-login paths from `Sources/Hop/KeychainLoginStore.swift` (the `savedService` items), `Sources/SwitcherCore/SwitchCoordinator.swift`, `Sources/SwitcherCore/LoginAttribution.swift`, `Sources/Hop/SwitchController.swift` (`saveCurrentLogin`/`logInFirst`/`forgetSavedLogin`), and the dead `Account` fields (`email`/`organizationUuid`/`organizationName`/`savedLoginExpiresAt`) if nothing else reads them. Delete the now-dead tests; keep `LiveLogin`/`IdentityDocument` only if still used by anything (they are not, once switching no longer reads the live login — remove them too if unreferenced). Keep all desktop-profile (`folder`) code.

**Interfaces:** none produced; this task only removes code and the `menuModel` arguments it fed.

- [ ] **Step 1:** Delete the files/paths above. Update call sites so the project compiles.
- [ ] **Step 2: Run** `swift build` → compiles with no references to removed symbols.
- [ ] **Step 3: Run** `swift test` → the whole suite passes (dead tests removed, remaining ones green).
- [ ] **Step 4:** Manual: fresh `./build.sh`, enable Hop-as-login, add two tokens, switch both ways with a live session. Update `README.md` to describe the new model.
- [ ] **Step 5: Commit** `refactor: remove the old captured-login terminal switch`.

---

## Self-Review

1. **Spec coverage (Plan 1 scope):** secure token store (Tasks 1–3), pointer + helper + settings (4–7), add/renew/remove tokens (8), live switch (9), full pivot/retire (10). Usage bars and auto-failover are Plans 2–3, as scoped. ✓
2. **Step scan:** code steps carry signatures and the values the spec pins (service name, token prefix/length, settings keys, TTL); bodies are left to the implementer except the helper's guard logic, which the spec fixes. No "handle edge cases" lines. ✓
3. **Type consistency:** `TokenStore`/`FakeTokenStore`/`KeychainTokenStore`, `TokenStoreConst.service = "local.hop.token"` (Task 3) is the same service string the helper reads (Task 5) and the pointer feeds (Task 4/9); `tokenAddedAt` (Task 1) drives `tokenBacked`/`.needsToken` (Task 9). ✓
4. **Review Focus:** settings-key preservation (Task 6 round-trip test), token whitespace/prefix (Task 2), pointer→missing-token (Task 5 guard test), absent/empty/invalid settings (Task 6), clean revert (Task 7 manual). ✓
5. **Proportion:** ~10 tasks over a multi-subsystem pivot; step bodies are signatures/test-names, not transcripts. ✓

---

## Decisions left to the builder
- Exact default TTL value (Task 7) — a few seconds; pick and comment it.
- Whether `tokenAddedAt` needs a custom decoder (Task 1) — only if synthesized decoding rejects the missing key.
- The exact paste-UI reuse in Task 8 — follow the existing add-account UI.

## Verify on a real machine before merge (from the spec)
- Clean revert: removing `apiKeyHelper` returns Claude to its Keychain login.
- ~~The settings `env` block's TTL is honored for helper re-invocation~~ — **PROVEN 2026-11-07** in an isolated sandbox: the `env` block delivers the TTL, the value governs a lazy request-time refetch, and the live switch was shown in a real interactive TUI. Remaining real-machine checks: a visibly-distinct **healthy-A → healthy-B** swap (the spike had only one valid token), and that the switch feels immediate at the chosen production TTL.
- `security` reads of `local.hop.token` items don't prompt under Hop's signing (the mechanism `claude-as` already relies on).
