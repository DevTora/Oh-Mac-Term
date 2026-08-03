#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDIR="$HOME/.local/bin"
CONFDIR="$HOME/.config/key-remap"
ZSHDIR="$HOME/.zshrc.d"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
say() { printf "${GREEN}✓${NC} %s\n" "$1"; }
info() { printf "${CYAN}→${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1"; }

echo "key-remap installer"
echo ""

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
  if [[ -t 0 ]]; then
    printf "  %s %s\n" "Reinstall?" "(overwrites binary and zsh scripts, keeps config)"
    read -erp "Continue? [Y/n]" yn; yn=${yn:-Y}
    case "$yn" in [nN]*) echo "Cancelled"; exit 0 ;; esac
  else
    info "Non-interactive (stdin not a tty): reinstalling"
  fi
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

# ── 3. Config ──
echo ""
info "Installing config..."
mkdir -p "$CONFDIR"
if [[ ! -f "$CONFDIR/config.json" ]]; then
  cp "$DIR/config/config.json" "$CONFDIR/config.json"
  say "$CONFDIR/config.json"
else
  info "$CONFDIR/config.json exists, skipped (edit to add rules)"
fi

# ── 4. Zsh integration ──
echo ""
info "Installing zsh integration..."
mkdir -p "$ZSHDIR"
cp "$DIR/zsh/key-remap.zsh" "$ZSHDIR/key-remap.zsh"
cp "$DIR/zsh/shift-enter.zsh" "$ZSHDIR/shift-enter.zsh"
say "$ZSHDIR/key-remap.zsh + $ZSHDIR/shift-enter.zsh"

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

# ── 6. Permission + start ──
echo ""
info "Grant accessibility permission to Terminal if the system dialog appears (15s window)"
info "key-remap inherits the launching terminal's permission"
check_permission() { "$BINDIR/key-remap" --check-permission 2>/dev/null; }
if ! check_permission && ! check_permission; then
  err "Accessibility permission not granted"
  info "Grant manually: System Settings -> Privacy & Security -> Accessibility -> add Terminal.app"
  info "Then run: $BINDIR/key-remap &"
  exit 1
fi
say "Accessibility permission ready"
echo ""
info "Starting key-remap..."
mkdir -p "$HOME/.local/var/log"
nohup "$BINDIR/key-remap" >>"$HOME/.local/var/log/key-remap.log" 2>&1 &
PID=$!; sleep 1
if kill -0 "$PID" 2>/dev/null; then
  say "key-remap started (pid $PID)"
else
  err "Failed to start. Debug: $BINDIR/key-remap"
  exit 1
fi

echo ""
say "key-remap installed"
echo ""
info "Usage:"
info "  Edit config  -> $CONFDIR/config.json"
info "  Reload       -> key-remap-reload (in terminal)"
info "  Shift+Enter  -> insert newline (ready)"
info "  Ctrl+J       -> insert newline (fallback, no permission needed)"
