#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://codeload.github.com/DevTora/Oh-Mac-Term/tar.gz/refs/heads/main"

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

curl -fsSL "$REPO_URL" | tar xz -C "$BUILD_DIR"

"$BUILD_DIR/Oh-Mac-Term-main/key-remap/bin/install.sh"
