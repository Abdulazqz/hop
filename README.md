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

- Click an account to open it, or bring it to the front if it's already open.
- Hold ⌥ to turn each row into **Quit <name>**.
- ⌃⌥1 … ⌃⌥9 jump to accounts by position.
- **Add account…** makes a new profile folder and opens Claude in it so you can sign in.
- **Edit accounts…** renames, recolors, reorders, and removes accounts.
- Quitting Hop leaves your Claude windows open.
- The first time it brings a window forward, macOS may ask to let Hop control System Events. Allow it.
- Each `./build.sh --install` re-signs the app, so macOS may ask for those permissions again.

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
`claude`. macOS asks once to let Hop control Terminal; allow it. The first time
Hop switches, macOS also asks whether Hop may read Claude Code's Keychain item:
choose **Always Allow**. `build.sh` signs Hop with your Apple Development
identity when Xcode has one, so that answer holds across rebuilds; without one
it signs ad hoc and macOS asks again after every rebuild. Hop reads the Keychain
only when you switch, save, or forget a login, never just to draw the menu.

A saved login lasts as long as its refresh token, about four weeks. Rows warn
seven days before. Log in as that account once to renew it.

**Hotkeys** in the menu chooses what ⌃⌥1…9 do: nothing, switch the login, open
the Claude app (the default), or open Terminal.

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
```

`./build.sh --install` links `hop` into `~/bin` when that folder exists; otherwise use the full path under `~/Applications/Hop.app/Contents/MacOS/Hop`.

`open` is for accounts that aren't running. To switch to one that's already running, use the menu or its hotkey.

## Develop

```bash
swift test
./build.sh
```

## License

MIT. See [LICENSE](LICENSE).

Hop is an independent project and isn't affiliated with or endorsed by Anthropic. "Claude" is a trademark of Anthropic.
