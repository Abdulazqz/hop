# Hop as a Secure Multi-Account Control Center — Design

**Date:** 2026-11-07
**Status:** Design — three open decisions resolved 2026-11-07 (see "Decisions made"); pending final approval before planning. Nothing built yet.
**Supersedes the switching mechanism of:** `2026-09-23-terminal-login-switch-design.md` (the multi-org *identity* model from that work is kept; see "Relationship to the existing design").

## Intent and why

Today the user runs several Claude accounts (e.g. `ai@rella.sa` in two orgs, `ms6rb2201`, `ms6rb2202`). Two pains:

1. **They can't see each account's usage without logging into it.** They want to glance at every account's weekly and 5-hour limits at once, as colored bars like claude.ai (blue → yellow → red).
2. **Switching accounts mid-work is clumsy.** When the active account hits a limit, the only thing that reliably switches *every running `claude` session at once* is Claude Code's built-in `/login`. Hop's current Keychain-login swap updates identity (`/status` shows the new account) but a running session keeps using its cached token, so it stays limited. The user wants Hop to own switching and have it take effect live, across all sessions, the way `/login` does.

The hard constraint that shaped everything: **no account token may sit in a plaintext file at rest** (the user explicitly rejected that), and **their existing `~/.claude` must not be relocated**.

The design makes Hop the one place to add an account once, see every account's live usage, and switch which account *all* running sessions use — live, and with every token staying in the macOS Keychain.

## How it works (the proven mechanism)

All of the following was verified in an isolated sandbox against Claude Code **v2.1.319** (temp `CLAUDE_CONFIG_DIR`s; the real login was never touched):

- **Credential per account = a `claude setup-token`** (`sk-ant-oat01…`), stored in the **macOS Keychain** (the same place `claude-as` keeps `claude-profile-<name>` items). It authenticates on the **subscription** (first-party), not API billing.
- **`apiKeyHelper`** is a normal Claude Code setting (set in the user's existing `~/.claude/settings.json` — **no config-dir move**). When set, Claude Code calls the helper for credentials and *does not read the Keychain login or OAuth*. The helper:
  - reads a **pointer file** that holds only the **active account's name** (not a secret),
  - runs `security find-generic-password -s <hop-item-for-that-account> -w` to read that account's token from the Keychain,
  - prints the token to stdout.
- **`CLAUDE_CODE_API_KEY_HELPER_TTL_MS`** (set short) controls when the helper is re-run. It is **not a background timer**: Claude re-invokes the helper **lazily, on the next API request whose cached credential is older than the TTL** — an idle session does not refetch. The TTL *value* governs the boundary (proven 2026-11-07: set via the settings `env` block, TTL=3 s refetched between ~13 s-spaced turns while TTL=20 s did not and only refetched a turn sent >20 s after the last fetch). Because one user turn makes many API requests in the tool loop, a switch can be adopted **mid-turn**, not only at a turn boundary.
- **Switching = Hop rewrites the pointer file.** The helper re-reads the pointer on every invocation, so on the **next request whose cached cred is older than the TTL** (with a few-second TTL, effectively the next turn) every running session's helper call returns the new account's token — **all sessions switch live**, hand-started terminal sessions included.
- **Proven end to end:** a running session that was *logged out* (pointer named no account) recovered to *working* mid-session the instant the pointer was flipped to a valid account — nothing could have "fallen back," so this is unambiguous live adoption. Shown in both a `-p` stream-json session and a real **interactive TUI** session (2026-11-07). *One inch not directly shown:* a visibly-distinct healthy-A → healthy-B swap (only one valid setup-token was on hand); the mechanism makes it follow, since the helper re-reads the pointer each stale request and adopts whatever token it returns.
- **Resilience:** ~~if the helper returns an empty/invalid token, Claude Code falls back to the last *working* token instead of breaking.~~ *(Corrected 2026-11-08 during Plan 1 review, confirmed against Claude Code 2.1.319 + the auth docs: an **empty** helper makes Claude Code report "apiKeyHelper is failing" within ~3 attempts; it does **not** fall back to the Keychain login while `apiKeyHelper` is set. The helper must still never emit a partial/wrong token. Graceful degradation onto a healthy account is Hop's own auto-failover, Plan 3.)*

**Usage reading (same tokens):** a single 1-token inference call with an account's setup-token returns utilization in response headers:
`anthropic-ratelimit-unified-7d-utilization` / `-7d-reset` / `-7d-status`, and `-5h-*` **when that account has a 5-hour limit and recent activity**. (The `/api/oauth/usage` GET needs `user:profile` scope, which setup-tokens lack → 403, so headers are the path.) Hop reads these for each account to draw the bars.

## Goals

- See every account's **weekly and 5-hour usage** at a glance in the Hop menu, as blue→yellow→red bars, without logging into each account.
- **Switch the active account live** so every running `claude` session (including ones the user started by hand in a terminal) picks it up on its next turn — a true replacement for `/login`.
- **Every token stays in the Keychain.** The only things on disk are an account-name pointer and a secret-free helper script.
- **No relocation of `~/.claude`.** The user keeps all their settings, plugins, skills, hooks, and history.
- Add/remove/renew accounts from Hop.
- **Automatically fail over** to a healthy account when the active one is exhausted or its token dies, with a config switch to turn this off.

## Non-goals

- Reading usage via the `/api/oauth/usage` endpoint (blocked by scope; headers suffice).
- Auto-refreshing setup-tokens behind the user's back (see anti-goals). Hop detects expiry and prompts a re-mint.
- Changing the account for an API request already **in flight** (you can't un-send a request). A switch is adopted by the session's next request past the TTL — the next turn, or a later request **within** the current turn, but never retroactively. *(The earlier "only next turn" wording was corrected by the 2026-11-07 spike.)*
- Managing non-Claude / third-party-provider auth.

## Anti-goals (these would make it a failure even if it "worked")

- **A token written to any plaintext file at rest.** This is the whole reason the earlier file-credential approach was rejected. The helper reads from the Keychain at call time; nothing persists a token to disk.
- **Relocating or forking the user's `~/.claude`.**
- **Silently minting or rotating OAuth refresh tokens.** Hop does not perform OAuth refresh flows. Accounts are authenticated by tokens the *user* created with `claude setup-token`.
- **A switch that corrupts the live login** (the September lockout). This design never swaps the Keychain *login* item during a switch; it only flips a name in a pointer file.

## Constraints

- macOS 14+, Swift Package Manager; Hop is a menu-bar app (`Hop`) + pure logic (`SwitcherCore`). (Unchanged.)
- Keychain access goes through the Apple `security` CLI, never a Security-framework write (consistent with existing Hop discipline; avoids partition-list re-stamping and lockouts). Reads of Hop-created items via `security` do not prompt (verified).
- Tokens are passed to Claude Code via the helper's **stdout** (a pipe), never argv — so they don't appear in process listings. Same exposure profile as `CLAUDE_CODE_OAUTH_TOKEN`, which the user already relies on via `claude-as`.
- Setup-tokens expire (observed `loginExpiresAt` ~weeks out) and are also subject to weekly/5-hour limits. Hop must treat a dead token as an expected, recoverable state.
- `apiKeyHelper` set in `~/.claude/settings.json` is **global**: it governs *every* `claude` session on the machine (including the user's farm/commander sessions). This is intended (it's what makes switching universal) but makes Hop the single source of auth — the "Automatic failover" and "Failure modes" sections cover the mitigation. **Precedence (proven 2026-11-07):** `apiKeyHelper` also **overrides a `CLAUDE_CODE_OAUTH_TOKEN` set in the environment** — a session cannot opt out of Hop via that env var; the only opt-out is running it under a separate `CLAUDE_CONFIG_DIR` with no helper. The **farm runs on da2 (a separate machine)** and is unaffected unless Hop is installed there; on the laptop, enabling Hop governs commander sessions and any local `claude-as` as well.

## The how, as decided

Decisions the user and the investigation settled. Items left open are in "Open decisions."

### Account model
- An **account** = { user-facing label, setup-token (in Keychain), optional (email, organizationUuid) when known, cached usage snapshot + timestamp, last-known health }.
- Tokens live in **Hop-owned Keychain items** (Hop namespace, e.g. `local.hop.account.<id>`), created/read/removed via the `security` CLI. (Recommendation; see open decision #4 about reusing `claude-profile-*`.)
- Setup-tokens do not expose the account's email/org to Hop, so the **label is user-provided** when adding the account (as `claude-as` does). (email, org) is populated only when Hop can derive it; the menu is keyed by label. — *Author's call; confirm.*

### Adding an account
1. User runs `claude setup-token` under the target account (interactive, in their browser) and pastes the `sk-ant-oat01…` token into Hop, with a label. (Mirrors `claude-as add`.)
2. Hop validates the token with one minimal inference call (which also fetches the first usage snapshot) and stores it in the Keychain.

### Switching (the `/login` replacement)
- Hop writes the chosen account's name to the **pointer file**.
- On each session's next request with a stale credential (within one TTL of the flip; with a few-second TTL, the next turn), its helper call returns that account's token → all sessions switch. The Hop menu marks the active account from the pointer.
- No Keychain *login* item is touched; the switch is a single small file write.

### Automatic failover (auto-switch)
When the active account hits a limit or its token dies, Hop automatically flips the pointer to the healthiest other account, so every running session moves to a working account on its next turn. A config switch turns this off (then Hop only surfaces the problem and waits for a manual switch). **Default: on.**

Because Hop already polls every account's usage, it knows each account's health. Guardrails, learned directly from the user's farm proxy (see the farm's account-switching notes — these exact failures caused real outages):
- **Only switch to a genuinely healthy target:** token valid, not weekly- or 5-hour-exhausted, not org-disabled (403). Never fail over onto a limited/dead account — the farm's worst outages came from rotating onto a weekly-dead or 403 account.
- **Debounce:** don't switch again within a short window of the last switch, to avoid flapping between two near-exhausted accounts.
- **No healthy target → stay put and surface it loudly** ("all accounts limited"); never switch to something worse. Warn when fewer than two healthy accounts remain.
- **Make it visible:** notify the user when an auto-switch happens and why (which account was exhausted, which took over), so a silent account change never confuses them.

Auto-switch takes effect on each session's next turn (like a manual switch); Hop cannot retry a request already in flight. This doubles as the mitigation for the global single-source-of-auth risk: a dead *active* token triggers an automatic move to a healthy account rather than leaving every session stuck.

### Setup / install (one time, done by Hop)
- Hop writes `"apiKeyHelper": "<path to Hop's helper script>"` into `~/.claude/settings.json` and sets `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` to a short value, and installs the helper script + pointer file in Hop's application-support directory.
- Hop presents this as an explicit, reversible "enable Hop as my Claude login" action, with a clear explanation of the global effect.
- **Revert:** removing the `apiKeyHelper` line restores Claude Code's normal Keychain-login behavior; the Keychain login item is never deleted, so revert is clean. — *Reasoned from the docs ("keychain never read" is an override, not a deletion); the builder must verify on a real machine before shipping.*

### Usage display
- For each account, on a timer (and on explicit refresh), Hop makes one minimal inference call with that account's token and reads the `anthropic-ratelimit-unified-*` headers.
- Render **one bar per limit the account actually reports** (5-hour and/or weekly) — never a fake "0%" bar for a limit an account doesn't have (Anthropic has stripped the 5-hour limit from some accounts).
- Color by utilization: blue (low) → yellow (mid) → red (high). Thresholds **blue <50 %, yellow 50–85 %, red >85 %** (decided 2026-11-07).
- Show a freshness label ("as of N min ago"). The **active** account can be refreshed most often; idle accounts less so.

### Failure modes (must be designed for, not afterthoughts)
- **Dead/expired token:** the helper returns empty → Claude Code shows "Your apiKeyHelper script is failing" / falls back to the last working token. Hop detects this (its own usage poll gets a 401/err) and, with auto-switch on, fails over to a healthy account (see "Automatic failover"); it also surfaces "re-authenticate <account>" (re-run `claude setup-token`) for the dead one.
- **Hop not running / helper script missing:** sessions can't get credentials. Mitigation: the helper is a standalone script that works without the Hop app running (it only reads a pointer file + Keychain); the Hop *app* is needed only to *change* the pointer or add accounts. Document the "remove the apiKeyHelper line to revert" escape hatch prominently.
- **Polling cost / observer effect:** each usage poll is a real 1-token inference call that counts as that account's own usage and opens a 5-hour window on an otherwise-idle account. Keep the cadence modest and document it. — *Author's call; confirm cadence.*

## Relationship to the existing design

The **multi-org identity model** from the 2026-09-23 work (a login is `(email, organizationUuid)`, not just an email) is retained wherever Hop knows an account's identity, and the menu/UI shell is reused. What changes is the **credential store and switch mechanism**: instead of swapping the live Keychain *login* blob between saved copies, Hop stores a setup-token per account and switches by flipping the `apiKeyHelper` pointer. The saved-login-blob switching path is **removed** (full pivot, decided 2026-11-07).

## What's left to the builder

- Swift implementation across `SwitcherCore` (account model, pointer, usage parsing from headers) and `Hop` (menu bars + colors, add/renew/remove flows, the install/revert of the `apiKeyHelper` setting).
- The exact helper script (robust: missing pointer → default account; dead token → fall back to a known-good account; never emit a partial token).
- Header parsing for the full `anthropic-ratelimit-unified-*` set, including overage/representative-claim, and the mapping to bars.
- Verifying on a real machine: the clean revert (removing `apiKeyHelper` restores Keychain login), and that `security` reads of Hop's items never prompt under Hop's signing.
- TDD throughout (SwitcherCore is pure and unit-testable), matching the existing suite's style.

## Decisions made (2026-11-07)

1. **Full pivot.** Hop's old Keychain-login swap is removed; the apiKeyHelper model is the only switch mechanism.
2. **Automatic failover, on by default, with a config switch to disable** (see "Automatic failover"). This is also the mitigation for the global single-source-of-auth risk: a dead active token triggers an automatic move to a healthy account rather than leaving every session stuck.
3. **Usage colors:** blue <50 %, yellow 50–85 %, red >85 %.

No open decisions remain.
