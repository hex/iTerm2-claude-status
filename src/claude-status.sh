#!/usr/bin/env bash
# ABOUTME: Claude Code Stop hook command. Reads transcript JSONL and emits an
# ABOUTME: OSC 1337 SetUserVar to /dev/tty so iTerm2 can render the active
# ABOUTME: model + context in its status bar via \(user.claudeStatus).
# ABOUTME: stdout is intentionally empty. Falls back to latest-mtime transcript
# ABOUTME: discovery when stdin contains no transcript_path.

set -u

CONTEXT_LIMIT="${CLAUDE_CONTEXT_LIMIT:-1000000}"
TRACK_LEN=10
PROJECTS_DIR="$HOME/.claude/projects"

# 1. Get transcript path: prefer stdin JSON (Claude Code statusLine provides it).
input=""
if [ -p /dev/stdin ]; then
  input=$(/bin/cat)
fi

transcript=""
if [ -n "$input" ]; then
  transcript=$(/usr/bin/jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)
fi

if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
  [ -d "$PROJECTS_DIR" ] || exit 0
  transcript=$(
    /usr/bin/find "$PROJECTS_DIR" -name "*.jsonl" -type f \
      -exec /usr/bin/stat -f '%m %N' {} + 2>/dev/null \
      | /usr/bin/sort -rn \
      | /usr/bin/awk 'NR==1 { $1=""; sub(/^ /, ""); print; exit }'
  )
fi

# 2. Extract model + token usage from the most recent assistant turn.
#    If the transcript is missing or has no assistant messages yet (e.g.,
#    SessionStart fires before any turns have happened), fall back to the
#    model from the stdin JSON and zero tokens — produces a baseline
#    "fresh session" status.
data=""
if [ -n "${transcript:-}" ] && [ -f "$transcript" ]; then
  data=$(
    /usr/bin/tail -r "$transcript" 2>/dev/null \
    | /usr/bin/jq -rs '
        map(select(.type=="assistant" and .message.usage))
        | select(length > 0)
        | .[0]
        | [ .message.model // "unknown",
            ( (.message.usage.input_tokens // 0)
            + (.message.usage.cache_creation_input_tokens // 0)
            + (.message.usage.cache_read_input_tokens // 0) ) ]
        | @tsv
      ' 2>/dev/null
  )
fi

if [ -n "${data:-}" ]; then
  model_id="${data%	*}"
  tokens="${data##*	}"
else
  # Fresh session path: get model from stdin JSON, tokens=0.
  model_id=""
  if [ -n "$input" ]; then
    model_id=$(/usr/bin/jq -r '.model.id // .model.display_name // .model // "unknown"' <<<"$input" 2>/dev/null)
  fi
  [ -z "${model_id:-}" ] || [ "$model_id" = "null" ] && model_id="unknown"
  tokens=0
fi

read -r family display_model < <(
  /bin/echo "$model_id" \
  | /usr/bin/awk -F'-' '
      /^claude-/ {
        fam = toupper(substr($2, 1, 1)) substr($2, 2);
        printf "%s %s %s.%s\n", fam, fam, $3, $4;
        exit
      }
      { printf "Unknown %s\n", $0; exit }
    '
)

case "$family" in
  Opus)   glyph="✦" ;;
  Sonnet) glyph="✧" ;;
  Haiku)  glyph="✱" ;;
  *)      glyph="✱" ;;
esac

pct=$((tokens * 100 / CONTEXT_LIMIT))
[ "$pct" -lt 0 ] && pct=0
[ "$pct" -gt 100 ] && pct=100

pos=$(( pct * (TRACK_LEN - 1) / 100 ))

bar=""
i=0
while [ "$i" -lt "$TRACK_LEN" ]; do
  if [ "$i" -eq "$pos" ]; then bar="${bar}●"; else bar="${bar}─"; fi
  i=$((i + 1))
done

if [ "$tokens" -ge 1000 ]; then
  tokens_display="$((tokens / 1000))k"
else
  tokens_display="$tokens"
fi

if   [ "$pct" -ge 85 ]; then emoji="🔴"
elif [ "$pct" -ge 60 ]; then emoji="🟡"
else                          emoji="🟢"
fi

text="$glyph $display_model  $bar  $tokens_display ($pct%) $emoji"

# 3. Side effect: push to iTerm2 via OSC 1337 SetUserVar. Brace group
#    redirects shell-level errors (e.g. "Device not configured" when there's
#    no controlling terminal) along with the command's own stderr.
b64=$(/bin/echo -n "$text" | /usr/bin/base64)
osc=$(/usr/bin/printf '\033]1337;SetUserVar=claudeStatus=%s\007' "$b64")
if [ -n "${TMUX:-}" ]; then
  { /usr/bin/printf '\033Ptmux;\033%s\033\\' "$osc" > /dev/tty; } 2>/dev/null || true
else
  { /usr/bin/printf '%s' "$osc" > /dev/tty; } 2>/dev/null || true
fi

# 4. Primary output: empty stdout. Claude Code's footer stays blank — this
#    script is iTerm2-status-bar only. To restore the footer rendering, change
#    the next line back to: /bin/echo "$text"
/bin/echo -n ""
