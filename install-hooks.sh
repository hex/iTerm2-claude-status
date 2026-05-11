#!/usr/bin/env bash
# ABOUTME: Idempotently registers ~/bin/claude-status as Stop, SessionStart,
# ABOUTME: and SessionEnd hooks in ~/.claude/settings.json. Appends only —
# ABOUTME: never overwrites existing hook entries.

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
COMMAND="~/bin/claude-status"
EVENTS=(Stop SessionStart SessionEnd)

if [ ! -f "$SETTINGS" ]; then
    echo "ERROR: $SETTINGS does not exist. Run Claude Code at least once first." >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required. Install with: brew install jq" >&2
    exit 1
fi

tmp="$(mktemp -t claude-status-settings.XXXXXX)"
trap 'rm -f "$tmp" "$tmp.new"' EXIT
cp "$SETTINGS" "$tmp"

added=()
already=()

for evt in "${EVENTS[@]}"; do
    present=$(jq --arg c "$COMMAND" --arg e "$evt" \
      '((.hooks[$e] // []) | map((.hooks // []) | map(.command) | any(. == $c)) | any) // false' \
      "$tmp")
    if [ "$present" = "true" ]; then
        already+=("$evt")
        continue
    fi

    jq --arg e "$evt" --arg c "$COMMAND" '
      .hooks[$e] //= [{"hooks":[]}]
      | .hooks[$e][0].hooks //= []
      | .hooks[$e][0].hooks |= ([{"type":"command","command":$c,"timeout":5}] + .)
    ' "$tmp" > "$tmp.new"
    jq -e ".hooks[\"$evt\"]" "$tmp.new" > /dev/null
    mv "$tmp.new" "$tmp"
    added+=("$evt")
done

if [ "${#added[@]}" -eq 0 ]; then
    echo "claude-status already registered in all hook events: ${already[*]}"
    echo "settings.json unchanged."
    exit 0
fi

backup="$SETTINGS.bak.$(date +%s)"
cp "$SETTINGS" "$backup"
mv "$tmp" "$SETTINGS"

echo "Registered claude-status hook in: ${added[*]}"
[ "${#already[@]}" -gt 0 ] && echo "Already present in: ${already[*]} (left as-is)"
echo "Backup: $backup"
echo ""
echo "Hooks fire on the next assistant turn (Stop), pane open (SessionStart),"
echo "and session exit (SessionEnd). Run claude-status manually now if you"
echo "want to populate the bar immediately."
