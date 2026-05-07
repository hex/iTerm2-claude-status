#!/usr/bin/env bash
# ABOUTME: Installs iTerm2-claude-status by symlinking source files into deployment paths.
# ABOUTME: Targets: ~/bin/claude-status, ~/.claude/hooks/iterm-claude-status.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$REPO_DIR/src"

BIN_DIR="$HOME/bin"
HOOKS_DIR="$HOME/.claude/hooks"

DATA_TARGET="$BIN_DIR/claude-status"
HOOK_TARGET="$HOOKS_DIR/iterm-claude-status.sh"

mkdir -p "$BIN_DIR" "$HOOKS_DIR"

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
link "$SRC_DIR/iterm-claude-status.sh" "$HOOK_TARGET"

chmod +x "$SRC_DIR/claude-status.sh" "$SRC_DIR/iterm-claude-status.sh"

if ! command -v claude-status >/dev/null 2>&1; then
    echo ""
    echo "WARNING: $BIN_DIR is not on your PATH. Add it to your shell rc:"
    echo "  export PATH=\"\$HOME/bin:\$PATH\""
    echo "Otherwise the hook will not find claude-status at runtime."
fi

echo ""
echo "Next steps:"
echo ""
echo "1. Register the Stop hook in ~/.claude/settings.json. Add this to the"
echo "   .hooks.Stop[0].hooks array (or create the structure if missing):"
echo ""
echo '       {'
echo '         "type": "command",'
echo '         "command": "~/.claude/hooks/iterm-claude-status.sh",'
echo '         "timeout": 5'
echo '       }'
echo ""
echo "   For an existing settings.json with other Stop hooks, the safest"
echo "   programmatic merge is:"
echo ""
echo "       jq '.hooks.Stop[0].hooks += [{\"type\":\"command\",\"command\":\"~/.claude/hooks/iterm-claude-status.sh\",\"timeout\":5}]' \\"
echo "         ~/.claude/settings.json > /tmp/settings.new && \\"
echo "         mv /tmp/settings.new ~/.claude/settings.json"
echo ""
echo "2. In iTerm2: Settings -> Profiles -> Session -> Configure Status Bar..."
echo "   Drag in an Interpolated String component and set:"
echo "     Expression: \(user.claudeStatus)"
echo "     Priority:   10"
echo ""
echo "3. (tmux users only) Add 'set -g allow-passthrough on' to your tmux.conf"
echo "   so the OSC 1337 sequence passes through to iTerm2."
echo ""
echo "4. The status bar populates after the next Claude Code Stop hook fires."
