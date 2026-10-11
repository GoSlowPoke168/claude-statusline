#!/bin/bash
# Installs the custom Claude Code statusline on Linux or macOS.
# Usage: ./install.sh [--water-session] [--water-lifetime] [--water-fun-fact]
set -euo pipefail

FLAGS=""
for arg in "$@"; do
    case "$arg" in
        --water-session|--water-lifetime|--water-fun-fact) FLAGS="$FLAGS $arg" ;;
        *) echo "Usage: ./install.sh [--water-session] [--water-lifetime] [--water-fun-fact]" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATUSLINE_SRC="$SCRIPT_DIR/statusline-command.sh"
STATUSLINE_DEST="$CLAUDE_DIR/statusline-command.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "Installing Claude Code statusline into $CLAUDE_DIR ..."
mkdir -p "$CLAUDE_DIR"
cp "$STATUSLINE_SRC" "$STATUSLINE_DEST"
chmod +x "$STATUSLINE_DEST"
if [ -n "$FLAGS" ]; then
    cp "$SCRIPT_DIR/water.sh" "$SCRIPT_DIR/water-facts.txt" "$SCRIPT_DIR/water-prices.txt" "$CLAUDE_DIR/"
else
    rm -f "$CLAUDE_DIR/water.sh" "$CLAUDE_DIR/water-facts.txt" "$CLAUDE_DIR/water-prices.txt" "$CLAUDE_DIR/water-learned-prices.txt"
fi

# --- ensure jq is available ---
if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found — attempting to install it..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y jq
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y jq
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm jq
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y jq
    elif command -v brew >/dev/null 2>&1; then
        brew install jq
    else
        echo "Could not detect a package manager to install jq automatically." >&2
        echo "Please install jq yourself, then re-run this script." >&2
        exit 1
    fi
fi

# --- merge (not overwrite) the statusLine key into settings.json ---
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

TMP="$(mktemp)"
jq --arg cmd "bash ~/.claude/statusline-command.sh$FLAGS" '.statusLine = {"type": "command", "command": $cmd}' "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"

echo "Done. Statusline installed at $STATUSLINE_DEST"
echo "settings.json updated at $SETTINGS (other keys preserved)."
echo "Restart Claude Code (or start a new session) to see it."
