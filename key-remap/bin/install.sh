#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
say() { printf "${GREEN}✓${NC} %s\n" "$1"; }
info() { printf "${CYAN}→${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1"; }

echo "key-remap installer"
echo ""

# ── 0. Interactive terminal required ──
if [[ ! -t 0 ]]; then
  err "key-remap installer requires an interactive terminal"
  info "Run in a terminal, e.g.: bash <(curl -fsSL https://raw.githubusercontent.com/DevTora/Oh-Mac-Term/main/key-remap/bin/bootstrap.sh)"
  exit 1
fi

# ── Paths and helpers ──
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDIR="$HOME/.local/bin"
CONFDIR="$HOME/.config/key-remap"
ZSHDIR="$HOME/.zshrc.d"

# Ask a yes/no question; default to no. Returns 0 only on y*/Y*.
confirm_yes() {
  local ans
  read -erp "$1 [y/N] " ans; ans=${ans:-N}
  [[ "$ans" == [yY]* ]]
}

# Refresh a file; keep a customized copy: same content is copied silently,
# differing content is kept unless the user confirms overwriting it.
update_file() {
  local src=$1 dst=$2 label=$3
  if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    say "Installed $dst"
  elif cmp -s "$src" "$dst"; then
    cp "$src" "$dst"
    say "$label unchanged - refreshed"
  elif confirm_yes "Overwrite customized $label?"; then
    cp "$src" "$dst"
    say "Rewrote $dst"
  else
    info "$label customized, kept ($dst)"
  fi
}

# ── 1. Environment check ──
info "Checking environment..."
case "$(uname -s)" in
  Darwin) ;;
  *) err "macOS only"; exit 1 ;;
esac
if ! command -v swiftc &>/dev/null; then
  err "Swift required (run: xcode-select --install)"
  exit 1
fi
for f in src/key-remap.swift config/config.json zsh/key-remap.zsh zsh/shift-enter.zsh; do
  if [[ ! -f "$DIR/$f" ]]; then
    err "Missing $f in $DIR"
    exit 1
  fi
done

if [[ -x "$BINDIR/key-remap" ]]; then
  echo ""
  info "key-remap already installed"
  printf "  %s %s\n" "Reinstall?" "(overwrites binary; customized config/zsh kept unless confirmed)"
  read -erp "Proceed? [y/N] " yn; yn=${yn:-N}
  case "$yn" in [yY]*) printf "\nReinstalling\n" ;; *) printf "\nCancelled\n\n"; exit 0 ;; esac
  pkill -f "/\.local/bin/key-remap" 2>/dev/null || true
  sleep 0.5
fi

# ── 2. Build ──
echo ""
info "Building binary..."
mkdir -p "$BINDIR"
if ! swiftc -O -o "$BINDIR/key-remap" "$DIR/src/key-remap.swift"; then
  err "Build failed"
  exit 1
fi
say "Built to $BINDIR/key-remap"

# ── 3. Zsh integration ──
echo ""
info "Installing zsh integration..."
mkdir -p "$ZSHDIR"
cp "$DIR/zsh/key-remap.zsh" "$ZSHDIR/key-remap.zsh"
say "$ZSHDIR/key-remap.zsh"
echo ""
update_file "$DIR/zsh/shift-enter.zsh" "$ZSHDIR/shift-enter.zsh" "shift-enter.zsh"

# ── 4. Config ──
echo ""
info "Installing config..."
mkdir -p "$CONFDIR"
update_file "$DIR/config/config.json" "$CONFDIR/config.json" "config.json"

# ── 5. .zshrc ──
echo ""
info "Checking ~/.zshrc..."
ZSHRC="$HOME/.zshrc"
if [[ -L "$ZSHRC" ]]; then
  target="$(readlink "$ZSHRC")"
  [[ "$target" != /* ]] && target="$(dirname "$ZSHRC")/$target"
  ZSHRC="$target"
fi
LOADER='for f in ${ZDOTDIR:-$HOME}/.zshrc.d/*.zsh(N); do source "$f"; done'
if grep -q '\.zshrc\.d/\*\.zsh' "$ZSHRC" 2>/dev/null; then
  info "$HOME/.zshrc already loads .zshrc.d, skipping"
elif ! grep -q '[^[:space:]]' "$ZSHRC" 2>/dev/null; then
  echo "# Load modular configs from ~/.zshrc.d/" > "$ZSHRC"
  echo "$LOADER" >> "$ZSHRC"
  say "Created ~/.zshrc with .zshrc.d loader"
else
  awk '{lines[NR]=$0} END {l=NR; while(l>0 && lines[l]~/^[[:space:]]*$/) l--; for(i=1;i<=l;i++) print lines[i]}' "$ZSHRC" > "${ZSHRC}.tmp"
  {
    echo ""
    echo "# Load modular configs from ~/.zshrc.d/"
    echo "$LOADER"
  } >> "${ZSHRC}.tmp"
  mv "${ZSHRC}.tmp" "$ZSHRC"
  say "Appended .zshrc.d loader to ~/.zshrc"
fi

# ── 6. LaunchAgent ──
echo ""
info "Installing LaunchAgent..."
LABEL="com.devtora.key-remap"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/com.devtora.key-remap.plist"
mkdir -p "$PLIST_DIR" "$HOME/.local/var/log"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$BINDIR/key-remap</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$HOME/.local/var/log/key-remap.log</string>
	<key>StandardErrorPath</key>
	<string>$HOME/.local/var/log/key-remap.log</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST"
# stop stray instances spawned outside launchd and clear a stale lock,
# otherwise flock keeps the launchd copy from starting
pkill -f "/\.local/bin/key-remap" 2>/dev/null || true
rm -f /tmp/key-remap.lock
if launchctl print "gui/$(id -u)/$LABEL" &>/dev/null; then
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  say "LaunchAgent restarted"
else
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  say "LaunchAgent loaded"
fi

# ── 7. Permission ──
echo ""
info "Checking accessibility permission..."
# Judge authorization by whether the launchd-managed instance stays alive past
# its own 15s wait window (it exits on denial). Never run the binary directly
# from this script — TCC would attribute it to the hosting terminal app.
last_start=$(date +%s)
launchctl kickstart -k "gui/$(id -u)/$LABEL"
info "A dialog naming key-remap should appear — allow it (or use the opened pane)"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
granted=""
for _ in {1..24}; do
  sleep 5
  if pgrep -f "/\.local/bin/key-remap" >/dev/null; then
    if (( $(date +%s) - last_start >= 16 )); then granted=1; break; fi
  else
    launchctl kickstart -k "gui/$(id -u)/$LABEL"
    last_start=$(date +%s)
  fi
done
if [[ -z "$granted" ]]; then
  err "Accessibility permission not granted for key-remap"
  info "Enable \"$BINDIR/key-remap\" in Accessibility, then run:"
  info "  launchctl kickstart gui/\$UID/$LABEL"
  exit 1
fi
say "Accessibility permission granted"

launchctl kickstart -k "gui/$(id -u)/$LABEL"
sleep 1
if pgrep -f "/\.local/bin/key-remap" >/dev/null; then
  say "key-remap running via LaunchAgent"
else
  err "Failed to start. Debug: tail \$HOME/.local/var/log/key-remap.log"
  exit 1
fi

echo ""
say "key-remap installed"
echo ""
info "Usage:"
info "  Edit config  -> $CONFDIR/config.json"
info "  Start/restart -> key-remap-start (in terminal)"
info "  Reload       -> key-remap-reload (in terminal)"
info "  Shift+Enter  -> insert newline (ready)"
info "  Ctrl+J       -> insert newline (fallback, no permission needed)"
echo ""
