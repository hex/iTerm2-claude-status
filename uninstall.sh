#!/usr/bin/env bash
# ABOUTME: Removes iTerm2-claude-status symlinks. Source repo is untouched.

set -euo pipefail

DATA_TARGET="$HOME/bin/claude-status"
HOOK_TARGET="$HOME/.claude/hooks/iterm-claude-status.sh"

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
remove "$HOOK_TARGET"

echo ""
echo "Manual cleanup still required:"
echo "  - Remove the iterm-claude-status hook entry from ~/.claude/settings.json"
echo "  - Remove the Interpolated String component from iTerm2's status bar"
