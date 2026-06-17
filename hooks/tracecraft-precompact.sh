#!/bin/sh
# tracecraft-precompact.sh — PreCompact hook: set checkpoint flag before context compression
#
# Only active when TRACECRAFT_TIMING=precompact in ~/.tracecraft-config.
# Sets the same flag file as tracecraft-stop.sh, picked up by tracecraft-autostart.sh
# on the next turn (post-compression).

[ "$TRACECRAFT" = "0" ] && exit 0
[ -f "$HOME/.tracecraft-disabled" ] && [ "$TRACECRAFT" != "1" ] && exit 0

[ -f ".claude/skills/tracecraft/SKILL.md" ] || \
[ -f "$HOME/.claude/skills/tracecraft/SKILL.md" ] || exit 0

# Load config
TRACECRAFT_MODEL=haiku
TRACECRAFT_TIMING=every
TRACECRAFT_LOCK_TIMEOUT=90
[ -f "$HOME/.tracecraft-config" ] && . "$HOME/.tracecraft-config"

# Only act when timing=precompact
[ "$TRACECRAFT_TIMING" = "precompact" ] || exit 0

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 | cut -c1-8)
[ -z "$SESSION_ID" ] && exit 0

for d in .tracecraft/*_${SESSION_ID}_*/; do
    [ -d "$d" ] || continue
    FLAG_DIR="/tmp/tracecraft-checkpoint"
    mkdir -p "$FLAG_DIR" 2>/dev/null || exit 0
    echo "$d" > "$FLAG_DIR/${SESSION_ID}" 2>/dev/null
    exit 0
done

exit 0
