#!/usr/bin/env bash
# ABOUTME: Claude Code Stop/SessionStart hook. Emits an OSC 1337 SetUserVar to
# ABOUTME: /dev/tty so iTerm2 renders model + context via \(user.claudeStatus).

set -u

CONTEXT_LIMIT="${CLAUDE_CONTEXT_LIMIT:-1000000}"
TRACK_LEN=10
PROJECTS_DIR="$HOME/.claude/projects"

input=""
if [ -p /dev/stdin ]; then
  input=$(</dev/stdin)
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

model_id=""
tokens=0
if [ -n "${transcript:-}" ] && [ -f "$transcript" ]; then
  # Stream from the end; jq emits one TSV row per assistant turn. head -n1
  # closes the pipe on first match, jq dies via SIGPIPE — O(1) memory.
  data=$(
    /usr/bin/tail -r "$transcript" 2>/dev/null \
    | /usr/bin/jq -r 'select(.type=="assistant" and .message.usage)
        | [ .message.model // "unknown",
            ( (.message.usage.input_tokens // 0)
            + (.message.usage.cache_creation_input_tokens // 0)
            + (.message.usage.cache_read_input_tokens // 0) ) ]
        | @tsv' 2>/dev/null \
    | /usr/bin/head -n1
  )
  [ -n "$data" ] && IFS=$'\t' read -r model_id tokens <<<"$data"
fi

# Fresh-session fallback: empty transcript means model_id stayed "". Get it
# from the SessionStart stdin JSON instead; tokens stays at 0.
if [ -z "$model_id" ] && [ -n "$input" ]; then
  model_id=$(/usr/bin/jq -r '.model.id // .model.display_name // .model // "unknown"' <<<"$input" 2>/dev/null)
fi
if [ -z "$model_id" ] || [ "$model_id" = "null" ]; then
  model_id="unknown"
fi

if [[ "$model_id" =~ ^claude-([a-z]+)-([0-9]+)-([0-9]+) ]]; then
  fam_lower="${BASH_REMATCH[1]}"
  family="$(/usr/bin/tr '[:lower:]' '[:upper:]' <<<"${fam_lower:0:1}")${fam_lower:1}"
  display_model="$family ${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
else
  family="Unknown"
  display_model="$model_id"
fi

case "$family" in
  Opus)   glyph="✦" ;;
  Sonnet) glyph="✧" ;;
  Haiku)  glyph="✱" ;;
  *)      glyph="✱" ;;
esac

pct=$((tokens * 100 / CONTEXT_LIMIT))
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

# Brace group catches shell-level redirect errors (e.g. "Device not configured"
# when invoked without a controlling tty) along with the command's own stderr.
b64=$(/bin/echo -n "$text" | /usr/bin/base64)
osc=$(/usr/bin/printf '\033]1337;SetUserVar=claudeStatus=%s\007' "$b64")
if [ -n "${TMUX:-}" ]; then
  { /usr/bin/printf '\033Ptmux;\033%s\033\\' "$osc" > /dev/tty; } 2>/dev/null || true
else
  { /usr/bin/printf '%s' "$osc" > /dev/tty; } 2>/dev/null || true
fi
