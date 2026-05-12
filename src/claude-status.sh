#!/usr/bin/env bash
# ABOUTME: Claude Code Stop/SessionStart/SessionEnd hook. Resolves the user's
# ABOUTME: TTY and emits OSC 1337 SetUserVar so iTerm2 renders user.claudeStatus.

set -u

TRACK_LEN=10
PROJECTS_DIR="$HOME/.claude/projects"

# All visual elements are overrideable via env vars. `${VAR-default}` keeps the
# default only when the var is unset, so `export FOO=""` explicitly disables.
EMOJI_LOW="${CLAUDE_STATUS_EMOJI_LOW-🟢}"
EMOJI_MID="${CLAUDE_STATUS_EMOJI_MID-🟡}"
EMOJI_HIGH="${CLAUDE_STATUS_EMOJI_HIGH-🔴}"

GLYPH_OPUS="${CLAUDE_STATUS_GLYPH_OPUS-✦}"
GLYPH_SONNET="${CLAUDE_STATUS_GLYPH_SONNET-✧}"
GLYPH_HAIKU="${CLAUDE_STATUS_GLYPH_HAIKU-✱}"
GLYPH_UNKNOWN="${CLAUDE_STATUS_GLYPH_UNKNOWN-✱}"

BAR_FILL="${CLAUDE_STATUS_BAR_FILL-●}"
BAR_EMPTY="${CLAUDE_STATUS_BAR_EMPTY-─}"

find_tty() {
  # Hook subprocesses have no controlling terminal (Claude Code setsid's them),
  # so /dev/tty fails. Find the user's actual TTY device path via env var or
  # by walking up the process tree.
  if [ -n "${TTY:-}" ] && [ -w "$TTY" ]; then
    /bin/echo "$TTY"; return 0
  fi
  local p="$PPID"
  while [ -n "$p" ] && [ "$p" != "1" ] && [ "$p" != "0" ]; do
    local t
    t=$(/bin/ps -p "$p" -o tty= 2>/dev/null | /usr/bin/tr -d ' ')
    if [ -n "$t" ] && [ "$t" != "??" ] && [ -w "/dev/$t" ]; then
      /bin/echo "/dev/$t"; return 0
    fi
    p=$(/bin/ps -p "$p" -o ppid= 2>/dev/null | /usr/bin/tr -d ' ')
  done
  return 1
}

emit_osc() {
  local b64
  b64=$(/bin/echo -n "$1" | /usr/bin/base64)
  local osc
  osc=$(/usr/bin/printf '\033]1337;SetUserVar=claudeStatus=%s\007' "$b64")
  local seq
  if [ -n "${TMUX:-}" ]; then
    seq=$(/usr/bin/printf '\033Ptmux;\033%s\033\\' "$osc")
  else
    seq="$osc"
  fi

  local target
  target=$(find_tty) || return 0
  /usr/bin/printf '%s' "$seq" >> "$target" 2>/dev/null || true
}

input=""
if [ ! -t 0 ]; then
  # Read stdin with a per-line 1s timeout so we never hang on edge cases
  # (open-but-empty stdin from non-pipe environments). Hooks fire fast,
  # so the timeout never triggers in real invocations.
  while IFS= read -r -t 1 line 2>/dev/null; do
    input+="$line"$'\n'
  done
fi

hook_event=""
if [ -n "$input" ]; then
  hook_event=$(/usr/bin/jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null)
fi

# SessionEnd path: clear the bar so it doesn't show ghost data after Claude exits.
if [ "$hook_event" = "SessionEnd" ]; then
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
  Opus)   glyph="$GLYPH_OPUS"   ;;
  Sonnet) glyph="$GLYPH_SONNET" ;;
  Haiku)  glyph="$GLYPH_HAIKU"  ;;
  *)      glyph="$GLYPH_UNKNOWN" ;;
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
  if [ "$i" -eq "$pos" ]; then bar="${bar}${BAR_FILL}"; else bar="${bar}${BAR_EMPTY}"; fi
  i=$((i + 1))
done

if [ "$tokens" -ge 1000 ]; then
  tokens_display="$((tokens / 1000))k"
else
  tokens_display="$tokens"
fi

if   [ "$pct" -ge 85 ]; then emoji="$EMOJI_HIGH"
elif [ "$pct" -ge 60 ]; then emoji="$EMOJI_MID"
else                          emoji="$EMOJI_LOW"
fi

emit_osc "$glyph $display_model  $bar  $tokens_display ($pct%) $emoji"
