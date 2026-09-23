# Hop

A menu-bar app for running several Claude desktop accounts side by side. Each
account lives in its own profile folder, so signing into one never signs
another out.

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

**Nothing in `/Applications`.** `./build.sh --install` puts Hop in
`~/Applications`, inside your home folder.

## Command line

```bash
"$HOME/Applications/Hop.app/Contents/MacOS/Hop" status
"$HOME/Applications/Hop.app/Contents/MacOS/Hop" open 3
"$HOME/Applications/Hop.app/Contents/MacOS/Hop" quit 3
```

`open` is for accounts that aren't running. To switch to one that's already running, use the menu or its hotkey.

## Develop

```bash
swift test
./build.sh
```

## License

MIT. See [LICENSE](LICENSE).

Hop is an independent project and isn't affiliated with or endorsed by Anthropic. "Claude" is a trademark of Anthropic.
