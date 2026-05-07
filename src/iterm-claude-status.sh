#!/usr/bin/env bash
# ABOUTME: Stop hook. Runs claude-status and pushes the single-line output
# ABOUTME: to iTerm2's user.claudeStatus var via OSC 1337.

set -u

/bin/cat > /dev/null

text=$(claude-status 2>/dev/null)
[ -z "${text:-}" ] && exit 0

b64=$(/bin/echo -n "$text" | /usr/bin/base64)
osc=$(/usr/bin/printf '\033]1337;SetUserVar=claudeStatus=%s\007' "$b64")

if [ -n "${TMUX:-}" ]; then
  /usr/bin/printf '\033Ptmux;\033%s\033\\' "$osc" > /dev/tty 2>/dev/null
else
  /usr/bin/printf '%s' "$osc" > /dev/tty 2>/dev/null
fi

exit 0
