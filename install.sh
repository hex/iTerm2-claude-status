#!/usr/bin/env bash
# ABOUTME: Installs iTerm2-claude-status by symlinking claude-status onto PATH.
# ABOUTME: claude-status is a Claude Code statusLine command that drives both
# ABOUTME: the Claude Code footer AND iTerm2's status bar (via OSC 1337).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$REPO_DIR/src"

BIN_DIR="$HOME/bin"
DATA_TARGET="$BIN_DIR/claude-status"

mkdir -p "$BIN_DIR"

link() {
    local src="$1" dst="$2"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        echo "  Backing up existing $dst -> $dst.bak"
        mv "$dst" "$dst.bak"
    fi
    ln -sf "$src" "$dst"
    echo "  Linked $(basename "$src") -> $dst"
}

echo "Installing iTerm2-claude-status from $REPO_DIR"
link "$SRC_DIR/claude-status.sh" "$DATA_TARGET"

chmod +x "$SRC_DIR/claude-status.sh"

if ! command -v claude-status >/dev/null 2>&1; then
    echo ""
    echo "WARNING: $BIN_DIR is not on your PATH. Add it to your shell rc:"
    echo "  export PATH=\"\$HOME/bin:\$PATH\""
    echo "Otherwise Claude Code will not find claude-status."
fi

echo ""
echo "Next steps:"
echo ""
echo "1. Set claude-status as your Claude Code statusLine in ~/.claude/settings.json:"
echo ""
echo '       "statusLine": {'
echo '         "type": "command",'
echo '         "command": "~/bin/claude-status",'
echo '         "padding": 0'
echo '       }'
echo ""
echo "   If you have an existing statusLine (e.g. claude-powerline), replacing it"
echo "   means the Claude Code footer also switches to claude-status's output."
echo ""
echo "2. In iTerm2: Settings -> Profiles -> Session -> Configure Status Bar..."
echo "   Drag in an Interpolated String component and set:"
echo "     Expression: \(user.claudeStatus)"
echo "     Priority:   10"
echo ""
echo "3. (tmux users only) Add 'set -g allow-passthrough on' to your tmux.conf"
echo "   so the OSC 1337 sequence passes through to iTerm2."
echo ""
echo "4. The footer + iTerm2 bar populate after Claude Code's next render."
