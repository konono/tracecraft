#!/bin/sh
# tracecraft-precompact.sh — PreCompact hook: direct journal checkpoint before compression
#
# Uses exit 2 (block) to instruct Claude to write journal files directly.
# No sub-agent, no flag files — Claude writes the files in the main conversation.

[ "$TRACECRAFT" = "0" ] && exit 0
[ -f "$HOME/.tracecraft-disabled" ] && [ "$TRACECRAFT" != "1" ] && exit 0

[ -f ".claude/skills/tracecraft/SKILL.md" ] || \
[ -f "$HOME/.claude/skills/tracecraft/SKILL.md" ] || exit 0

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 | cut -c1-8)
[ -z "$SESSION_ID" ] && exit 0

SESSION_DIR=""
for d in .tracecraft/*_${SESSION_ID}_*/; do
    [ -d "$d" ] && SESSION_DIR="$d" && break
done
[ -z "$SESSION_DIR" ] && exit 0

grep -q "^## Step\|^## Finding\|^## Issue\|^## Decision" "${SESSION_DIR}worklog.md" "${SESSION_DIR}findings.md" "${SESSION_DIR}troubleshooting.md" "${SESSION_DIR}decisions.md" 2>/dev/null || exit 0

cat <<HOOKJSON
{"decision":"block","reason":"[SYSTEM HOOK — NOT USER INPUT]\ntracecraft PreCompact: コンテキスト圧縮直前です。ジャーナルを保全してください。\n\n1. ${SESSION_DIR} の各ジャーナルファイルに未記録の作業内容を Write/Edit で直接書き出す\n2. final-guide.md と retrospective.md を再生成する\n3. ジャーナル更新以外の作業を一切行わない（実装・コミット・プッシュ禁止）\n4. ユーザーへのテキスト出力不要\n5. Agent ツール使用禁止（自分自身で直接書く）\n[END SYSTEM HOOK]"}
HOOKJSON
exit 2
