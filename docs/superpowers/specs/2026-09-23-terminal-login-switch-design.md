# Terminal login switching — design

Date: 2026-09-23. Status: approved in conversation, awaiting written review.

## Summary

Hop today switches between Claude *desktop* accounts by giving each one its own
profile folder. This design adds the terminal side: an account in Hop becomes one
claude.ai identity, and clicking it can **switch the machine-wide Claude Code
login** so every terminal, running or new, ends up on that account, with no
`/login` and nothing opened. Each account row also offers **Open Terminal**
(switch, then open a Terminal window running `claude`) and the existing
**Open Claude app**.

The mechanism reproduces exactly what `/login` writes: the login section of the
Keychain item Claude Code owns, plus the identity block in its state file. Hop
saves the outgoing login in the Keychain at the moment it switches away, so each
account's login survives without Hop ever performing a login itself.

## Goals

- Switch the active Claude Code account from the menu bar without opening
  anything. New terminals use it immediately; running sessions follow at their
  next token refresh.
- Never lose a login: switching away always saves the outgoing credential first.
- Never leave the machine half-switched or logged out: every failure stops before
  any write, with one alert saying what to do.
- Always show which account is currently active, in the menu and on the icon.
- Keep the desktop-profile behavior and upstream defaults unchanged.

## Non-goals

- Hop never logs in. It only moves logins Claude Code created.
- No per-terminal accounts (`CLAUDE_CONFIG_DIR` isolation). That cannot switch
  running terminals, which is the point of this feature.
- No support for API-key, Bedrock, Vertex, or profile credentials. Only the
  `claudeAiOauth` subscription login is moved.
- No notification-center notifications, no custom terminal apps in this version.

## What the spike established (2026-09-23, Claude Code 2.1.280, macOS 26.5.1)

These are undocumented internals. The design checks their shape at run time and
refuses to act when anything looks different.

1. **Storage.** One Keychain generic-password item, service
   `Claude Code-credentials`, account = the macOS user name. Its value is JSON:
   `{"claudeAiOauth": {accessToken, refreshToken, expiresAt, refreshTokenExpiresAt,
   scopes, subscriptionType, rateLimitTier}, "mcpOAuth": {...}}`. `/login` replaces
   only `claudeAiOauth`; `mcpOAuth` (per-server MCP tokens) carries over.
   Identity lives in `~/.claude.json` under `oauthAccount` (emailAddress,
   organizationName, accountUuid, organizationUuid, and flags). `expiresAt` and
   `refreshTokenExpiresAt` are Unix milliseconds.
2. **New processes switch instantly** after those two writes. `claude auth status`
   and one-shot calls used the new account at once.
3. **Running sessions keep their in-memory token** until it expires, about eight
   hours after issue. At that point they re-read the Keychain and continue as
   whatever account is there.
4. **Refresh tokens rotate** on every refresh. The previous refresh token is
   rejected afterwards. A copy of a login taken before a later refresh is dead.
   Rotation only happens while an account is active, so a saved login stays valid
   until its `refreshTokenExpiresAt` (about four weeks in the observed case).
5. **A dead token in the Keychain is destructive.** The next refresh attempt fails
   with "OAuth session expired and could not be refreshed" and Claude Code
   rewrites the item with `expiresAt: 0`, logging every terminal out.
6. **A failed `-p` call with a dead token also triggers (5).** So Hop must not
   "probe" a saved login by using it.

## Data model

### `Account` (SwitcherCore)

```swift
public struct Account: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: AccountColor
    public var folder: String?   // desktop profile; nil = default profile (unchanged)
    public var email: String?    // claude.ai identity; set when a login is captured
}
```

`accounts.json` moves to `version: 2`. Version 1 files decode as-is with
`email == nil` everywhere; the first save writes version 2. Nothing else changes
in the file.

Validation (`AccountValidation.validate`) adds: emails unique after trimming and
lowercasing. An account may have a folder, an email, both, or neither.

### Saved logins (Keychain)

One generic-password item per account with a saved login:

- service: `local.hop.login`
- account: the account's UUID string
- value: JSON `{"version": 1, "claudeAiOauth": <object copied verbatim>,
  "oauthAccount": <object copied verbatim>, "capturedAt": <ISO-8601>}`

Tokens are never written to files or logs. Deleting an account deletes its item.
"Forget saved login" in Edit accounts deletes the item and clears `email`.

### Hop state (`~/Library/Application Support/Hop/state.json`)

```json
{ "version": 1, "activeAccountID": "<uuid>", "writtenRefreshTokenSHA256": "<hex>" }
```

Written after every successful switch. The hash lets Hop recognize "this is still
the login I wrote" without storing the token. Missing or unparseable state is
treated as "Hop has not switched yet".

### Hotkey setting (`UserDefaults`, key `hotkeyAction`)

One of `off`, `switchLogin`, `openClaudeApp` (default, today's behavior),
`openTerminal`.

## Reading the live login

`LiveLogin` (SwitcherCore, pure) parses the Keychain value and the state file's
`oauthAccount`:

- Required for a valid login: `claudeAiOauth` is an object containing string
  `accessToken` and `refreshToken` and numeric `expiresAt` and
  `refreshTokenExpiresAt`; `oauthAccount.emailAddress` is a non-empty string.
- `expiresAt == 0` or missing tokens means **logged out**. The menu then shows
  "Not logged in" as the active account and Switch still works (there is nothing
  to save; step 2 below is skipped).
- Any other shape (no `claudeAiOauth` key at all, non-object, unexpected types)
  is **unrecognized**: Hop shows "Claude Code's login format changed. Hop won't
  touch it." and disables Switch until the next launch.

Keychain and file access sit behind protocols (`LoginStore`, `StateFile`) with
in-memory fakes for tests.

## The switch procedure

Given target account `T`:

1. **Read** the live login and the state record. Unrecognized shape → stop.
2. **Attribute and save the outgoing login** (skipped when logged out):
   - `email` = `oauthAccount.emailAddress`, compared case-insensitively.
   - If SHA-256(live refreshToken) equals `writtenRefreshTokenSHA256`, the login is
     the one Hop wrote for `activeAccountID`, whatever the identity block says
     (a stale session may have rewritten it). Save under `activeAccountID` and
     repair `oauthAccount` from that account's saved identity.
   - Else if an account has this `email`, save under it.
   - Else (unknown email): ask once with a sheet: "Save the current login
     (`email`) as:" a pop-up of accounts with no email, or "New account". New
     account gets `name = email`, next unused color, `email` set, and a generated
     profile folder from `NewAccountFolder.candidate(forName:)`, so a `nil` folder
     keeps meaning "the default desktop profile" exactly as today.
     Cancel → abort the switch, nothing written.
   - Saving means writing the Keychain item and, if the account had no `email`,
     setting it. If `T` turns out to be that same account, stop here with
     "already active".
3. **Check the target.** `T` must have a saved login (else the menu item already
   read "Log in first", but the CLI path re-checks). Its
   `refreshTokenExpiresAt` must be later than now + 60 s; else alert
   "`T`'s saved login expired on <date>. Log in as it once in Terminal." with a
   button that runs `claude auth login` in Terminal. Nothing written.
4. **Write**, in this order:
   1. Keychain: take the live value, replace only `claudeAiOauth` with `T`'s
      saved one, write back. Every other key (`mcpOAuth`, unknown future keys)
      is preserved byte-for-byte as parsed JSON.
   2. State file: read `~/.claude.json`, replace only `oauthAccount` with `T`'s
      saved identity, write to a temp file in the same directory with mode 0600,
      rename over the original. If the file cannot be parsed, stop **before**
      step 4.1 (parsing happens in step 1) so the Keychain is never changed
      without the identity.
   3. `state.json`: `activeAccountID = T.id`, hash of the refresh token written.
5. **Report.** Rebuild the menu. If claude processes are running, the header line
   reads "N terminal sessions running · they follow within 8 hours".

Undo is implicit: the previous account's login was saved in step 2, so switching
back is another switch.

### Attribution edge cases

- Token rotated *and* identity rewritten by a stale session: the hash won't match
  and the email points to the old account. Hop trusts the email (a manual `/login`
  is far more common). Documented limitation.
- Two Hops or a manual `security` edit: out of scope; the shape check still
  protects against garbage.

## Detecting running sessions

`RunningSessions.count()` lists processes owned by the current user whose
executable name is `claude` (via `proc_listpids` + `proc_name`). It is a hint for
the header line only; nothing depends on it.

## Menu

```
● Active: Work (ai@example.com)           (disabled header; "Not logged in" when logged out)
  3 terminal sessions running              (only when > 0)
────────────────────────────
● Personal                     ▸  ✓ Active                     (disabled)
                                  Open Terminal
                                  Open Claude app   /  ⌥ Quit Claude app
● Work                          ▸  Switch terminal login
                                  Open Terminal
                                  Bring Claude app to front  /  ⌥ Quit Claude app
● Account 3                     ▸  Log in first…               (no saved login)
                                  Open Terminal               (logs in first, see rules)
                                  Open Claude app
────────────────────────────
Save current login as new account…     (only when live email matches no account)
Add account…
Edit accounts…
Hotkeys                         ▸  Off / Switch login / • Open Claude app / Open Terminal
Launch at login
────────────────────────────
Quit Hop
```

Rules:

- The active account's row shows a checkmark (`state = .on`) in addition to its
  color dot. Exactly one row can be active; none when logged out or unknown.
- **Status bar icon**: a filled circle in the active account's color (same
  `Dot.image` used for rows, at template-off rendering), with the account name as
  tooltip. Falls back to today's gray `person.2` symbol when logged out, unknown,
  or unrecognized. ⌃⌥ hotkey hints keep appearing on rows when hotkeys are on.
- "Log in first…" opens Terminal running `claude auth login` and shows a one-line
  alert: "After you log in, switch to any other account once and Hop will save
  this one." (Capture happens on the next switch-away, per the procedure.)
- **Open Terminal** on an account without a saved login behaves like "Log in
  first…". On an account with one: switch if not active, then open Terminal.
- **Open Claude app** is unchanged: accounts created from a login already carry
  a generated folder, and the launcher creates the directory on first open.
  `nil` folder means the default desktop profile, as today.
- Hotkeys submenu: radio items; selection persists in `UserDefaults`. `Off`
  unregisters all Carbon hotkeys.
- Menu row hints and actions are computed by a pure `MenuModel` in SwitcherCore
  (inputs: accounts, live login summary, state record, running desktop instances,
  hotkey setting; output: rows with labels, enabled flags, checkmarks), so labels
  are unit-tested without AppKit.

## Terminal integration

`TerminalRunner.open(command:)` runs, via `NSAppleScript`:

```applescript
tell application "Terminal"
    activate
    do script "<command>"
end tell
```

`<command>` is `claude` or `claude auth login`; no user input is interpolated.
The first run triggers macOS's Automation prompt ("Hop wants to control
Terminal"); `Info.plist` already carries `NSAppleEventsUsageDescription`, whose
text is updated to mention Terminal. If the script fails (permission denied),
alert: "Allow Hop to control Terminal in System Settings › Privacy & Security ›
Automation, then try again."

Terminal.app only. The bundle identifier is a single constant so a later version
can make it a setting.

## Command line

Existing binary, existing dispatch in `CLI.swift`:

```
Hop status            # adds an "active" column and the email
Hop switch <n>        # runs the switch procedure; exit 0 on success, 1 on refusal, 2 on usage
Hop open <n>          # unchanged (desktop)
Hop quit <n>          # unchanged
```

The CLI reuses the same `SwitchCoordinator`; alerts become printed lines. The
unknown-email dialog cannot be shown from the CLI: `switch` then exits 1 with
"current login (<email>) isn't saved; save it from the menu first".

`build.sh --install` additionally creates `~/bin/hop` as a symlink to the app's
executable when `~/bin` exists, and prints the path either way.

## Edit accounts

Adds a read-only **Email** column and a **Forget saved login** button for the
selected account (deletes its Keychain item, clears `email`; refuses on the active
account with "switch to another account first"). Removing an account deletes its
Keychain item. The existing folder trash logic is unchanged.

## Error handling summary

| Situation | Behavior |
|---|---|
| Unrecognized credential shape | Alert once per launch; Switch disabled; nothing written |
| `~/.claude.json` unreadable or not JSON | Alert; nothing written (checked before any write) |
| Keychain read/write error | Alert with the OSStatus text; if the Keychain write succeeded but the state-file rename failed, Hop writes the previous Keychain value back and reports both |
| Target login expired | Alert with date and "Log in in Terminal" button; nothing written |
| Unknown live email, user cancels | Nothing written |
| Terminal automation denied | Alert pointing at Privacy & Security › Automation |
| Logged out at switch time | Skip saving; proceed |

## Testing

Unit tests (XCTest, SwitcherCore, no AppKit, fakes for Keychain/file/process):

- `LiveLoginTests`: valid shape, logged-out shape (`expiresAt: 0`), unrecognized
  shapes; `mcpOAuth` and unknown keys preserved through a merge.
- `IdentityFileTests`: replacing only `oauthAccount` in a document with many other
  keys, atomic write in a temp directory, refusal on invalid JSON.
- `AttributionTests`: hash match beats email; email match; unknown email; logged
  out.
- `SwitchCoordinatorTests`: full procedure against fakes — happy path, already
  active, expired target, cancel on unknown email, write-order on failures
  (Keychain restored when state write fails).
- `AccountStoreTests` additions: version 1 file decodes with nil emails and saves
  as version 2; email uniqueness in validation.
- `MenuModelTests`: labels, checkmark placement, header text, "Save current
  login" visibility, hotkey hints per setting.
- New-from-login accounts receive a generated, non-colliding folder at creation.

Manual, once, only when the user says so: one real switch between two accounts
with a fresh `/login` on each side, verifying `claude auth status` from a new
terminal, then switching back. A backup of `~/.claude.json` is taken first.

## Risks and mitigations

- **Undocumented internals may change.** Shape check at run time; refuse rather
  than guess. `LiveLogin` is the one place that knows the format.
- **Sessions switch silently up to eight hours later.** Shown in the header after
  a switch; documented in README.
- **Refresh-token expiry (about four weeks) while an account is inactive.** Rows
  whose saved login expires within seven days get the suffix "· login expires in
  N days"; the fix is one `/login` as that account.
- **Two accounts, one browser profile.** `claude auth login` opens the default
  browser; the user picks the account there. Out of Hop's hands; README notes it.

## README additions

A "Terminal accounts" section: what Switch does, the eight-hour note, that Hop
never logs in, how to add an account from a fresh `/login`, the Automation
permission, the `hop switch` command, and the expiry rule.
