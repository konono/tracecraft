#!/bin/sh
# tracecraft-stop.sh — Stop hook: set checkpoint flag (non-blocking, silent)
#
# Behavior depends on TRACECRAFT_TIMING (set by install.sh):
#   every       — set flag on every turn (default)
#   off         — do nothing
#   precompact  — do nothing (PreCompact hook handles it)
#   interval:N  — set flag every N turns

[ "$TRACECRAFT" = "0" ] && exit 0
[ -f "$HOME/.tracecraft-disabled" ] && [ "$TRACECRAFT" != "1" ] && exit 0

[ -f ".claude/skills/tracecraft/SKILL.md" ] || \
[ -f "$HOME/.claude/skills/tracecraft/SKILL.md" ] || exit 0

# Settings (rendered by install.sh)
TRACECRAFT_MODEL=__TRACECRAFT_MODEL__
TRACECRAFT_TIMING=__TRACECRAFT_TIMING__
TRACECRAFT_LOCK_TIMEOUT=__TRACECRAFT_LOCK_TIMEOUT__

case "$TRACECRAFT_TIMING" in
    off|precompact) exit 0 ;;
esac

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 | cut -c1-8)
[ -z "$SESSION_ID" ] && exit 0

# Check for active journal session
for d in .tracecraft/*_${SESSION_ID}_*/; do
    [ -d "$d" ] || continue

    # Handle interval:N timing
    case "$TRACECRAFT_TIMING" in
        interval:*)
            N=$(echo "$TRACECRAFT_TIMING" | cut -d: -f2)
            [ -z "$N" ] && N=5
            COUNTER_DIR="/tmp/tracecraft-interval"
            mkdir -p "$COUNTER_DIR" 2>/dev/null || exit 0
            COUNTER_FILE="$COUNTER_DIR/${SESSION_ID}"
            COUNT=0
            [ -f "$COUNTER_FILE" ] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
            COUNT=$(( COUNT + 1 ))
            if [ "$COUNT" -ge "$N" ]; then
                COUNT=0
                # Fall through to set flag
            else
                echo "$COUNT" > "$COUNTER_FILE" 2>/dev/null
                exit 0
            fi
            echo "$COUNT" > "$COUNTER_FILE" 2>/dev/null
            ;;
    esac

    FLAG_DIR="/tmp/tracecraft-checkpoint"
    mkdir -p "$FLAG_DIR" 2>/dev/null || exit 0
    echo "$d" > "$FLAG_DIR/${SESSION_ID}" 2>/dev/null
    exit 0
done

exit 0
