# Hop

A menu-bar app for running several Claude accounts side by side. Desktop
accounts each get their own profile folder, so signing into one never signs
another out. Terminal accounts switch the Claude Code login for the whole
machine with one click, with no `/login`.

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

- The line at the top of the menu shows the active terminal account, and below it how many terminal sessions are running.
- The menu-bar icon is a filled circle in the active account's color, and a plain gray icon when no account is active.
- Each account row opens a submenu:
  - **Switch terminal login** makes it the terminal account. The item reads **Active** when it already is, and **Log in first…** when Hop has no saved login for it yet.
  - **Open Terminal** switches if needed and opens a Terminal window running `claude`.
  - **Open Claude app** starts the desktop app for that account, or **Bring Claude app to front** when it's already running. Hold ⌥ to turn it into **Quit Claude app**.
- **Save current login (…) as new account…** appears when Terminal is logged in as an account Hop hasn't saved.
- **Hotkeys** chooses what ⌃⌥1 … ⌃⌥9 do for the accounts by position: Off, Switch login, Open Claude app (the default), or Open Terminal.
- **Add account…** makes a new profile folder and opens Claude in it so you can sign in.
- **Edit accounts…** renames, recolors, reorders, and removes accounts. Removing an account also deletes its saved terminal login.
- Quitting Hop leaves your Claude windows open.
- The first time it brings a window forward, macOS may ask to let Hop control System Events. Allow it.
- macOS remembers the permissions it asks for as long as Hop keeps the same signing identity. `build.sh` uses your Apple Development identity when Xcode has one; if it has to sign ad hoc it says so, and macOS will ask again after each rebuild.

Accounts are stored in `~/Library/Application Support/Hop/accounts.json`.

Don't launch Claude with your own `--user-data-dir` shortcuts alongside this:
two copies on the same folder is what signs accounts out.

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
`claude`. macOS asks once to let Hop control Terminal; allow it. Hop reads and
writes Claude Code's Keychain item through Apple's `security` tool, the same way
Claude Code does, so macOS doesn't ask about it and running `claude` sessions
keep their access. (Writing it through the Security framework instead would
re-stamp the item with Hop and every session would hit a "security wants to
access key" dialog.) Hop touches the Keychain only when you switch, save, or
forget a login, never just to draw the menu. Hop's own saved logins are
Keychain items Hop creates; `build.sh` signs Hop with your Apple Development
identity when Xcode has a valid one, so access to them holds across rebuilds.
Without one it signs ad hoc and macOS asks about them after every rebuild.

A saved login lasts as long as its refresh token, about four weeks. Rows warn
seven days before. Log in as that account once to renew it.

One claude.ai account can belong to several organizations (a personal plan and
a team, say), and each organization is a separate login: `/login` asks which one
you want. Hop keeps them apart as separate accounts, matching a login by email
*and* organization, and shows the organization next to the email in the menu,
in Edit accounts, and in `hop status`. Accounts saved by an older Hop have no
organization recorded yet; Hop learns it from the saved login the next time you
switch, and never saves one organization's login over another's.

Accounts that use a separate `CLAUDE_CONFIG_DIR` are not supported; Hop manages
the default login only.

## Troubleshooting

**No icon in the menu bar.** On MacBooks with a notch, macOS hides status items
once the right side of the menu bar is full, and it doesn't say so. Hop checks
for this a couple of seconds after it starts and shows an alert. Free some space
in System Settings › Menu Bar (Control Center on older macOS) by setting items
you don't need to "Don't Show in Menu Bar", then open Hop again. The ⌃⌥ hotkeys
and the command line keep working while the icon is hidden.

**"Claude app not found".** Hop launches the Claude desktop app and looks it up
by bundle identifier, so it can live anywhere macOS knows about. If it isn't
installed at all, Hop says so when it starts. Install it from
[claude.ai/download](https://claude.ai/download).

## Command line

```bash
hop status      # accounts, with * on the active terminal login
hop switch 2    # make account 2 the terminal login
hop open 3      # open the desktop app for account 3
hop quit 3
hop probe-login   # what Hop sees in Claude Code's login, no secrets
```

`./build.sh --install` links `hop` into `~/bin` when that folder exists; otherwise use the full path under `~/Applications/Hop.app/Contents/MacOS/Hop`.

`open` starts the desktop app for an account that isn't running; use the menu to bring a running one forward. `switch` changes the terminal login.

## Develop

```bash
swift test
./build.sh
```

## License

MIT. See [LICENSE](LICENSE).

Hop is an independent project and isn't affiliated with or endorsed by Anthropic. "Claude" is a trademark of Anthropic.
