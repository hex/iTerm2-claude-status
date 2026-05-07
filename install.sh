#!/usr/bin/env bash
# ABOUTME: Installs iTerm2-claude-status by symlinking claude-status onto PATH.
# ABOUTME: claude-status is registered as a Claude Code Stop hook that emits
# ABOUTME: OSC 1337 SetUserVar to /dev/tty after each assistant turn.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$REPO_DIR/src"

BIN_DIR="$HOME/bin"
DATA_TARGET="$BIN_DIR/claude-status"

# Pre-flight dependency check.
missing=()
for dep in jq; do
    command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: required dependencies missing: ${missing[*]}" >&2
    echo "Install with: brew install ${missing[*]}" >&2
    exit 1
fi

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
echo "1. Register claude-status as Stop, SessionStart, AND SessionEnd hooks in ~/.claude/settings.json."
echo "   Add to .hooks.Stop[0].hooks, .hooks.SessionStart[0].hooks, and .hooks.SessionEnd[0].hooks (create structures if missing):"
echo ""
echo '       {'
echo '         "type": "command",'
echo '         "command": "~/bin/claude-status",'
echo '         "timeout": 5'
echo '       }'
echo ""
echo "   For a programmatic merge:"
echo ""
echo "       jq '.hooks.Stop[0].hooks = [{\"type\":\"command\",\"command\":\"~/bin/claude-status\",\"timeout\":5}] + (.hooks.Stop[0].hooks // [])' \\"
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
echo "4. The status bar populates after the next Claude Code Stop hook fires"
echo "   (i.e., after Claude finishes responding to your next message)."
