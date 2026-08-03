# freezeterm

Locks your Terminal window in place. The window position and size are frozen so they survive reopening and restore.

## What it does

- Sets a fixed window position and column/row size via a Terminal profile
- Locks `com.apple.Terminal.plist` with the `uchg` flag so Terminal cannot overwrite the saved frame
- Locks Terminal's Saved Application State directory
- Disables session restore so the window doesn't jump around on relaunch
- The window then snaps back to the locked position on every relaunch

> **Scope**: the script sets `com.apple.Terminal NSQuitAlwaysKeepsWindows` (Terminal-only), so window restore for other apps is **not** affected.

> **What it locks**: it only freezes the *relaunch* position (the frame stored in the locked plist). While running, the window can still be dragged freely — it is not pinned. Any new position you drag to is ignored on the next relaunch, which returns to the locked frame.

## Usage

The script takes an explicit subcommand (no more automatic state detection):

```bash
./freezeterm.sh setup    # unlock, clear frame cache, import profile, move window to (POS_X, POS_Y)
./freezeterm.sh lock     # lock the current window position in place
./freezeterm.sh unlock   # unlock everything + restore Terminal window restore
```

Typical workflow:

```bash
./freezeterm.sh setup    # unlock + move window to target position
# Cmd+Q Terminal, reopen it
./freezeterm.sh lock     # lock the current (moved) position
```

### setup

1. Unlock the plist and Saved State (no-op if already unlocked)
2. Clear old frame caches
3. Import the profile colors/size from `Basic.terminal` (fallback: set size via `defaults`)
4. Move the window to `(POS_X, POS_Y)`
5. Tells you to `Cmd+Q` and reopen, then run `lock`

### lock

1. Lock `com.apple.Terminal.plist` with `chflags uchg`
2. Lock Terminal's Saved Application State directory
3. Disable session restore for Terminal (`com.apple.Terminal NSQuitAlwaysKeepsWindows` → false)
4. Report the locked window position

### unlock

1. Remove the `uchg` flags from the plist and Saved State
2. Delete the Terminal-level `NSQuitAlwaysKeepsWindows` key to restore macOS defaults

## Known behavior

- Relaunching immediately after `Cmd+Q` may briefly use the *previous* window position: macOS's WindowServer asynchronously saves a window-position snapshot on quit, and on a fast quit/reopen cycle that stale snapshot can win over the locked plist frame. Waiting a moment (or quitting normally after the window settles) makes the locked position take effect.
- This WindowServer behavior is outside the script's control; `chflags` and `NSQuitAlwaysKeepsWindows` cannot stop it. There is no fully reliable fix without third-party window management tools.

## Configuration

Adjust the top of `freezeterm.sh`:

| Variable | Meaning |
|---|---|
| `COLUMNS` | Window width in columns (default 80) |
| `ROWS` | Window height in rows (default 24) |
| `POS_X` | Window x position in points (default 40) |
| `POS_Y` | Window y position in points (default 40) |
| `PROFILE` | Terminal profile name (default `Basic`) |
| `COLOR_FILE` | Profile colors file (default `Basic.terminal` next to the script) |

## Requirements

- macOS
- Terminal.app
- The script must be run from a shell with permission to modify `~/Library/Preferences/com.apple.Terminal.plist` (Terminal.app should be quit or it may rewrite the file)

## Unlock

Run `./freezeterm.sh unlock`. Or manually:

```bash
chflags nouchg "$HOME/Library/Preferences/com.apple.Terminal.plist"
chflags nouchg "$HOME/Library/Saved Application State/com.apple.Terminal.savedState"
defaults delete com.apple.Terminal NSQuitAlwaysKeepsWindows   # or: defaults write ... -bool true
```

## License

MIT — see [LICENSE](../LICENSE)
