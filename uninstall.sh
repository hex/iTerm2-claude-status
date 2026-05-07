#!/usr/bin/env bash
# ABOUTME: Removes iTerm2-claude-status symlinks. Source repo is untouched.

set -euo pipefail

DATA_TARGET="$HOME/bin/claude-status"

remove() {
    local dst="$1"
    if [ -L "$dst" ]; then
        rm "$dst"
        echo "  Removed symlink: $dst"
        if [ -e "$dst.bak" ]; then
            mv "$dst.bak" "$dst"
            echo "  Restored backup: $dst"
        fi
    elif [ -e "$dst" ]; then
        echo "  Skipped (not a symlink): $dst"
    fi
}

echo "Uninstalling iTerm2-claude-status"
remove "$DATA_TARGET"

echo ""
echo "Manual cleanup still required:"
echo "  - Restore your previous statusLine command in ~/.claude/settings.json"
echo "    (or remove the statusLine block entirely)"
echo "  - Remove the Interpolated String component from iTerm2's status bar"
