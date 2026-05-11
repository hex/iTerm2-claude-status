#!/usr/bin/env bash
# ABOUTME: Removes ~/bin/claude-status entries from Stop, SessionStart, and
# ABOUTME: SessionEnd hooks in ~/.claude/settings.json. Leaves other hooks
# ABOUTME: in those arrays intact.

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
COMMAND="~/bin/claude-status"
EVENTS=(Stop SessionStart SessionEnd)

if [ ! -f "$SETTINGS" ]; then
    echo "Nothing to do: $SETTINGS does not exist."
    exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required. Install with: brew install jq" >&2
    exit 1
fi

tmp="$(mktemp -t claude-status-settings.XXXXXX)"
trap 'rm -f "$tmp" "$tmp.new"' EXIT
cp "$SETTINGS" "$tmp"

removed=()

for evt in "${EVENTS[@]}"; do
    before=$(jq --arg e "$evt" --arg c "$COMMAND" \
      '((.hooks[$e] // []) | map((.hooks // []) | map(.command) | map(select(. == $c)) | length) | add) // 0' \
      "$tmp")

    jq --arg e "$evt" --arg c "$COMMAND" '
      if (.hooks[$e] // []) | length == 0 then .
      else .hooks[$e][0].hooks |= (. | map(select(.command != $c)))
      end
    ' "$tmp" > "$tmp.new"
    jq -e . "$tmp.new" > /dev/null
    mv "$tmp.new" "$tmp"

    [ "$before" -gt 0 ] && removed+=("$evt")
done

if [ "${#removed[@]}" -eq 0 ]; then
    echo "claude-status not registered in any hook event. settings.json unchanged."
    exit 0
fi

backup="$SETTINGS.bak.$(date +%s)"
cp "$SETTINGS" "$backup"
mv "$tmp" "$SETTINGS"

echo "Removed claude-status hook from: ${removed[*]}"
echo "Other hook entries in those arrays were left intact."
echo "Backup: $backup"
