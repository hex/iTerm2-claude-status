# iTerm2-claude-status

Live model + context indicator for [Claude Code](https://docs.claude.com/en/docs/claude-code) sessions, rendered in iTerm2's status bar.

```
✦ Opus 4.7  ──●───────  244k (24%) 🟢
```

Driven by a Claude Code `statusLine` command that emits an OSC 1337 escape sequence as a side effect. Claude Code's own footer stays blank by design — this tool is iTerm2-status-bar only. Updates whenever Claude Code's conversation messages change (event-driven, throttled at 300ms by Claude Code itself). Per-pane scoping — each iTerm2 pane shows only the Claude session running in *that* pane. Pure shell + jq, no Python runtime, no daemon, no polling.

## How it works

1. **`claude-status`** is registered as Claude Code's [`statusLine` command](https://code.claude.com/docs/en/statusline). Claude Code pipes session JSON to its stdin (containing `transcript_path`, `model`, etc.) and invokes the script on each conversation message change.
2. The script writes an [OSC 1337 `SetUserVar`](https://iterm2.com/documentation-escape-codes.html) escape sequence to `/dev/tty`. iTerm2 stores the value as a session-scoped user variable named `claudeStatus`.
3. The script's stdout is intentionally empty, so Claude Code's footer stays blank.
4. An **Interpolated String** component in iTerm2's status bar reads `\(user.claudeStatus)` and renders it.

Because Claude Code's statusLine is event-driven (not polled), the script only runs when there's actually new data to push. No polling overhead, no stale reads. To also see the indicator in Claude Code's footer, change the last line of `src/claude-status.sh` from `/bin/echo -n ""` to `/bin/echo "$text"`.

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

Both methods install a single binary `claude-status` on your PATH.

## Configure

Three steps — none touch your dotfiles automatically.

### 1. Set claude-status as your Claude Code statusLine

In `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/bin/claude-status",
    "padding": 0
  }
}
```

If you previously used a different statusLine command (e.g. `claude-powerline`), this replaces it. The footer will switch to claude-status's compact one-line format.

### 2. Add the iTerm2 status bar component

`Settings → Profiles → Session → Configure Status Bar…` → drag in **Interpolated String**, gear icon → Configure Component:

| Field | Value |
|---|---|
| Expression | `\(user.claudeStatus)` |
| Foreground color | Auto (or any theme color) |
| Priority | `10` |

Then `Advanced…` → set layout to **Tight Packing** so the segment sizes to its content rather than getting a fixed slot.

### 3. (tmux users only) Enable OSC passthrough

tmux strips OSC 1337 sequences by default. Add to your `tmux.conf`:

```
set -g allow-passthrough on
```

The script detects `$TMUX` and wraps the OSC in tmux's passthrough envelope; you just need passthrough enabled on tmux's side.

### 4. Trigger the first render

Send any message in Claude Code. After Claude responds, the statusLine fires and both surfaces populate.

## Customize

### Context window limit

The percentage divides token count by `CLAUDE_CONTEXT_LIMIT` (default `1000000`). To use the standard 200k Anthropic context, set the env var in your shell rc:

```bash
export CLAUDE_CONTEXT_LIMIT=200000
```

The statusLine command inherits the value from Claude Code's process environment.

### Thresholds

Three buckets, configured at the bottom of `src/claude-status.sh`:
- 🟢 below 60%
- 🟡 60% – 84%
- 🔴 85% and above

Edit the script to taste. Symlinks point at the repo source, so changes take effect on Claude Code's next render.

### Per-family glyph

- **✦** Opus
- **✧** Sonnet
- **✱** Haiku (and unknown models)

Mapping at the `case "$family" in ... esac` block in `claude-status.sh`.

### Bar resolution

`TRACK_LEN=10` (default) gives 10 dot positions across the full context window. With a 1M limit, the dot stays at index 0 for any percentage below 12% — you'll spend the first ~110k tokens of any session looking at `●─────────`. Lower `CLAUDE_CONTEXT_LIMIT` or raise `TRACK_LEN` for finer low-end resolution.

## Uninstall

```bash
cd ~/GitHub/iTerm2-claude-status
./uninstall.sh
```

The script removes only the symlink it created. You'll still need to manually:
- Restore your previous `statusLine` command in `~/.claude/settings.json` (or remove the block)
- Remove the Interpolated String component from iTerm2

## Limitations

- **Per-pane scoping is intentional but absolute.** The user variable is set in the iTerm2 session where Claude Code is running. Other panes' status bars stay blank — they have no way of knowing about Claude sessions elsewhere.
- **Replaces your current statusLine.** If you used claude-powerline or another statusLine command, this takes its place. Restore the old one via uninstall.sh's instructions if you switch back.
- **Context % reads cumulative transcript tokens.** The number reflects what's in the JSONL transcript file — if Claude Code has compacted the conversation internally, the displayed % may exceed what's actually loaded in working memory.
- **Model context-window mode (200k vs 1M) isn't auto-detected.** The transcript stores the base model id (`claude-opus-4-7`) without the `[1m]` suffix that indicates 1M-context mode. Configure via `CLAUDE_CONTEXT_LIMIT`.
- **macOS only.** Uses `stat -f`, `tail -r`, OSC 1337 (an iTerm2-specific escape sequence). Linux equivalents require porting `stat -c`, `tac`, and a different terminal that honors iTerm2 escapes.

## License

MIT — see [LICENSE](LICENSE).
