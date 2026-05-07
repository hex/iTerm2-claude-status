#!/usr/bin/env bash
# ABOUTME: Claude Code statusLine command. Outputs the status string to stdout
# ABOUTME: (becomes Claude Code's footer) AND emits OSC 1337 to /dev/tty (drives
# ABOUTME: iTerm2's user.claudeStatus var). Reads the Claude Code session JSON
# ABOUTME: from stdin when invoked as a statusLine; falls back to latest-mtime
# ABOUTME: transcript discovery when invoked manually.

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

[ -z "${transcript:-}" ] && exit 0
[ ! -f "$transcript" ] && exit 0

# 2. Extract model + token usage from the most recent assistant turn.
data=$(
  /usr/bin/tail -r "$transcript" 2>/dev/null \
  | /usr/bin/jq -rs '
      map(select(.type=="assistant" and .message.usage))[0]
      | [ .message.model // "unknown",
          ( (.message.usage.input_tokens // 0)
          + (.message.usage.cache_creation_input_tokens // 0)
          + (.message.usage.cache_read_input_tokens // 0) ) ]
      | @tsv
    ' 2>/dev/null
)

[ -z "${data:-}" ] && exit 0

model_id="${data%	*}"
tokens="${data##*	}"

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

# 3. Side effect: push to iTerm2 via OSC 1337 SetUserVar.
#    Skip if /dev/tty isn't writable (e.g. invoked from a non-TTY subprocess).
if [ -w /dev/tty ]; then
  b64=$(/bin/echo -n "$text" | /usr/bin/base64)
  osc=$(/usr/bin/printf '\033]1337;SetUserVar=claudeStatus=%s\007' "$b64")
  if [ -n "${TMUX:-}" ]; then
    /usr/bin/printf '\033Ptmux;\033%s\033\\' "$osc" > /dev/tty
  else
    /usr/bin/printf '%s' "$osc" > /dev/tty
  fi
fi

# 4. Primary output: stdout = Claude Code's footer string.
/bin/echo "$text"
