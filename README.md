# Hop

A menu-bar app for running several Claude accounts side by side. Desktop
accounts each get their own profile folder, so signing into one never signs
another out. Terminal accounts switch the Claude Code login for the whole
machine, live, with one click and no `/login` — and no account token is ever
written to a file.

## Requirements

- macOS 14 or later
- The [Claude desktop app](https://claude.ai/download). Hop finds it wherever macOS installed it; `/Applications` is the usual place.
- Xcode 15 or later (or its command line tools) to build

## Install

```bash
./build.sh --install
```

This builds `Hop.app`, copies it to `~/Applications`, and starts it. That is the
Applications folder inside your home folder, not the system-wide `/Applications`
that Finder's sidebar shows.
Turn on **Launch at login** from its menu.

## Use

- The line at the top of the menu shows the active account, and below it how many terminal sessions are running.
- The menu-bar icon is a filled circle in the active account's color, and a plain gray icon when no account is active.
- Each account row opens a submenu:
  - **Switch to this account** makes it the active account for every `claude` session. The item reads **Active** when it already is, and **Add a setup-token…** (which opens Edit accounts) when Hop holds no token for it yet.
  - **Open Terminal** switches to the account and opens a Terminal window running `claude`.
  - **Open Claude app** starts the desktop app for that account, or **Bring Claude app to front** when it's already running. Hold ⌥ to turn it into **Quit Claude app**.
- **Use Hop as my Claude login…** turns Hop into the login source for every `claude` session on this Mac (see below). Once on, the item reads **Stop using Hop as my Claude login** and reverts cleanly.
- **Hotkeys** chooses what ⌃⌥1 … ⌃⌥9 do for the accounts by position: Off, Switch login, Open Claude app (the default), or Open Terminal.
- **Add account…** makes a new profile folder and opens Claude in it so you can sign in.
- **Edit accounts…** renames, recolors, reorders, and removes accounts, and adds, replaces, or removes each account's setup-token.
- Quitting Hop leaves your Claude windows open — and leaves terminal switching working, since the login is served by a small script, not the app.
- The first time it brings a window forward, macOS may ask to let Hop control System Events. Allow it.
- macOS remembers the permissions it asks for as long as Hop keeps the same signing identity. `build.sh` uses your Apple Development identity when Xcode has one; if it has to sign ad hoc it says so, and macOS will ask again after each rebuild.

Accounts are stored in `~/Library/Application Support/Hop/accounts.json`. Each
account's setup-token lives in the macOS Keychain (service `local.hop.token`),
never in a file.

Don't launch Claude with your own `--user-data-dir` shortcuts alongside this:
two copies on the same folder is what signs accounts out.

## Terminal accounts (Hop as your Claude login)

Hop switches which account every `claude` session uses by owning the login,
the way `/login` does — but across all sessions at once and without ever
writing a token to disk.

**One-time setup.** Give each account a **setup-token**: run `claude setup-token`
signed in as that account (it opens your browser), copy the `sk-ant-oat01…`
token, and paste it into the account in **Edit accounts**. Hop validates it and
stores it in the Keychain. Then choose **Use Hop as my Claude login…**. Hop
writes an `apiKeyHelper` line into your existing `~/.claude/settings.json` and
picks a token-backed account to start active. (Hop refuses to enable until at
least one account has a token.)

**Switching.** Click an account and choose **Switch to this account**. Hop flips
a one-line pointer file naming the active account; every running `claude`
session — this app's, your terminal sessions, anything using `claude` — picks it
up on its next turn (within a few seconds), with nothing to restart.

**How it works.** When `apiKeyHelper` is set, Claude Code asks a script for
credentials on each request whose cached one is stale. Hop's script reads the
pointer file (an account UUID, not a secret) and prints that account's
setup-token from the Keychain. Switching accounts is just rewriting the pointer.
No token is ever written to a file at rest, and your `~/.claude` is not moved.

**It is global.** While on, `apiKeyHelper` governs *every* `claude` session on
this Mac, and it overrides a `CLAUDE_CODE_OAUTH_TOKEN` set in the environment —
the only way a session opts out is running under its own `CLAUDE_CONFIG_DIR`.

**Reverting.** **Stop using Hop as my Claude login** removes the `apiKeyHelper`
line; Claude Code goes straight back to its normal Keychain login. Your stored
tokens stay in the Keychain, so you can re-enable any time. Hop never deletes or
overwrites Claude Code's own login item.

**Renewing.** Setup-tokens expire after a few weeks. When one dies, its helper
call returns nothing and sessions fall back to their last working login; mint a
fresh token with `claude setup-token` and paste it in again with **Replace**.

Hop reads its Keychain tokens through Apple's `security` tool, the same way
Claude Code reads its own login, so macOS doesn't prompt and running sessions
keep working. (Writing through the Security framework instead would re-stamp
the item and every session would hit a "security wants to access key" dialog.)
`build.sh` signs Hop with your Apple Development identity when Xcode has a valid
one, so Keychain access holds across rebuilds; without one it signs ad hoc and
macOS asks again after each rebuild.

Hop can still record an account's email and organization for display (one
claude.ai account can belong to several organizations, each its own login), but
it no longer needs them to switch — the setup-token identifies the account.

## Troubleshooting

**No icon in the menu bar.** On MacBooks with a notch, macOS hides status items
once the right side of the menu bar is full, and it doesn't say so. Hop checks
for this a couple of seconds after it starts and shows an alert. Free some space
in System Settings › Menu Bar (Control Center on older macOS) by setting items
you don't need to "Don't Show in Menu Bar", then open Hop again. The ⌃⌥ hotkeys
and the command line keep working while the icon is hidden.

**"Your apiKeyHelper script is failing."** The active account's setup-token has
expired or was removed. Mint a fresh one with `claude setup-token` and paste it
in with **Replace** in Edit accounts, or switch to another token-backed account.

**"Claude app not found".** Hop launches the Claude desktop app and looks it up
by bundle identifier, so it can live anywhere macOS knows about. If it isn't
installed at all, Hop says so when it starts. Install it from
[claude.ai/download](https://claude.ai/download).

## Command line

```bash
hop status      # accounts, with * on the active one
hop switch 2    # make account 2 the active account
hop open 3      # open the desktop app for account 3
hop quit 3
```

`./build.sh --install` links `hop` into `~/bin` when that folder exists; otherwise use the full path under `~/Applications/Hop.app/Contents/MacOS/Hop`.

`open` starts the desktop app for an account that isn't running; use the menu to bring a running one forward. `switch` flips the active-account pointer (the account must have a setup-token).

## Develop

```bash
swift test
./build.sh
```

## License

MIT. See [LICENSE](LICENSE).

Hop is an independent project and isn't affiliated with or endorsed by Anthropic. "Claude" is a trademark of Anthropic.
