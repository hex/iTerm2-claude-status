# iTerm2-claude-status

Live model + context indicator for [Claude Code](https://docs.claude.com/en/docs/claude-code) sessions, rendered in iTerm2's status bar.

```
✦ Opus 4.7  ──●───────  244k (24%) 🟢
```

Driven by a Claude Code `Stop` hook that emits an OSC 1337 escape sequence to `/dev/tty` after each assistant turn. iTerm2 stores the value in a session-scoped user variable; an Interpolated String component reads it. Per-pane scoping — each iTerm2 pane shows only the Claude session running in *that* pane. Pure shell + jq, no Python runtime, no daemon, no polling. No row reserved in Claude Code's TUI.

## How it works

1. **`claude-status`** is registered as a `Stop` hook in `~/.claude/settings.json`. Claude Code invokes it after each assistant turn ends, piping session JSON to its stdin (containing `transcript_path`, `session_id`, etc.).
2. The script reads `transcript_path` from stdin (or falls back to mtime-based discovery), parses `message.usage` from the most recent assistant turn in the JSONL transcript, and renders the status string.
3. It writes an [OSC 1337 `SetUserVar`](https://iterm2.com/documentation-escape-codes.html) escape sequence to `/dev/tty`. iTerm2 stores the value as a session-scoped user variable named `claudeStatus`.
4. An **Interpolated String** component in iTerm2's status bar reads `\(user.claudeStatus)` and renders it.

Because Stop hooks are event-driven (not polled), the script only runs when there's actually new data to push. No polling overhead, no stale reads, no row reserved in Claude Code's TUI footer. If you'd rather use Claude Code's `statusLine` slot (which would also render the string in the TUI footer), see the alternate setup in [Configure as statusLine instead](#configure-as-statusline-instead).

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

### 1. Register claude-status as a Stop hook

In `~/.claude/settings.json`, add this to the `.hooks.Stop[0].hooks` array (create the structure if missing):

```json
{
  "type": "command",
  "command": "~/bin/claude-status",
  "timeout": 5
}
```

For an existing settings.json with other Stop hooks, the safest programmatic merge is:

```bash
jq '.hooks.Stop[0].hooks = [{"type":"command","command":"~/bin/claude-status","timeout":5}] + (.hooks.Stop[0].hooks // [])' \
  ~/.claude/settings.json > /tmp/settings.new && \
  mv /tmp/settings.new ~/.claude/settings.json
```

Adding it as the *first* entry means it runs before any blocking hook (e.g., a discoveries reminder).

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

Send any message in Claude Code. After Claude responds, the Stop hook fires and the iTerm2 status bar populates.

## Why a Stop hook?

Claude Code's [`statusLine` slot](https://code.claude.com/docs/en/statusline) is the more obvious place to put a status renderer — it's documented for exactly this purpose, receives a richer JSON payload via stdin, and fires on every conversation message change. We don't use it. Two reasons:

1. **Empty stdout still reserves a TUI row.** Claude Code allocates a screen row for the statusLine output even when the script prints nothing. For an iTerm2-status-bar-only tool, that row is a permanent blank line in your Claude Code footer. There's no setting to collapse it. A Stop hook's stdout is ignored entirely (Claude Code only inspects exit code + the `stop_hook_active` JSON field for "force continue" control signals), so empty output costs zero screen real estate.
2. **Same effective cadence, lower coupling.** Stop hooks fire once per assistant turn end. statusLine fires on every conversation message change (event-driven, ~300ms throttle). For "show me how full context is now," both update at roughly the same useful frequency — token counts only move per-turn. Switching to Stop hook also avoids replacing whatever statusLine command was already there (e.g., `claude-powerline`).

We considered other hook types and ruled them out:

- **`PostToolUse`** fires after each tool call, so it would update mid-turn. But each invocation runs *inline* with tool execution, adding ~150ms latency to every tool. Across a turn with many tool calls, the lag compounds.
- **`UserPromptSubmit`** fires before the new turn begins, so the latest assistant `message.usage` it can read is always one turn stale. Wrong moment.
- **`SessionStart`** / **`SessionEnd`** are too coarse — once-per-session, not once-per-turn.

If your preference is the opposite — you'd rather render the indicator in Claude Code's TUI footer *and* the iTerm2 bar, and you don't mind the row being there — see the next section.

## Configure as statusLine instead

Register `claude-status` as the `statusLine` command (instead of, or in addition to, a Stop hook):

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/bin/claude-status",
    "padding": 0
  }
}
```

Then change the last line of `src/claude-status.sh` from `/bin/echo -n ""` to `/bin/echo "$text"` so the footer renders the same string the iTerm2 bar shows.

## Customize

### Context window limit

The percentage divides token count by `CLAUDE_CONTEXT_LIMIT` (default `1000000`). To use the standard 200k Anthropic context, set the env var in your shell rc:

```bash
export CLAUDE_CONTEXT_LIMIT=200000
```

The hook inherits the value from Claude Code's process environment.

### Thresholds

Three buckets, configured at the bottom of `src/claude-status.sh`:
- 🟢 below 60%
- 🟡 60% – 84%
- 🔴 85% and above

Edit the script to taste. Symlinks point at the repo source, so changes take effect on Claude Code's next assistant turn.

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
- Remove the `claude-status` Stop hook entry from `~/.claude/settings.json`
- Remove the Interpolated String component from iTerm2

## Limitations

- **Per-pane scoping is intentional but absolute.** The user variable is set in the iTerm2 session where Claude Code is running. Other panes' status bars stay blank — they have no way of knowing about Claude sessions elsewhere.
- **Stop hook fires per assistant turn.** Mid-turn (while Claude is thinking), the bar shows the post-state of the *previous* turn. Token counts don't change mid-turn, so this is correct, but if you want a "Claude is working…" indicator that's a separate hook.
- **Context % reads cumulative transcript tokens.** The number reflects what's in the JSONL transcript file — if Claude Code has compacted the conversation internally, the displayed % may exceed what's actually loaded in working memory.
- **Model context-window mode (200k vs 1M) isn't auto-detected.** The transcript stores the base model id (`claude-opus-4-7`) without the `[1m]` suffix that indicates 1M-context mode. Configure via `CLAUDE_CONTEXT_LIMIT`.
- **macOS only.** Uses `stat -f`, `tail -r`, OSC 1337 (an iTerm2-specific escape sequence). Linux equivalents require porting `stat -c`, `tac`, and a different terminal that honors iTerm2 escapes.

## License

MIT — see [LICENSE](LICENSE).
