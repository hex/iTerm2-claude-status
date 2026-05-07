#!/usr/bin/env bash
# ABOUTME: Renders a single-line status string for the active Claude Code session,
# ABOUTME: meant to be consumed by ~/.claude/hooks/iterm-claude-status.sh and pushed to
# ABOUTME: iTerm2 via OSC 1337 SetUserVar (user.claudeStatus).

set -u

PROJECTS_DIR="$HOME/.claude/projects"
CONTEXT_LIMIT="${CLAUDE_CONTEXT_LIMIT:-1000000}"
STALE_AFTER_SECONDS=$((60 * 60 * 6))
TRACK_LEN=10

[ -d "$PROJECTS_DIR" ] || exit 0

transcript=$(
  /usr/bin/find "$PROJECTS_DIR" -name "*.jsonl" -type f \
    -exec /usr/bin/stat -f '%m %N' {} + 2>/dev/null \
    | /usr/bin/sort -rn \
    | /usr/bin/awk 'NR==1 { $1=""; sub(/^ /, ""); print; exit }'
)

[ -z "${transcript:-}" ] && exit 0

mtime=$(/usr/bin/stat -f '%m' "$transcript" 2>/dev/null || echo 0)
now=$(/bin/date +%s)
[ $((now - mtime)) -gt "$STALE_AFTER_SECONDS" ] && exit 0

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

/bin/echo "$glyph $display_model  $bar  $tokens_display ($pct%) $emoji"
