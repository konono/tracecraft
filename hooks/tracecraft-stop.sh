#!/bin/sh
# tracecraft-stop.sh — Stop hook: set checkpoint flag (non-blocking, silent)
#
# This hook exits 0 with NO output — it is completely invisible to the user.
# It only touches a flag file that the UserPromptSubmit hook picks up on the
# next turn to trigger a deferred checkpoint via background Agent.
#
# Why non-blocking:
#   - exit 2 (block) causes "Stop hook error: ..." to appear in conversation
#   - There is no way to suppress this display in Claude Code
#   - Non-blocking + deferred checkpoint keeps the conversation clean

[ "$TRACECRAFT" = "0" ] && exit 0
[ -f "$HOME/.tracecraft-disabled" ] && [ "$TRACECRAFT" != "1" ] && exit 0

[ -f ".claude/skills/tracecraft/SKILL.md" ] || \
[ -f "$HOME/.claude/skills/tracecraft/SKILL.md" ] || exit 0

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 | cut -c1-8)
[ -z "$SESSION_ID" ] && exit 0

# Check for active journal session
for d in .tracecraft/*_${SESSION_ID}_*/; do
    [ -d "$d" ] || continue
    # Journal exists — set checkpoint flag
    FLAG_DIR="/tmp/tracecraft-checkpoint"
    mkdir -p "$FLAG_DIR" 2>/dev/null || exit 0
    echo "$d" > "$FLAG_DIR/${SESSION_ID}" 2>/dev/null
    exit 0
done

exit 0
