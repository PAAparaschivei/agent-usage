#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
helper="$root/dist/Agent Usage.app/Contents/Helpers/agent-usage-claude-capture"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export AGENT_USAGE_CLAUDE_CACHE="$scratch/status.json"
"$helper" < "$root/examples/claude-status.json"
test "$(/usr/bin/plutil -extract rate_limits.five_hour.used_percentage raw "$AGENT_USAGE_CLAUDE_CACHE")" = "22"
test "$(/usr/bin/plutil -extract rate_limits.seven_day.used_percentage raw "$AGENT_USAGE_CLAUDE_CACHE")" = "31"
! grep -E 'fixture-marker|Example model' "$AGENT_USAGE_CLAUDE_CACHE"
printf '{}\n' | "$helper"
test "$(/usr/bin/plutil -extract rate_limits.five_hour.used_percentage raw "$AGENT_USAGE_CLAUDE_CACHE")" = "22"
