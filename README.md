# iTerm2-claude-status

Live model + context indicator for [Claude Code](https://docs.claude.com/en/docs/claude-code) sessions, rendered in iTerm2's status bar.

```
✦ Opus 4.7  ──●───────  244k (24%) 🟢
```

Updates after every assistant turn. Per-pane scoping — each iTerm2 pane shows only the Claude session running in *that* pane. Pure shell + jq, no Python runtime, no daemon, no polling.

## How it works

Three components, push-based:

1. **`claude-status`** (`src/claude-status.sh`) — finds the most-recent Claude Code transcript JSONL under `~/.claude/projects/`, extracts the model name and `message.usage` from the last assistant turn, and prints a single line: glyph + model + bar + token count + percentage + threshold emoji.
2. **`iterm-claude-status.sh`** (`src/iterm-claude-status.sh`) — Claude Code Stop hook. Runs `claude-status`, base64-encodes the output, writes an OSC 1337 `SetUserVar=claudeStatus=<b64>` escape sequence to `/dev/tty`. iTerm2 stores the value as a session-scoped user variable.
3. **iTerm2 Interpolated String component** — reads `\(user.claudeStatus)` and renders it in the status bar.

The Stop hook fires after each assistant turn, so the bar updates exactly when context changes — no polling, no stale reads. Token counts inside an assistant turn are static, so per-turn refresh is the right cadence.

## Install

### From source

```bash
git clone https://github.com/hex/iTerm2-claude-status.git ~/GitHub/iTerm2-claude-status
cd ~/GitHub/iTerm2-claude-status
./install.sh
```

### Homebrew

```bash
brew tap hex/tap
brew install iterm2-claude-status
```

Both methods install:
- `claude-status` (binary on PATH)
- `iterm-claude-status.sh` (Claude Code Stop hook)

## Configure

After install, three steps remain — none of which touch your dotfiles automatically.

### 1. Register the Stop hook in `~/.claude/settings.json`

Add this object to the `.hooks.Stop[0].hooks` array (create the structure if missing):

```json
{
  "type": "command",
  "command": "~/.claude/hooks/iterm-claude-status.sh",
  "timeout": 5
}
```

For an existing settings.json with other Stop hooks, the safest programmatic merge is:

```bash
jq '.hooks.Stop[0].hooks += [{"type":"command","command":"~/.claude/hooks/iterm-claude-status.sh","timeout":5}]' \
  ~/.claude/settings.json > /tmp/settings.new && \
  mv /tmp/settings.new ~/.claude/settings.json
```

### 2. Add the iTerm2 status bar component

`Settings → Profiles → Session → Configure Status Bar…` → drag in **Interpolated String**, gear icon → Configure Component:

| Field | Value |
|---|---|
| Expression | `\(user.claudeStatus)` |
| Foreground color | Auto (or any theme color) |
| Priority | `10` |

In the Configure Status Bar dialog, **Advanced…** → set layout to **Tight Packing** so the segment sizes to its content.

### 3. (tmux users only) Enable OSC passthrough

tmux strips OSC 1337 sequences by default. Add to `~/.config/tmux/tmux.conf`:

```
set -g allow-passthrough on
```

The hook already detects `$TMUX` and wraps the OSC in tmux's passthrough envelope; you just need passthrough enabled on tmux's side.

### 4. Trigger an update

Send any message in Claude Code. After the response, the Stop hook fires and the bar populates.

## Customize

### Context window limit

The percentage divides token count by `CLAUDE_CONTEXT_LIMIT` (default `1000000`). To use the standard 200k Anthropic context, set the env var in your shell rc:

```bash
export CLAUDE_CONTEXT_LIMIT=200000
```

The hook script inherits the value from the Claude Code process environment.

### Thresholds

Three buckets, configured at the bottom of `src/claude-status.sh`:
- 🟢 below 60%
- 🟡 60% – 84%
- 🔴 85% and above

Edit the script to taste. Symlinks point at the repo source, so changes take effect immediately on the next Stop hook fire.

### Per-family glyph

- **✦** Opus
- **✧** Sonnet
- **✱** Haiku (and unknown models)

Mapping at the `case "$family" in ... esac` block in `claude-status.sh`.

### Bar resolution

`TRACK_LEN=10` (default) gives 10 dot positions across the full context window. With a 1M limit, the dot stays at index 0 for any percentage below 12% — you'll spend the first ~110k tokens of any session looking at `●─────────`. To get finer low-end resolution, lower `CLAUDE_CONTEXT_LIMIT` or raise `TRACK_LEN`.

## Uninstall

```bash
cd ~/GitHub/iTerm2-claude-status
./uninstall.sh
```

The script removes only the symlinks it created. You'll still need to manually:
- Remove the hook entry from `~/.claude/settings.json`
- Remove the Interpolated String component from iTerm2

## Limitations

- **Per-pane scoping is intentional but absolute.** The user variable is set in the iTerm2 session where Claude Code is running. Other panes' status bars stay blank — they have no way of knowing about Claude sessions elsewhere.
- **Bar only updates per assistant turn.** Mid-turn (while you're waiting for Claude to think), the bar shows the post-state of the *previous* turn. Token counts don't change mid-turn, so this is correct, but if you want a "Claude is working…" indicator that's a separate hook.
- **Context % reads cumulative transcript tokens.** The number reflects what's in the JSONL transcript file — if Claude Code has compacted the conversation internally, the displayed % may exceed what's actually loaded in working memory.
- **Model context-window mode (200k vs 1M) isn't auto-detected.** The transcript stores the base model id (`claude-opus-4-7`) without the `[1m]` suffix that indicates 1M-context mode. Configure via `CLAUDE_CONTEXT_LIMIT`.
- **macOS only.** Uses `stat -f`, `tail -r`, OSC 1337 (an iTerm2-specific escape sequence). Linux equivalents require porting `stat -c`, `tac`, and a different terminal that honors iTerm2 escapes.

## License

MIT — see [LICENSE](LICENSE).
