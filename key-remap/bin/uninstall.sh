#!/usr/bin/env bash
set -euo pipefail

BINDIR="$HOME/.local/bin"
CONFDIR="$HOME/.config/key-remap"
ZSHDIR="$HOME/.zshrc.d"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
say() { printf "${GREEN}✓${NC} %s\n" "$1"; }
info() { printf "${CYAN}→${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1"; }

# Ask before removing user data; defaults to keep.
confirm_yes() {
  local ans
  read -erp "$1 [y/N] " ans; ans=${ans:-N}
  [[ "$ans" == [yY]* ]]
}

echo "key-remap uninstall"
echo ""

# ── 0. Interactive terminal required ──
if [[ ! -t 0 ]]; then
  err "key-remap uninstall requires an interactive terminal"
  info "Run in a terminal, e.g.: bash <(curl -fsSL https://raw.githubusercontent.com/DevTora/Oh-Mac-Term/main/key-remap/bin/uninstall.sh)"
  exit 1
fi

# 1. Unload and remove LaunchAgent
LABEL="com.devtora.key-remap"
PLIST="$HOME/Library/LaunchAgents/com.devtora.key-remap.plist"
if launchctl print "gui/$(id -u)/$LABEL" &>/dev/null; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  say "LaunchAgent unloaded"
fi
if [[ -f "$PLIST" ]]; then
  rm -f "$PLIST"
  say "Removed $PLIST"
fi

# 2. Stop process and remove singleton lock
pkill -f "/\.local/bin/key-remap" 2>/dev/null || true
rm -f /tmp/key-remap.lock
sleep 0.5
say "Process stopped"

# 3. Remove binary
if [[ -f "$BINDIR/key-remap" ]]; then
  rm -f "$BINDIR/key-remap"
  say "Removed $BINDIR/key-remap"
fi
if [[ -f "$BINDIR/key-remap.swift" ]]; then
  rm -f "$BINDIR/key-remap.swift"
  say "Removed $BINDIR/key-remap.swift"
fi

# 4. Remove config
if [[ -d "$CONFDIR" ]]; then
  if confirm_yes "Remove config too?"; then
    if [[ "$CONFDIR" == "$HOME"/.config/key-remap ]]; then
      rm -rf "$CONFDIR"
      say "Removed $CONFDIR/"
    fi
  else
    say "Kept $CONFDIR/ (config retained)"
  fi
fi

# 5. Remove log
LOGFILE="$HOME/.local/var/log/key-remap.log"
if [[ -f "$LOGFILE" ]]; then
  if confirm_yes "Remove log too?"; then
    rm -f "$LOGFILE"
    rmdir "$(dirname "$LOGFILE")" 2>/dev/null || true
    say "Removed $LOGFILE"
  else
    say "Kept $LOGFILE (log retained)"
  fi
fi

# 6. Remove zsh integration
if [[ -f "$ZSHDIR/key-remap.zsh" ]]; then
  rm -f "$ZSHDIR/key-remap.zsh"
  say "Removed $ZSHDIR/key-remap.zsh"
fi
if [[ -f "$ZSHDIR/shift-enter.zsh" ]]; then
  if confirm_yes "Remove shift-enter.zsh too?"; then
    rm -f "$ZSHDIR/shift-enter.zsh"
    say "Removed $ZSHDIR/shift-enter.zsh"
  else
    say "Kept $ZSHDIR/shift-enter.zsh (Ctrl+J fallback remains)"
  fi
fi

# 7. Cleanup .zshrc + dir
ZSHRC="$HOME/.zshrc"
if [[ -L "$ZSHRC" ]]; then
  target="$(readlink "$ZSHRC")"
  [[ "$target" != /* ]] && target="$(dirname "$ZSHRC")/$target"
  ZSHRC="$target"
fi
rm -f "$ZSHDIR/.DS_Store"
rmdir "$ZSHDIR" 2>/dev/null || true
if [[ -d "$ZSHDIR" ]]; then
  say "Kept ~/.zshrc.d (still in use)"
else
  if [[ -f "$ZSHRC" ]] && grep -q '\.zshrc\.d/\*\.zsh\|^# Load modular configs' "$ZSHRC" 2>/dev/null; then
    awk '!/\.zshrc\.d\/\*\.zsh/ && !/^# Load modular configs from ~\/\.zshrc\.d\/$/ {lines[n++]=$0} END {while(n>0 && lines[n-1]~/^[[:space:]]*$/) n--; for(i=0;i<n;i++) print lines[i]}' "$ZSHRC" > "${ZSHRC}.tmp" && mv "${ZSHRC}.tmp" "$ZSHRC"
    say "Cleaned .zshrc"
  fi
fi

# 8. Accessibility (TCC) entry — manual removal only.
# key-remap is a bare binary without a bundle id, so `tccutil reset`
# cannot target it; the entry must be removed via System Settings UI.
info "TCC entry: remove \"key-remap\" in System Settings > Privacy & Security > Accessibility"
info "(path-based client; tccutil cannot reset it — select it and press \"-\")"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true

say "key-remap uninstalled"
