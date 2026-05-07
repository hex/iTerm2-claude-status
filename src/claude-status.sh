#!/usr/bin/env bash
# ABOUTME: Claude Code Stop/SessionStart/SessionEnd hook. Emits an OSC 1337
# ABOUTME: SetUserVar to /dev/tty so iTerm2 renders model + context in user.claudeStatus.

set -u

TRACK_LEN=10
PROJECTS_DIR="$HOME/.claude/projects"

emit_osc() {
  local b64
  b64=$(/bin/echo -n "$1" | /usr/bin/base64)
  local osc
  osc=$(/usr/bin/printf '\033]1337;SetUserVar=claudeStatus=%s\007' "$b64")
  if [ -n "${TMUX:-}" ]; then
    { /usr/bin/printf '\033Ptmux;\033%s\033\\' "$osc" > /dev/tty; } 2>/dev/null || true
  else
    { /usr/bin/printf '%s' "$osc" > /dev/tty; } 2>/dev/null || true
  fi
}

input=""
if [ -p /dev/stdin ]; then
  input=$(</dev/stdin)
fi

# SessionEnd path: clear the bar so it doesn't show ghost data after Claude exits.
if [ -n "$input" ] && \
   [ "$(/usr/bin/jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null)" = "SessionEnd" ]; then
  emit_osc ""
  exit 0
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
  # Stream from the end; head -n1 closes the pipe on first match, jq dies via
  # SIGPIPE — O(1) memory.
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

# Per-family context-window default. Override with CLAUDE_CONTEXT_LIMIT env var.
# Opus 4.x defaults to 1M tokens; Sonnet/Haiku default to 200k. Unknown models
# get the most generous default (1M) so they don't show >100% before the user
# realizes they need to override.
if [ -n "${CLAUDE_CONTEXT_LIMIT:-}" ]; then
  CONTEXT_LIMIT="$CLAUDE_CONTEXT_LIMIT"
else
  case "$family" in
    Opus)             CONTEXT_LIMIT=1000000 ;;
    Sonnet|Haiku)     CONTEXT_LIMIT=200000  ;;
    *)                CONTEXT_LIMIT=1000000 ;;
  esac
fi

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

emit_osc "$glyph $display_model  $bar  $tokens_display ($pct%) $emoji"
