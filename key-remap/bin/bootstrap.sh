#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://codeload.github.com/DevTora/Oh-Mac-Term/tar.gz/refs/heads/main"

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

curl -fsSL "$REPO_URL" | tar xz -C "$BUILD_DIR"

INSTALL="$(find "$BUILD_DIR" -maxdepth 4 -path '*/key-remap/bin/install.sh')"
[[ -n "$INSTALL" && -f "$INSTALL" ]] || { echo "install.sh not found in fetched repo" >&2; exit 1; }
"$INSTALL"
