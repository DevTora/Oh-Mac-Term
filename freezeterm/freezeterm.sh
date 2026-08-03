#!/bin/bash
# Terminal window lock script
# Usage:
#   ./freezeterm.sh setup    unlock + clear frames + import profile + move window
#   ./freezeterm.sh lock     lock the current window position
#   ./freezeterm.sh unlock   unlock everything + restore global window restore

# Config(adjust as needed)
COLUMNS=80
ROWS=24
POS_X=40
POS_Y=40
PROFILE="Basic"
COLOR_FILE="$(dirname "$0")/${PROFILE}.terminal"

set -e

PLIST="$HOME/Library/Preferences/com.apple.Terminal.plist"
SAVED="$HOME/Library/Saved Application State/com.apple.Terminal.savedState"

usage() {
    echo "Usage: $0 {setup|lock|unlock}"
    echo "  setup   unlock, clear frame cache, import profile, move window to ($POS_X, $POS_Y)"
    echo "          then Cmd+Q Terminal and reopen before running 'lock'"
    echo "  lock    lock the current window position in place"
    echo "  unlock  unlock everything and restore the global NSQuitAlwaysKeepsWindows setting"
}

case "${1:-}" in
    setup)
        # ====== Setup: unlock + prepare ======
        echo "Unlocking and preparing"
        chflags nouchg "$PLIST" 2>/dev/null || true
        chflags nouchg "$SAVED" 2>/dev/null || true

        # Clear old frame cache (before modifying the plist, so defaults won't overwrite the python write)
        echo "[1] Clearing old frame cache"
        defaults delete com.apple.Terminal "NSWindow Frame TTWindow $PROFILE" 2>/dev/null || true
        defaults delete com.apple.Terminal "NSWindow Frame TTWindow" 2>/dev/null || true

        # Import profile colors
        echo "[2] Importing profile"
        if [ -f "$COLOR_FILE" ]; then
            PLIST_PATH="$PLIST" \
            COLOR_FILE="$COLOR_FILE" \
            PROFILE="$PROFILE" \
            COLUMNS="$COLUMNS" \
            ROWS="$ROWS" \
            python3 << 'PYEOF'
import os, plistlib
plist_path = os.environ['PLIST_PATH']
with open(plist_path, 'rb') as f:
    d = plistlib.load(f)
with open(os.environ['COLOR_FILE'], 'rb') as f:
    colors = plistlib.load(f)
profile = os.environ['PROFILE']
d.setdefault('Window Settings', {})[profile] = colors
ws = d['Window Settings'][profile]
ws['columnCount'] = int(os.environ['COLUMNS'])
ws['rowCount'] = int(os.environ['ROWS'])
with open(plist_path, 'wb') as f:
    plistlib.dump(d, f)
PYEOF
            # Force cfprefsd to re-read the plist from disk
            killall cfprefsd 2>/dev/null || true
        else
            echo "[2] Profile file not found"
            defaults write com.apple.Terminal "Window Settings.$PROFILE.columnCount" -integer $COLUMNS
            defaults write com.apple.Terminal "Window Settings.$PROFILE.rowCount" -integer $ROWS
        fi

        # Move window
        echo "[3] Moving window to ($POS_X, $POS_Y)"
        open -a Terminal 2>/dev/null
        sleep 0.5
        osascript -e "
            tell application \"Terminal\"
                if not (exists window 1) then return
                set position of window 1 to {$POS_X, $POS_Y}
            end tell
        " 2>/dev/null || true

        echo ""
        echo " Window moved to ($POS_X, $POS_Y)"
        echo " Manually Cmd+Q Terminal, then reopen it"
        echo " Then run '$0 lock' to lock"
        ;;

    lock)
        # ====== Lock current position ======
        echo "Locking"
        # Write the Terminal-only restore key BEFORE locking the plist
        echo "[1] Disabling session restore (Terminal only)"
        defaults write com.apple.Terminal NSQuitAlwaysKeepsWindows -bool false
        echo "[2] Locking Terminal.plist"
        chflags uchg "$PLIST"
        echo "[3] Locking Saved State"
        mkdir -p "$SAVED"
        chflags uchg "$SAVED" 2>/dev/null || true

        POS=$(osascript -e '
            tell application "Terminal"
                if not (exists window 1) then return "-, -"
                set pos to position of window 1
                return (item 1 of pos as text) & ", " & (item 2 of pos as text)
            end tell
        ' 2>/dev/null || echo "-, -")

        echo ""
        echo " Locked, window at ($POS)"
        echo " plist $(stat -f "%Sf" "$PLIST")"
        ;;

    unlock)
        # ====== Unlock everything + restore global setting ======
        echo "Unlocking"
        chflags nouchg "$PLIST" 2>/dev/null || true
        chflags nouchg "$SAVED" 2>/dev/null || true
        echo "[1] Unlocked Terminal.plist"
        echo "[2] Unlocked Saved State"

        echo "[3] Restoring Terminal window restore"
        # The script wrote com.apple.Terminal NSQuitAlwaysKeepsWindows to false.
        # Remove it to return Terminal to macOS defaults (other apps unaffected).
        # Also clean up the legacy global key from earlier versions.
        defaults delete com.apple.Terminal NSQuitAlwaysKeepsWindows 2>/dev/null || true
        defaults delete NSGlobalDomain NSQuitAlwaysKeepsWindows 2>/dev/null || true

        echo ""
        echo " Unlocked. Window restore re-enabled for all apps."
        echo " plist $(stat -f "%Sf" "$PLIST")"
        ;;

    *)
        usage
        exit 1
        ;;
esac
