#!/usr/bin/env bash
set -euo pipefail

BINDIR="$HOME/.local/bin"
CONFDIR="$HOME/.config/key-remap"
ZSHDIR="$HOME/.zshrc.d"

GREEN='\033[0;32m'; NC='\033[0m'
say() { printf "${GREEN}✓${NC} %s\n" "$1"; }

# Ask before removing user data; defaults to keep. Non-tty stdin keeps it too.
ask_remove() {
  if [[ -t 0 ]]; then
    local ans
    read -erp "Remove $1? [y/N] " ans; ans=${ans:-N}
    [[ "$ans" == [yY]* ]]
  else
    return 1
  fi
}

echo "key-remap uninstall"
echo ""

# 1. Stop process
pkill -f "/\.local/bin/key-remap" 2>/dev/null || true
sleep 0.5
say "Process stopped"

# 2. Remove binary
if [[ -f "$BINDIR/key-remap" ]]; then
  rm -f "$BINDIR/key-remap"
  say "Removed $BINDIR/key-remap"
fi
if [[ -f "$BINDIR/key-remap.swift" ]]; then
  rm -f "$BINDIR/key-remap.swift"
  say "Removed $BINDIR/key-remap.swift"
fi

# 3. Remove config
if [[ -d "$CONFDIR" ]]; then
  if ask_remove "config too"; then
    if [[ "$CONFDIR" == "$HOME"/.config/key-remap ]]; then
      rm -rf "$CONFDIR"
      say "Removed $CONFDIR/"
    fi
  else
    say "Kept $CONFDIR/ (config retained)"
  fi
fi

# 4. Remove log
LOGFILE="$HOME/.local/var/log/key-remap.log"
if [[ -f "$LOGFILE" ]]; then
  if ask_remove "log too"; then
    rm -f "$LOGFILE"
    rmdir "$(dirname "$LOGFILE")" 2>/dev/null || true
    say "Removed $LOGFILE"
  else
    say "Kept $LOGFILE (log retained)"
  fi
fi

# 5. Remove zsh integration
for f in "$ZSHDIR/key-remap.zsh" "$ZSHDIR/shift-enter.zsh"; do
  [[ -f "$f" ]] && rm -f "$f" && say "Removed $f"
done

# 6. Cleanup .zshrc + dir
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

say "key-remap uninstalled"
